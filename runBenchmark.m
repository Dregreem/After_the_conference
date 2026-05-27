%% RUNBENCHMARK - Automated multi-scenario, multi-controller benchmark
%
% Uses the same lean two-rate inline loop as CompareYield.m — no
% runSimulation() wrapper — for dramatically faster runs.
%
% BUGS FIXED vs previous versions:
%   1. P_net subtracted zero motor cost (Power_Total logged after P_net).
%   2. generateComparisonReport crashed: bar() scalar vs array FaceColor.
%   3. Dead controlLDR call — ldr_locked computed but never used (removed).
%   4. results pre-alloc: results(nS,nC)=struct(...) left earlier elements
%      with success=[] — now uses repmat on a scalar template.
%   5. Scenario/PVGIS hardcoded outside scenario loop: second scenario entry
%      would silently use wrong PVGIS data — moved inside loop.
%   6. valid = incidence_log > 0 guessing: replaced with explicit
%      processed_log boolean to mark true daytime steps cleanly.
%
% COMPAREDYIELD TACTICS FULLY PORTED:
%   * Two-rate loop: outer 1 Hz (sun/PVGIS/FSM/log), inner 100 Hz (PID+servo)
%   * Inline power: IAM-corrected fixed panel; gross tracker via body-Z
%   * Motor parasitic: I_SPIN_BASE + velocity-proportional; zero in HOLD/IDLE
%   * P_net = max(0, gross-motor) computed AFTER motor, BEFORE logging
%   * trapz() for all energy integrals
%   * Servo initialised at actual sun position at t_start
%   * Body frame refreshed from FINAL servo angles after inner loop
%   * FSM time breakdown printed per run
%
% USAGE:  runBenchmark

clear; clc;
addpath(genpath(pwd));

%% ── CONFIGURATION ────────────────────────────────────────────────────────────
SCENARIOS   = {'SOLAR_DAY'};
CONTROLLERS = {'pid', 'fuzzy'};
dt_outer    = 0.01;                       % [s] outer: sun/PVGIS/FSM/log
dt_inner    = 0.01;                       % [s] inner: PID+servo
N_sub       = round(dt_outer / dt_inner); % = 100

%% ── OUTPUT DIRECTORY ─────────────────────────────────────────────────────────
timestamp = char(datetime('now','Format','yyyy-MM-dd_HH-mm-ss'));
bench_dir = fullfile('Results', sprintf('Benchmark_%s', timestamp));
mkdir(bench_dir);

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║              SOLAR TRACKER BENCHMARK RUNNER                 ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');
fprintf('  Output     : %s\n', bench_dir);
fprintf('  Scenarios  : %s\n', strjoin(SCENARIOS,  ', '));
fprintf('  Controllers: %s\n', strjoin(CONTROLLERS,', '));
fprintf('  dt_outer   : %.2f s  (sun/PVGIS/FSM/log)\n', dt_outer);
fprintf('  dt_inner   : %.4f s  (PID+servo, %d sub-steps)\n\n', dt_inner, N_sub);

%% ── SHARED PHYSICAL CONSTANTS ────────────────────────────────────────────────
PANEL_AREA  = 1.0;    % [m²]
ETA_PANEL   = 0.20;
TILT_DEG    = 41.0;   % Istanbul latitude — south-facing fixed tilt
b0          = 0.05;   % ASHRAE IAM coefficient
I_SPIN_BASE = 0.17;   % no-load spinning current per axis [A]
V_SUPPLY    = 6.0;    % servo supply [V]

% Fixed panel normal (ENU: south = −Y, up = +Z)
N_fixed = [0; -sind(TILT_DEG); cosd(TILT_DEG)];
N_fixed = N_fixed / norm(N_fixed);

% Servo MaxSpeed (needed for parasitic model) — query once
tmpSt = struct('Angle',0,'Velocity',0,'Current',0,'Energy',0);
[~, ~, ServoProps] = stepTheoreticalServo(tmpSt, 0, dt_inner, 'Pan');

%% ── FSM PARAMS (calibrated — identical to CompareYield.m) ───────────────────
SP = struct( ...
    'night_threshold',     0.10, ...
    'sun_lost_threshold',  0.15, ...
    'sun_found_threshold', 0.30, ...
    'lock_threshold',      0.50, ...  % [°] incidence threshold for "locked"
    'tracking_deadband',   3.0,  ...
    'batch_interval',      180.0, ...
    'max_burst_time',      10.0, ...
    'search_speed',        3.0,  ...
    'zenith_pan_lock',     false, ...
    'rate_filter_alpha',   0.95);

%% ── RESULTS — safe pre-alloc via repmat (fixes results(nS,nC)=struct bug) ────
nS = length(SCENARIOS);
nC = length(CONTROLLERS);
tmpl    = struct('scenario','','controller','','Metrics',struct(),'Log',struct(),'success',false);
results = repmat(tmpl, nS, nC);

%% ══════════════════════════════════════════════════════════════════════════════
%% MAIN BENCHMARK LOOP
%% ══════════════════════════════════════════════════════════════════════════════
for s = 1:nS
    for c = 1:nC
        scen = SCENARIOS{s};
        ctrl = CONTROLLERS{c};

        fprintf('──────────────────────────────────────────────\n');
        fprintf('  Running: %-12s | %-6s\n', scen, upper(ctrl));
        fprintf('──────────────────────────────────────────────\n');

        try
            tic;

            %% ── Load scenario + PVGIS inside loop (supports multi-scenario) ──
            Scenario    = generateScenario(scen);
            PVData_full = loadPVGIS(Scenario.pvgis_file);
            [PVData, DayStats] = filterPVGISbyDate( ...
                PVData_full, Scenario.analysis_mode, Scenario.analysis_date);

            fprintf('  Date: %s  G_peak=%.1f W/m²  Daylight=%.1f h  H=%.1f Wh/m²\n', ...
                string(DayStats.date,'dd-MMM-yyyy'), DayStats.peak_irradiance, ...
                DayStats.daylight_hours, DayStats.daily_insolation);

            %% ── Time vector (outer 1 Hz grid) ───────────────────────────────
            t_start_s = Scenario.t_start_hour * 3600;
            t_end_s   = t_start_s + Scenario.duration_sec;
            time_vec  = (t_start_s : dt_outer : t_end_s)';
            N         = length(time_vec);
            SimDate   = DayStats.date + hours(Scenario.t_start_hour);

            %% ── Pre-allocate log arrays ──────────────────────────────────────
            G_log         = zeros(N,1);
            P_fixed_log   = zeros(N,1);
            P_gross_log   = zeros(N,1);
            P_motor_log   = zeros(N,1);
            P_net_log     = zeros(N,1);
            incidence_log = zeros(N,1);
            locked_log    = false(N,1);
            processed_log = false(N,1);  % marks steps that were not skipped
            FSM_log       = repmat({'IDLE'}, N, 1);

            %% ── Initialise servo at actual sun position at t_start ────────────
            [~, el_init, az_init] = getSunVector( ...
                Scenario.lat, Scenario.lon, SimDate, Scenario.tz);
            if el_init > 0
                ip = az_init; if ip > 180, ip = ip - 360; end
                it = max(-90, min(90, 90 - el_init));
                [p0, t0, ~, ~] = applyFlipLogic(ip, it);
                StatePan  = struct('Angle',p0, 'Velocity',0,'Current',0,'Energy',0);
                StateTilt = struct('Angle',t0, 'Velocity',0,'Current',0,'Energy',0);
            else
                StatePan  = struct('Angle',0,  'Velocity',0,'Current',0,'Energy',0);
                StateTilt = struct('Angle',80, 'Velocity',0,'Current',0,'Energy',0);
            end
            fprintf('  Init: Pan=%.1f°  Tilt=%.1f°  (Sun el=%.1f°  az=%.1f°)\n', ...
                StatePan.Angle, StateTilt.Angle, el_init, az_init);

            %% ── State variables ──────────────────────────────────────────────
            FSM_State = struct('mode','TRACKING', ...
                'e_pan_prev',0,'e_tilt_prev',0, ...
                'de_pan_filtered',0,'de_tilt_filtered',0, ...
                'search_phase',0,'hold_timer',0,'burst_timer',0, ...
                'was_night',false,'park_target_pan',0,'park_target_tilt',90);
            ControlState     = struct('I_pan',0,'I_tilt',0,'de_pan_filt',0,'de_tilt_filt',0);
            CommandSmoothing = struct('target_pan_smoothed',  StatePan.Angle, ...
                                     'target_tilt_smoothed', StateTilt.Angle);

            %% ════════════════════════════════════════════════════════════════
            %% OUTER LOOP  (1 Hz)
            %% ════════════════════════════════════════════════════════════════
            for i = 1:N

                sim_t        = time_vec(i);
                current_time = SimDate + seconds(sim_t - t_start_s);

                % ── PVGIS irradiance — shift by timezone (PVGIS is UTC, sim is local)
                [G_now, ~] = getPVGISatTime(sim_t - Scenario.tz * 3600, PVData);
                G_log(i)   = G_now;

                % ── Sun position (moves 0.004°/s — valid for all 100 sub-steps)
                [S_vec, elevation, azimuth] = getSunVector( ...
                    Scenario.lat, Scenario.lon, current_time, Scenario.tz);

                % Skip night / very low irradiance — leave logs at zero
                if elevation <= 0 || G_now < 1
                    FSM_log{i} = 'IDLE';
                    continue;
                end

                % ── Fixed panel power (IAM-corrected, computed once per second)
                cos_f = max(0, dot(S_vec, N_fixed));
                IAM_f = 0;
                if cos_f > 0.01, IAM_f = max(0, 1 - b0*(1/cos_f - 1)); end
                P_fixed_log(i) = G_now * PANEL_AREA * ETA_PANEL * cos_f * IAM_f;

                % ── Ideal tracker angles + flip ───────────────────────────────
                [az_deg, el_deg] = cartesian2spherical(S_vec);
                ideal_pan  = az_deg; if ideal_pan > 180, ideal_pan = ideal_pan - 360; end
                ideal_tilt = max(-90, min(90, 90 - el_deg));
                [adj_pan, adj_tilt, is_flip, is_reachable] = applyFlipLogic(ideal_pan, ideal_tilt);

                % ── LDR voltages (needed by FSM) — pre-inner-loop body frame ──
                theta_p = StatePan.Angle; theta_t = StateTilt.Angle;
                cp = cosd(theta_p); sp = sind(theta_p);
                ct = cosd(theta_t); st = sind(theta_t);
                Sx_pre = cp*S_vec(1) - sp*S_vec(2);
                Sy_pre = sp*S_vec(1) + cp*S_vec(2);
                Sb_pre = [Sx_pre; ct*Sy_pre - st*S_vec(3); st*Sy_pre + ct*S_vec(3)];
                Sbn_pre = Sb_pre / (norm(Sb_pre) + 1e-8);
                [~, LDR_V, ~,~,~,~] = readLDRs(Sbn_pre);

                % ── FSM supervisor (1 Hz — slow decision-maker by design) ──────
                [ErrorSignal, FSM_State, ~, ~] = StateManagerFSM( ...
                    LDR_V, Sb_pre, theta_p, theta_t, ...
                    FSM_State, SP, dt_outer, is_flip);

                fsm_active = ismember(FSM_State.mode, {'TRACKING','SEARCH','PARK'});

                %% ══════════════════════════════════════════════════════════
                %% INNER LOOP  (100 Hz — PID/FLC + servo)
                %% Slow quantities (S_vec, ErrorSignal, adj_pan/tilt,
                %% is_flip, is_reachable) held constant from outer step.
                %% ══════════════════════════════════════════════════════════
                for sub = 1:N_sub

                    % Controller
                    if strcmp(ctrl,'fuzzy')
                        [VelCmd, ControlState, ~, ~] = FuzzyLogicController( ...
                            ErrorSignal, ControlState, dt_inner);
                    else
                        [VelCmd, ControlState, ~, ~] = PID_VelocityController( ...
                            ErrorSignal, ControlState, struct(), dt_inner);
                    end

                    % Velocity → position (joint limits)
                    tgt_pan  = max(-180, min(180, StatePan.Angle  + VelCmd.v_pan  * dt_inner));
                    tgt_tilt = max(-90,  min(90,  StateTilt.Angle + VelCmd.v_tilt * dt_inner));

                    % Geometric sun-aim blend — identical to CompareYield
                    if is_reachable && fsm_active
                        tgt_pan  = tgt_pan  + 0.5*(adj_pan  - tgt_pan);
                        tgt_tilt = tgt_tilt + 0.5*(adj_tilt - tgt_tilt);
                    end

                    % Command smoothing
                    smooth_a = 0.95;
                    if fsm_active
                        CommandSmoothing.target_pan_smoothed  = ...
                            (1-smooth_a)*CommandSmoothing.target_pan_smoothed  + smooth_a*tgt_pan;
                        CommandSmoothing.target_tilt_smoothed = ...
                            (1-smooth_a)*CommandSmoothing.target_tilt_smoothed + smooth_a*tgt_tilt;
                    else
                        % HOLD/IDLE — freeze so motors de-energise
                        CommandSmoothing.target_pan_smoothed  = StatePan.Angle;
                        CommandSmoothing.target_tilt_smoothed = StateTilt.Angle;
                    end

                    % Servo plant
                    [StatePan,  ~,~] = stepTheoreticalServo( ...
                        StatePan,  CommandSmoothing.target_pan_smoothed,  dt_inner,'Pan');
                    [StateTilt, ~,~] = stepTheoreticalServo( ...
                        StateTilt, CommandSmoothing.target_tilt_smoothed, dt_inner,'Tilt');

                end  %% end inner loop ─────────────────────────────────────────

                %% Post-outer: refresh body frame from FINAL servo angles ───────
                pf = StatePan.Angle;  tf = StateTilt.Angle;
                cp2=cosd(pf); sp2=sind(pf); ct2=cosd(tf); st2=sind(tf);
                Sx2 = cp2*S_vec(1) - sp2*S_vec(2);
                Sy2 = sp2*S_vec(1) + cp2*S_vec(2);
                Sb2 = [Sx2; ct2*Sy2 - st2*S_vec(3); st2*Sy2 + ct2*S_vec(3)];
                Sbn2 = Sb2 / (norm(Sb2) + 1e-8);

                % Incidence angle (body-Z dot product with sun unit vector)
                cos_t     = max(0, Sbn2(3));
                theta_inc = acosd(min(1, cos_t));

                % Tracker gross power (IAM-corrected) — same formula as CompareYield
                IAM_t = 0;
                if cos_t > 0.01, IAM_t = max(0, 1 - b0*(1/cos_t - 1)); end
                P_gross_log(i) = G_now * PANEL_AREA * ETA_PANEL * cos_t * IAM_t;

                % Motor parasitic — zero in HOLD/IDLE, same as CompareYield
                is_hold = ismember(FSM_State.mode, {'HOLD','IDLE'});
                if is_hold
                    I_motor = 0;
                else
                    vr = (abs(StatePan.Velocity) + abs(StateTilt.Velocity)) / ...
                         (ServoProps.MaxSpeed + 1e-6);
                    I_motor = I_SPIN_BASE + vr * 0.33;
                end
                P_motor_log(i) = I_motor * V_SUPPLY * 2;

                % Net tracker power — MUST be assigned AFTER P_motor_log(i)
                P_net_log(i) = max(0, P_gross_log(i) - P_motor_log(i));

                % Logging
                incidence_log(i) = theta_inc;
                locked_log(i)    = theta_inc < SP.lock_threshold;
                processed_log(i) = true;
                FSM_log{i}       = FSM_State.mode;

            end  %% end outer loop ─────────────────────────────────────────────

            elapsed = toc;

            %% ── FSM time breakdown (same print as CompareYield) ──────────────
            n_track = sum(strcmp(FSM_log,'TRACKING')) * dt_outer;
            n_hold  = sum(strcmp(FSM_log,'HOLD'))     * dt_outer;
            n_srch  = sum(strcmp(FSM_log,'SEARCH'))   * dt_outer;
            n_idle  = sum(strcmp(FSM_log,'IDLE'))     * dt_outer;
            fprintf('  Done in %.1f s\n', elapsed);
            fprintf('  FSM: TRACKING=%ds | HOLD=%ds | SEARCH=%ds | IDLE=%ds\n', ...
                n_track, n_hold, n_srch, n_idle);

            %% ── Metrics ──────────────────────────────────────────────────────
            % Use processed_log to identify true daytime steps cleanly
            day_idx = processed_log;
            M = struct();
            if any(day_idx)
                M.mean_incidence = mean(incidence_log(day_idx));
                M.max_incidence  = max(incidence_log(day_idx));
            else
                M.mean_incidence = NaN;
                M.max_incidence  = NaN;
            end
            M.lock_percentage      = 100 * sum(locked_log) * dt_outer / Scenario.duration_sec;
            M.lock_time_s          = sum(locked_log) * dt_outer;
            M.total_energy_Wh      = trapz(time_vec, P_motor_log) / 3600;
            M.tracker_yield_Wh     = trapz(time_vec, P_gross_log) / 3600;
            M.fixed_yield_Wh       = trapz(time_vec, P_fixed_log) / 3600;
            M.net_tracker_yield_Wh = trapz(time_vec, P_net_log)   / 3600;
            if M.fixed_yield_Wh > 0
                M.gain_vs_fixed = 100 * (M.net_tracker_yield_Wh - M.fixed_yield_Wh) / M.fixed_yield_Wh;
            else
                M.gain_vs_fixed = 0;
            end
            M.parasitic_ratio = 100 * M.total_energy_Wh / (M.tracker_yield_Wh + 1e-9);
            M.scenario   = scen;
            M.controller = ctrl;

            % Pack log for .mat save
            L.time_vec     = time_vec;
            L.G            = G_log;
            L.P_fixed      = P_fixed_log;
            L.P_tracker    = P_gross_log;
            L.P_motor      = P_motor_log;
            L.P_net        = P_net_log;
            L.incidence    = incidence_log;
            L.locked       = locked_log;
            L.processed    = processed_log;
            L.FSM_mode     = FSM_log;

            results(s,c).scenario   = scen;
            results(s,c).controller = ctrl;
            results(s,c).Metrics    = M;
            results(s,c).Log        = L;
            results(s,c).success    = true;

            fprintf('    Mean error:    %.3f°  |  Max: %.3f°\n', M.mean_incidence, M.max_incidence);
            fprintf('    Lock:          %.1f%%\n',   M.lock_percentage);
            fprintf('    Motor energy:  %.4f Wh  (parasitic ratio %.2f%%)\n', ...
                M.total_energy_Wh, M.parasitic_ratio);
            fprintf('    Tracker gross: %.4f Wh  |  Fixed: %.4f Wh\n', ...
                M.tracker_yield_Wh, M.fixed_yield_Wh);
            fprintf('    Tracker net:   %.4f Wh\n',  M.net_tracker_yield_Wh);
            fprintf('    Gain vs fixed: %+.1f%%\n\n', M.gain_vs_fixed);

            run_dir  = fullfile(bench_dir, sprintf('%s_%s', scen, upper(ctrl)));
            mkdir(run_dir);
            mat_file = fullfile(run_dir, sprintf('%s_%s.mat', scen, ctrl));
            save(mat_file, 'L', 'M', '-v7.3');
            fprintf('  Saved: %s\n\n', mat_file);

        catch ME
            results(s,c).scenario   = scen;
            results(s,c).controller = ctrl;
            results(s,c).success    = false;
            fprintf('  ✗ FAILED: %s\n', ME.message);
            if ~isempty(ME.stack)
                fprintf('    Line %d in %s\n\n', ME.stack(1).line, ME.stack(1).name);
            end
        end
    end
end

%% ── CONSOLE SUMMARY TABLE ────────────────────────────────────────────────────
fprintf('\n╔══════════════════════════════════════════════════════════════════════════════════╗\n');
fprintf('║  BENCHMARK RESULTS SUMMARY                                                    ║\n');
fprintf('╠══════════════════════════════════════════════════════════════════════════════════╣\n');
fprintf('║ %-14s %-8s %9s %9s %10s %13s %10s ║\n', ...
    'Scenario','Ctrl','MeanErr°','Lock%','MotorWh','TrackerNetWh','Gain%');
fprintf('╠══════════════════════════════════════════════════════════════════════════════════╣\n');
for s = 1:nS
    for c = 1:nC
        r = results(s,c);
        if r.success && ~isempty(fieldnames(r.Metrics))
            M = r.Metrics;
            fprintf('║ %-14s %-8s %9.3f %9.1f %10.4f %13.4f %10.1f ║\n', ...
                r.scenario, upper(r.controller), ...
                M.mean_incidence, M.lock_percentage, ...
                M.total_energy_Wh, M.net_tracker_yield_Wh, M.gain_vs_fixed);
        else
            fprintf('║ %-14s %-8s %9s %9s %10s %13s %10s ║\n', ...
                r.scenario, upper(r.controller), ...
                'FAIL','FAIL','FAIL','FAIL','FAIL');
        end
    end
end
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% ── COMPARISON REPORT ────────────────────────────────────────────────────────
generateComparisonReport_fixed(results, bench_dir);
fprintf('✓ Benchmark complete.  Results saved to: %s\n\n', bench_dir);


%% ══════════════════════════════════════════════════════════════════════════════
%% LOCAL FUNCTION: generateComparisonReport_fixed
%% ══════════════════════════════════════════════════════════════════════════════
function generateComparisonReport_fixed(results, output_dir)
if nargin < 2 || isempty(output_dir), output_dir = 'Results'; end

[nS, nC] = size(results);

%% CSV ────────────────────────────────────────────────────────────────────────
csv_file = fullfile(output_dir,'comparison_summary.csv');
fid = fopen(csv_file,'w');
fprintf(fid,'Scenario,Controller,Mean_Error_deg,Max_Error_deg,Lock_Pct,');
fprintf(fid,'Motor_Wh,Tracker_Gross_Wh,Tracker_Net_Wh,Fixed_Wh,Net_Gain_Pct,Parasitic_Pct\n');
for s = 1:nS
    for c = 1:nC
        r = results(s,c);
        if r.success && ~isempty(fieldnames(r.Metrics))
            M = r.Metrics;
            fprintf(fid,'%s,%s,%.4f,%.4f,%.2f,%.6f,%.6f,%.6f,%.6f,%.2f,%.3f\n', ...
                r.scenario, upper(r.controller), ...
                sfg(M,'mean_incidence'),      sfg(M,'max_incidence'), ...
                sfg(M,'lock_percentage'),     sfg(M,'total_energy_Wh'), ...
                sfg(M,'tracker_yield_Wh'),    sfg(M,'net_tracker_yield_Wh'), ...
                sfg(M,'fixed_yield_Wh'),      sfg(M,'gain_vs_fixed'), ...
                sfg(M,'parasitic_ratio'));
        else
            fprintf(fid,'%s,%s,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN\n', ...
                r.scenario, upper(r.controller));
        end
    end
end
fclose(fid);
fprintf('  ✓ CSV saved: %s\n', csv_file);

%% Build data matrices ─────────────────────────────────────────────────────────
scenarios   = unique({results(:).scenario},   'stable');
controllers = unique({results(:).controller}, 'stable');
nS2 = numel(scenarios);
nC2 = numel(controllers);

palette = [0.20 0.45 0.75;   % blue   — PID
           0.93 0.51 0.15;   % orange — fuzzy
           0.22 0.56 0.24;   % green
           0.76 0.22 0.22];  % red
if nC2 > size(palette,1), palette = lines(nC2); end

mat_mean   = nan(nS2,nC2);
mat_energy = nan(nS2,nC2);
mat_yield  = nan(nS2,nC2);
mat_lock   = nan(nS2,nC2);
mat_gain   = nan(nS2,nC2);

for s = 1:nS
    for c = 1:nC
        r = results(s,c);
        if ~r.success || isempty(fieldnames(r.Metrics)), continue; end
        si = find(strcmp(scenarios,   r.scenario),   1);
        ci = find(strcmp(controllers, r.controller), 1);
        if isempty(si)||isempty(ci), continue; end
        M = r.Metrics;
        mat_mean(si,ci)   = sfg(M,'mean_incidence');
        mat_energy(si,ci) = sfg(M,'total_energy_Wh');
        mat_yield(si,ci)  = sfg(M,'net_tracker_yield_Wh');
        mat_lock(si,ci)   = sfg(M,'lock_percentage');
        mat_gain(si,ci)   = sfg(M,'gain_vs_fixed');
    end
end
ctrl_labels = upper(controllers);

%% Figure 1: 3-subplot ─────────────────────────────────────────────────────────
fig = figure('Visible','off','Name','Controller Comparison','NumberTitle','off');
set(fig,'Position',[100 100 1400 900]);
specs = { ...
    mat_mean,   'Mean Incidence Error [°]', 'Tracking Accuracy — Mean Incidence Error',   '%.3f°', 'lower';  ...
    mat_energy, 'Motor Energy [Wh]',        'Energy Consumption — Total Motor Energy',    '%.4f',  'lower';  ...
    mat_yield,  'Net Tracker Yield [Wh]',   'Energy Harvest — Net Yield (Gross − Motor)', '%.4f',  'higher'};
for p = 1:3
    ax = subplot(3,1,p);
    bh = bar(ax, specs{p,1}, 'grouped');
    colorBarsSafely(bh, palette, nC2);
    set(ax,'XTick',1:nS2,'XTickLabel',scenarios,'FontSize',11,'FontName','Arial');
    ylabel(ax, specs{p,2},'FontSize',11,'FontName','Arial');
    title(ax,  specs{p,3},'FontSize',12,'FontName','Arial','FontWeight','bold');
    subtitle(ax, sprintf('%s is better', specs{p,5}),'FontSize',10);
    legend(ax, ctrl_labels,'Location','best','FontSize',10);
    grid(ax,'on'); ax.YGrid='on'; ax.XGrid='off';
    addValueLabels(ax, bh, specs{p,4});
end
sgtitle('Solar Tracker Controller Comparison','FontSize',14,'FontName','Arial','FontWeight','bold');
saveFig(fig, fullfile(output_dir,'controller_comparison.png'));
close(fig);

%% Figure 2: 5 panels + text ───────────────────────────────────────────────────
fig2 = figure('Visible','off','Name','Extended Comparison','NumberTitle','off');
set(fig2,'Position',[100 100 1400 1100]);
ext = { ...
    mat_mean,   'Mean Incidence Error [°]','Tracking Accuracy',     '%.3f°',   'lower';  ...
    mat_energy, 'Motor Energy [Wh]',       'Motor Energy',          '%.4f',    'lower';  ...
    mat_yield,  'Net Tracker Yield [Wh]',  'Net Tracker Yield',     '%.4f',    'higher'; ...
    mat_lock,   'Lock Time [%]',           'Alignment Lock %',      '%.1f%%',  'higher'; ...
    mat_gain,   'Gain vs Fixed [%]',       'Gain over Fixed Panel', '%+.1f%%', 'higher'};
for m = 1:5
    ax = subplot(3,2,m);
    bh = bar(ax, ext{m,1}, 'grouped');
    colorBarsSafely(bh, palette, nC2);
    set(ax,'XTick',1:nS2,'XTickLabel',scenarios,'FontSize',10,'FontName','Arial');
    ylabel(ax, ext{m,2},'FontSize',10,'FontName','Arial');
    title(ax,  ext{m,3},'FontSize',11,'FontName','Arial','FontWeight','bold');
    subtitle(ax, sprintf('%s is better', ext{m,5}),'FontSize',9);
    legend(ax, ctrl_labels,'Location','best','FontSize',9);
    grid(ax,'on'); ax.YGrid='on'; ax.XGrid='off';
    addValueLabels(ax, bh, ext{m,4});
end
ax6 = subplot(3,2,6);
axis(ax6,'off');
ltxt = {'BENCHMARK SUMMARY',' '};
for s = 1:nS
    for c = 1:nC
        r = results(s,c);
        if r.success && ~isempty(fieldnames(r.Metrics))
            M = r.Metrics;
            ltxt{end+1} = sprintf('%s | %s:',    upper(r.scenario), upper(r.controller)); %#ok
            ltxt{end+1} = sprintf('  Err=%.3f°  Lock=%.1f%%', ...
                sfg(M,'mean_incidence'), sfg(M,'lock_percentage')); %#ok
            ltxt{end+1} = sprintf('  Net=%.3fWh  Gain=%+.1f%%  Para=%.2f%%', ...
                sfg(M,'net_tracker_yield_Wh'), sfg(M,'gain_vs_fixed'), ...
                sfg(M,'parasitic_ratio')); %#ok
            ltxt{end+1} = ' '; %#ok
        end
    end
end
text(ax6,0.05,0.95,ltxt,'Units','normalized','FontSize',9,'FontName','Courier', ...
    'VerticalAlignment','top','BackgroundColor',[0.95 0.95 0.95]);
sgtitle('Extended Controller Comparison Dashboard','FontSize',13,'FontName','Arial','FontWeight','bold');
saveFig(fig2, fullfile(output_dir,'extended_comparison.png'));
close(fig2);

fprintf('  ✓ Report generation complete.\n');
end  % generateComparisonReport_fixed


%% ── LOCAL HELPERS ────────────────────────────────────────────────────────────

function v = sfg(s, field)
    if isfield(s,field) && ~isempty(s.(field)) && ~isnan(s.(field))
        v = s.(field);
    else
        v = NaN;
    end
end

function colorBarsSafely(bh, palette, nC2)
% Colours bar series without crashing when bar() returns a GraphicsPlaceholder.
% This happens with all-NaN data columns — the original crash site.
    for ci = 1:min(numel(bh), nC2)
        try
            bh(ci).FaceColor = palette(ci,:);
            bh(ci).EdgeColor = 'none';
            bh(ci).FaceAlpha = 0.85;
        catch
            % GraphicsPlaceholder for all-NaN column — skip silently
        end
    end
end

function addValueLabels(ax, bar_handles, fmt)
    hold(ax,'on');
    for bi = 1:numel(bar_handles)
        try
            xd = bar_handles(bi).XEndPoints;
            yd = bar_handles(bi).YEndPoints;
        catch
            continue;
        end
        for k = 1:numel(xd)
            if ~isnan(yd(k))
                yoff = max(abs(yd(k))*0.02, diff(ylim(ax))*0.01);
                text(ax, xd(k), yd(k)+yoff, sprintf(fmt,yd(k)), ...
                    'HorizontalAlignment','center','VerticalAlignment','bottom', ...
                    'FontSize',8,'FontName','Arial');
            end
        end
    end
end

function saveFig(fig, fpath)
    try
        exportgraphics(fig, fpath,'Resolution',200);
        fprintf('  ✓ Chart saved: %s\n', fpath);
    catch
        saveas(fig, fpath);
        fprintf('  ✓ Chart saved (fallback): %s\n', fpath);
    end
end