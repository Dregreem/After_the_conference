%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║           CompareYield.m — Fixed vs Dual-Axis Tracker               ║
%% ║           Master's-Level Academic Yield Analysis                     ║
%% ║           Uses PVGIS real irradiance via generateScenario()          ║
%% ║           Three reference days → Annual extrapolation                ║
%% ╚══════════════════════════════════════════════════════════════════════╝
%
%  SUB-STEPPING STRATEGY (no dt change required)
%  ─────────────────────────────────────────────────────────────────────
%  Problem:  PID (Ki=10.317) and stepTheoreticalServo were tuned for
%            dt=0.01 s in main_easy.m.  At dt=1 s the integrator hits
%            anti-windup in 2 steps and the servo overshoots ~15°/step
%            while the sun moves only 0.004°/step.
%
%  Solution: TWO nested loops — no architectural changes:
%
%    OUTER loop  dt_outer=1 s  (slow physics — barely changes in 1 s)
%      • getPVGISatTime()   → irradiance changes <0.1 W/m²/s
%      • getSunVector()     → sun moves 0.004°/s  → valid for 100 sub-steps
%      • StateManagerFSM()  → supervisor is a slow decision-maker (1 Hz fine)
%      • energy logging     → trapz on 1 s grid (unchanged)
%
%    INNER loop  dt_inner=0.01 s  × N_sub=100 per outer step
%      • PID_VelocityController / FuzzyLogicController
%      • stepTheoreticalServo
%      Uses the sun vector cached from the outer step → zero accuracy loss.
%
%  Runtime: ~8–12 s per reference day — same as original dt=1 s version,
%  because N_sub×dt_inner = dt_outer  (same total simulated time).
%  ─────────────────────────────────────────────────────────────────────

clear; clc; close all;
addpath(genpath(pwd));

%% ════════════════════════════════════════════════════════════════════════
%% GEOGRAPHIC CONFIGURATION — Single source of truth for location params
%% ════════════════════════════════════════════════════════════════════════
%  Usage: set loc_name before running to switch location, e.g.:
%    loc_name = 'HELSINKI'; CompareYield
%  Available: 'ISTANBUL', 'HELSINKI', 'ASWAN'
if ~exist('loc_name', 'var'), loc_name = 'ISTANBUL'; end
Geo = getGeoConfig(loc_name);

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║       FIXED vs TRACKER — ANNUAL YIELD COMPARISON            ║\n');
fprintf('║  %-52s  ║\n', [Geo.Name, ' | PVGIS | Three-Day Method']);
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% ════════════════════════════════════════════════════════════════════════
%% ░░░░░░░░░░░░░  CHANGE ONLY THESE 2 PARAMETERS  ░░░░░░░░░░░░░░░░░░░░░░
%% ════════════════════════════════════════════════════════════════════════

CONTROL_MODE  = 'pid';          % 'pid' or 'fuzzy'  — identical to main_easy.m
PHYSICS_MODEL = 'THEORETICAL';  % THEORETICAL = stepTheoreticalServo

%% ════════════════════════════════════════════════════════════════════════
%% TIMESTEPS
%% ════════════════════════════════════════════════════════════════════════

dt_outer = 1.00;                        % [s] outer step: sun / PVGIS / FSM / log
dt_inner = 0.01;                        % [s] inner step: PID + servo (matches main_easy.m)
N_sub    = round(dt_outer / dt_inner);  % = 100 sub-steps per outer step

fprintf('CONTROL_MODE  : %s\n',   upper(CONTROL_MODE));
fprintf('PHYSICS_MODEL : %s\n',   PHYSICS_MODEL);
fprintf('dt_outer      : %.2f s  (sun / PVGIS / FSM / log)\n', dt_outer);
fprintf('dt_inner      : %.2f s  (PID + servo — %d sub-steps per outer step)\n\n', dt_inner, N_sub);

%% ════════════════════════════════════════════════════════════════════════
%% CONFIGURATION
%% ════════════════════════════════════════════════════════════════════════

%% 12-Day Duffie & Beckman Monthly Representative Days (Recommended by ASHRAE/NREL)
%  One representative day per month; each day accounts for all days in that month.
%  Representative day = midday of nth-day weighted average (Spencer, 1971)
representative_days = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];
month_lengths       = [31, 28, 31,  30,  31,  30,  31,  31,  30,  31,  30,  31];
season_names        = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'};
nDays = length(representative_days);

% Panel specs — Micro-Tracker: 4 petals × (100 mm × 100 mm) = 0.04 m² total
PANEL_AREA = 0.04;   % [m²] — 4 petals × 0.01 m² each (100 mm × 100 mm per petal)
ETA_PANEL  = 0.20;   % PV cell efficiency at STC [25°C, 1000 W/m²]
TILT_DEG   = Geo.Lat; % Fixed panel tilt = local latitude (maximises annual yield)
b0         = 0.05;   % ASHRAE IAM coefficient (93-2010 clear-sky model)

% Thermal derating constants — Evans (1981) model
NOCT    = 45.0;   % Nominal Operating Cell Temperature [°C]
GAMMA_T = 0.004;  % Temperature power coefficient [1/°C]: 0.4 %/°C above 25°C STC

% Fixed panel normal — south-facing, tilted at latitude (ENU: south = −Y)
N_fixed = [0; -sind(TILT_DEG); cosd(TILT_DEG)];
N_fixed = N_fixed / norm(N_fixed);

% FSM thresholds — calibrated for realistic winter irradiance (G_peak 224 W/m²)
SupervisorParams = struct();
SupervisorParams.night_threshold     = 0.10;
SupervisorParams.sun_lost_threshold  = 0.15;
SupervisorParams.sun_found_threshold = 0.30;
SupervisorParams.lock_threshold      = 0.50;
SupervisorParams.tracking_deadband   = 3.0;    % [°] 0.14% optical loss, massive energy savings
SupervisorParams.batch_interval      = 60.0;   % [s] 1-min batch interval — optimize net yield
SupervisorParams.max_burst_time      = 2.0;    % [s] strict hardware interrupt for energy optimization
SupervisorParams.search_speed        = 3.0;
SupervisorParams.zenith_pan_lock     = false;
SupervisorParams.tau_derivative      = 2.0;    % EMA time constant [s] — dt-invariant

% Parasitic model
I_SPIN_BASE = 0.17;   % no-load spinning current per axis [A]
V_SUPPLY    = 6.0;    % servo supply voltage [V]

%% ════════════════════════════════════════════════════════════════════════
%% LOAD PVGIS & SCENARIO
%% ════════════════════════════════════════════════════════════════════════

% Build a minimal Scenario struct from Geo config (for getSunVector compatibility)
Scenario              = struct();
Scenario.lat          = Geo.Lat;
Scenario.lon          = Geo.Lon;
Scenario.tz           = Geo.TZ;
Scenario.pvgis_file   = Geo.PVGIS_File;
Scenario.t_start_hour = 5;       % 5 AM — captures dawn at all latitudes/seasons
Scenario.duration_sec = 15*3600; % 15-hour window (5 AM → 8 PM)

PVData_full = loadPVGIS(Geo.PVGIS_File);

fprintf('PVGIS File : %s\n', Geo.PVGIS_File);
fprintf('Location   : %s\n', Geo.Name);
fprintf('Coords     : %.2f°N  %.2f°E  UTC%+d\n\n', Geo.Lat, Geo.Lon, Geo.TZ);

% Query servo props once (MaxSpeed used in parasitic model)
tmpState = struct('Angle',0,'Velocity',0,'Current',0,'Energy',0);
[~, ~, ServoProps] = stepTheoreticalServo(tmpState, 0, dt_inner, 'Pan');

%% ════════════════════════════════════════════════════════════════════════
%% RESULT STORAGE
%% ════════════════════════════════════════════════════════════════════════

% nDays defined above in CONFIGURATION
Results = struct();   % Initialize struct array (nesting: Results(d).field)
AllData = cell(nDays, 1);   % Detailed data per month

%% ════════════════════════════════════════════════════════════════════════
%% MAIN LOOP — THREE REFERENCE DAYS
%% ════════════════════════════════════════════════════════════════════════

for d = 1:nDays

    %% ── Orbital mechanics: compute properties for this representative Julian day
    n         = representative_days(d);
    % Solar declination angle (Spencer 1971 approximation — ±0.035° accuracy)
    delta_deg = 23.45 * sin(deg2rad((360/365) * (284 + n)));

    % Map Julian day → calendar date within the PVGIS data year for file lookup
    pvgis_year = year(PVData_full.time(1));
    ref_date   = datetime(pvgis_year, 1, 1) + days(n - 1);

    % Seasonal ambient temperature — Klein (1977) sinusoidal latitude model
    %   T_amb(n) = T_mean + DeltaT * cos(2*pi*(n - n_hottest) / 365)
    %   n_hottest = 205 (late July — hottest day in Northern Hemisphere)
    %   At n=205: cos(0)=+1 → T_mean+DeltaT = summer maximum. Correct.
    %   Coefficients calibrated for mid-latitude sites; conservative for arctic/desert
    T_mean_loc  = max(5.0, 32.0 - 0.45 * Geo.Lat);   % Annual mean temp [°C]
    Delta_T_loc = max(5.0, 13.0 - 0.10 * Geo.Lat);   % Seasonal amplitude [°C]
    T_ambient   = T_mean_loc + Delta_T_loc * cos(2*pi*(n - 205)/365);  % [°C] scalar

    fprintf('══════════════════════════════════════════════════════════\n');
    fprintf('  Month %2d/12 : %s\n', d, season_names{d});
    fprintf('  Julian n=%-3d | delta=%+.2f deg | T_amb=%.1f degC | %s | %s\n', ...
        n, delta_deg, T_ambient, upper(CONTROL_MODE), Geo.Name);
    fprintf('══════════════════════════════════════════════════════════\n');

    [PVData, DayStats] = filterPVGISbyDate(PVData_full, 'DAILY', ref_date);
    fprintf('  Date: %s  G_peak=%.1f W/m²  Day=%.1f h  H=%.1f Wh/m²\n\n', ...
        string(DayStats.date,'dd-MMM-yyyy'), DayStats.peak_irradiance, ...
        DayStats.daylight_hours, DayStats.daily_insolation);

    % Outer time vector (1 s grid — used for logging and trapz)
    t_start_s = Scenario.t_start_hour * 3600;
    t_end_s   = t_start_s + Scenario.duration_sec;
    time_vec  = (t_start_s : dt_outer : t_end_s)';
    N         = length(time_vec);
    SimDate   = DayStats.date + hours(Scenario.t_start_hour);

    % Log arrays (1 s resolution)
    G_pvgis         = zeros(N,1);
    P_fixed         = zeros(N,1);
    P_tracker_gross = zeros(N,1);
    P_parasitic     = zeros(N,1);
    P_tracker_net   = zeros(N,1);
    FSM_log         = cell(N,1);
    for k=1:N, FSM_log{k}='IDLE'; end
    T_cell_tracker  = zeros(N,1);   % PV cell temperature — tracker panel [°C]
    T_cell_fixed    = zeros(N,1);   % PV cell temperature — fixed panel [°C]
    f_derate_log    = ones(N,1);    % Per-step thermal derating factor [—]
    IAM_tracker_log = zeros(N,1);   % Incident Angle Modifier — tracker panel [—]

    %% ── Initialise tracker at actual sun position at t_start ───────────
    current_time_init = SimDate;
    [S_init, el_init, az_init] = getSunVector( ...
        Scenario.lat, Scenario.lon, current_time_init, Scenario.tz);

    if el_init > 0
        init_pan  = az_init; if init_pan > 180, init_pan = init_pan - 360; end
        init_tilt = max(-90, min(90, 90 - el_init));
        [adj_pan0, adj_tilt0, ~, ~] = applyFlipLogic(init_pan, init_tilt);
        StatePan  = struct('Angle',adj_pan0,  'Velocity',0,'Current',0,'Energy',0);
        StateTilt = struct('Angle',adj_tilt0, 'Velocity',0,'Current',0,'Energy',0);
    else
        StatePan  = struct('Angle',0,  'Velocity',0,'Current',0,'Energy',0);
        StateTilt = struct('Angle',80, 'Velocity',0,'Current',0,'Energy',0);
    end
    fprintf('  Init: Pan=%.1f°  Tilt=%.1f°  (Sun el=%.1f°  az=%.1f°)\n', ...
        StatePan.Angle, StateTilt.Angle, el_init, az_init);

    %% ── State variables ────────────────────────────────────────────────
    FSM_State = struct('mode','TRACKING', ...
        'e_pan_prev',0,'e_tilt_prev',0, ...
        'de_pan_filtered',0,'de_tilt_filtered',0, ...
        'search_phase',0,'hold_timer',0,'burst_timer',0, ...
        'was_night',false,'park_target_pan',0,'park_target_tilt',90);

    ControlState = struct('I_pan',0,'I_tilt',0,'de_pan_filt',0,'de_tilt_filt',0);

    CommandSmoothing = struct( ...
        'target_pan_smoothed',  StatePan.Angle, ...
        'target_tilt_smoothed', StateTilt.Angle);

    tic;
    for i = 1:N   %% ══ OUTER LOOP (1 Hz) ═══════════════════════════════

        sim_t        = time_vec(i);
        current_time = SimDate + seconds(sim_t - t_start_s);

        %% ── Slow quantities (updated every 1 s) ───────────────────────

        % PVGIS irradiance — shift sim_t by timezone (PVGIS is UTC, simulation is local)
        [G_now, ~] = getPVGISatTime(sim_t - Scenario.tz * 3600, PVData);
        G_pvgis(i) = G_now;

        % Sun vector — moves 0.004°/s, perfectly valid for 100 sub-steps
        [S_vec, elevation, azimuth] = getSunVector( ...
            Scenario.lat, Scenario.lon, current_time, Scenario.tz);

        if elevation <= 0 || G_now < 1
            FSM_log{i} = 'IDLE';
            continue;
        end

        % Fixed panel power (depends only on sun vector — computed once per second)
        cos_f = max(0, dot(S_vec, N_fixed));
        % IAM formula with bounds checking — prevent numerical instability at grazing angles
        % When cos_f is very small, 1/cos_f becomes large, causing numerical issues
        if cos_f > 0.01
            IAM_f = max(0, 1 - b0*(1/cos_f - 1));
        else
            IAM_f = 0;  % Grazing incidence — treat as zero transmission
        end
        P_fixed(i) = G_now * PANEL_AREA * ETA_PANEL * cos_f * IAM_f;

        % Ideal tracker angles + flip logic (slow — only depends on sun)
        [az_deg, el_deg] = cartesian2spherical(S_vec);
        ideal_pan  = az_deg; if ideal_pan > 180, ideal_pan = ideal_pan - 360; end
        ideal_tilt = max(-90, min(90, 90 - el_deg));
        [adj_pan, adj_tilt, is_flip, is_reachable] = applyFlipLogic(ideal_pan, ideal_tilt);

        % LDR voltages — read once per second with angles from END of previous inner loop
        % This is a 1-step (1 second) lag inherent to the 1 Hz FSM supervisor design
        theta_p_prev = StatePan.Angle;  % angles from end of PREVIOUS inner loop
        theta_t_prev = StateTilt.Angle;
        cp=cosd(theta_p_prev); sp=sind(theta_p_prev); ct=cosd(theta_t_prev); st=sind(theta_t_prev);
        Sx = cp*S_vec(1)-sp*S_vec(2); Sy = sp*S_vec(1)+cp*S_vec(2);
        S_body_1hz   = [Sx; ct*Sy-st*S_vec(3); st*Sy+ct*S_vec(3)];
        S_body_1hz_n = S_body_1hz / (norm(S_body_1hz)+1e-8);
        [~, LDR_V, ~, ~, ~, ~] = readLDRs(S_body_1hz_n);

        % FSM — supervisor runs at 1 Hz (slow decision-maker by design)
        [ErrorSignal, FSM_State, ~, ~] = StateManagerFSM( ...
            LDR_V, S_body_1hz, theta_p_prev, theta_t_prev, ...
            FSM_State, SupervisorParams, dt_outer, is_flip);

        %% ── THERMODYNAMIC CUTOFF — Force IDLE when solar gain < motor cost ──
        %  If G_total < 250 W/m², energy delivered is less than parasitic drain
        %  → Force FSM to IDLE to prevent "Winter Energy Bleed" (negative gains)
        if G_now < 250
            FSM_State.mode = 'IDLE';  % Override FSM decision; motors fully de-energise
        end

        fsm_active = ismember(FSM_State.mode, {'TRACKING','SEARCH','PARK'});

        %% ── INNER LOOP: PID + Servo at dt=0.01 s (100 sub-steps) ─────
        %  S_vec, adj_pan, adj_tilt, is_flip, is_reachable, ErrorSignal
        %  are all held constant — they change negligibly over 1 second.

        % Initialize current accumulators for parasitic power averaging
        I_pan_accum  = 0;
        I_tilt_accum = 0;

        for s = 1:N_sub   %% ══ INNER LOOP (100 Hz) ════════════════════

            % ── BLOCK B: Controller (dt_inner = 0.01 s) ─────────────────
            if strcmp(CONTROL_MODE, 'fuzzy')
                [VelCmd, ControlState, ~, ~] = FuzzyLogicController( ...
                    ErrorSignal, ControlState, dt_inner);
            else
                [VelCmd, ControlState, ~, ~] = PID_VelocityController( ...
                    ErrorSignal, ControlState, struct(), dt_inner);
            end

            % Velocity → position
            theta_pan_curr  = StatePan.Angle;
            theta_tilt_curr = StateTilt.Angle;
            tgt_pan  = max(-180, min(180, theta_pan_curr  + VelCmd.v_pan  * dt_inner));
            tgt_tilt = max(-90,  min(90,  theta_tilt_curr + VelCmd.v_tilt * dt_inner));

            % Geometric sun-aim blend (flip-safe)
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
                % HOLD / IDLE — freeze smoothed target so motors de-energise
                CommandSmoothing.target_pan_smoothed  = theta_pan_curr;
                CommandSmoothing.target_tilt_smoothed = theta_tilt_curr;
            end

            % ── BLOCK C: Servo plant at dt_inner = 0.01 s ───────────────
            [StatePan,  ~, ~] = stepTheoreticalServo( ...
                StatePan,  CommandSmoothing.target_pan_smoothed,  dt_inner, 'Pan');
            [StateTilt, ~, ~] = stepTheoreticalServo( ...
                StateTilt, CommandSmoothing.target_tilt_smoothed, dt_inner, 'Tilt');

            % Accumulate current for parasitic power averaging
            I_pan_accum  = I_pan_accum  + StatePan.Current;
            I_tilt_accum = I_tilt_accum + StateTilt.Current;

        end   %% ══ END INNER LOOP ══════════════════════════════════════

        %% ── Logging (1 Hz, after sub-steps) ───────────────────────────

        % Refresh body frame with final servo angles
        theta_pan_f  = StatePan.Angle;  theta_tilt_f = StateTilt.Angle;
        cp2=cosd(theta_pan_f); sp2=sind(theta_pan_f);
        ct2=cosd(theta_tilt_f); st2=sind(theta_tilt_f);
        Sx2=cp2*S_vec(1)-sp2*S_vec(2); Sy2=sp2*S_vec(1)+cp2*S_vec(2);
        Sb = [Sx2; ct2*Sy2-st2*S_vec(3); st2*Sy2+ct2*S_vec(3)];
        Sbn = Sb / (norm(Sb)+1e-8);

        % Tracker gross power — cos(incidence) = body-z component
        cos_t = max(0, Sbn(3));
        % IAM formula with bounds checking — prevent numerical instability at grazing angles
        if cos_t > 0.01
            IAM_t = max(0, 1 - b0*(1/cos_t - 1));
        else
            IAM_t = 0;  % Grazing incidence — treat as zero transmission
        end
        IAM_tracker_log(i) = IAM_t;   % Log IAM for thermal penalty visualization
        P_tracker_gross(i) = G_now * PANEL_AREA * ETA_PANEL * cos_t * IAM_t;

        %% ── Thermal Derating Model — Evans (1981) / Ross (1976) ─────────────────
        % Cell temperature: T_cell = T_amb + (NOCT-20)/800 * G_POA * IAM
        % T_ambient is the representative scalar for Julius day n [°C]
        T_cell_tracker(i) = T_ambient + ((NOCT - 20) / 800) * G_now * IAM_t;
        T_cell_fixed(i)   = T_ambient + ((NOCT - 20) / 800) * G_now * IAM_f;

        % Derating factor: f = 1 - gamma_T * max(0, T_cell - 25)  [Evans, 1981]
        f_derate_tracker  = 1 - GAMMA_T * max(0, T_cell_tracker(i) - 25);
        f_derate_fixed    = 1 - GAMMA_T * max(0, T_cell_fixed(i)   - 25);
        f_derate_log(i)   = f_derate_tracker;

        % Apply thermal derating to gross powers (before parasitic subtraction)
        P_tracker_gross(i) = P_tracker_gross(i) * f_derate_tracker;
        P_fixed(i)         = P_fixed(i)         * f_derate_fixed;
        % (HOLD/IDLE → motors fully de-energised via current estimation in servo)
        is_hold = ismember(FSM_State.mode, {'HOLD','IDLE'});
        if is_hold
            I_motor = 0;
        else
            % Average the accumulated current over the N_sub inner steps
            I_pan_avg  = I_pan_accum  / N_sub;
            I_tilt_avg = I_tilt_accum / N_sub;
            I_motor = I_pan_avg + I_tilt_avg;  % Total current, both axes [A]
        end
        P_parasitic(i)   = I_motor * V_SUPPLY;        % [W], two axes
        P_tracker_net(i) = P_tracker_gross(i) - P_parasitic(i);  % Can be negative (energy debt)
        FSM_log{i}       = FSM_State.mode;

    end   %% ══ END OUTER LOOP ═══════════════════════════════════════════
    elapsed = toc;
    fprintf('  Done in %.1f s\n', elapsed);

    % FSM time breakdown
    n_track = sum(strcmp(FSM_log,'TRACKING'));
    n_hold  = sum(strcmp(FSM_log,'HOLD'));
    n_srch  = sum(strcmp(FSM_log,'SEARCH'));
    n_idle  = sum(strcmp(FSM_log,'IDLE'));
    fprintf('  FSM: TRACKING=%ds | HOLD=%ds | SEARCH=%ds | IDLE=%ds\n', ...
        n_track, n_hold, n_srch, n_idle);

    % Day energy via trapz on 1 s grid
    E_fixed  = trapz(time_vec, P_fixed)         / 3600;
    E_gross  = trapz(time_vec, P_tracker_gross) / 3600;
    E_para   = trapz(time_vec, P_parasitic)     / 3600;
    P_delivered = max(0, P_tracker_net);        % Only positive power reaches the load
    E_net    = trapz(time_vec, P_delivered)     / 3600;  % Deliverable energy [Wh]
    E_net_raw = trapz(time_vec, P_tracker_net)  / 3600;  % Thermodynamic net (can be negative) [Wh]
    Para_r   = 100 * E_para  / (E_gross + 1e-9);
    Net_gain = 100 * (E_net  - E_fixed) / (E_fixed + 1e-9);

    fprintf('  E_fixed=%.2fWh | E_gross=%.2fWh | E_para=%.3fWh | E_net=%.2fWh\n', ...
        E_fixed, E_gross, E_para, E_net);
    fprintf('  Parasitic=%.2f%%  |  Net Gain=%+.2f%%\n\n', Para_r, Net_gain);

    Results(d).label    = season_names{d};
    Results(d).month_length = month_lengths(d);   % Days in this month
    Results(d).DayStats = DayStats;
    Results(d).E_fixed    = E_fixed;
    Results(d).E_gross    = E_gross;
    Results(d).E_para     = E_para;
    Results(d).E_net      = E_net;
    Results(d).Para_r     = Para_r;
    Results(d).Net_gain   = Net_gain;
    Results(d).T_ambient  = T_ambient;   % Klein (1977) seasonal ambient [°C]
    Results(d).delta_deg  = delta_deg;   % Solar declination [°]
    Results(d).julian_day = representative_days(d); % Representative day for month d

    AllData{d}.time_vec        = time_vec;
    AllData{d}.t_start_s       = t_start_s;
    AllData{d}.P_fixed         = P_fixed;
    AllData{d}.P_tracker_gross = P_tracker_gross;
    AllData{d}.P_tracker_net   = P_tracker_net;   % Thermodynamic net (can be negative)
    AllData{d}.P_delivered     = P_delivered;     % Deliverable to load (always ≥ 0)
    AllData{d}.P_parasitic     = P_parasitic;
    AllData{d}.G_pvgis         = G_pvgis;
    AllData{d}.FSM_log         = FSM_log;
    AllData{d}.T_cell_tracker  = T_cell_tracker;  % Cell temp — tracker [°C]
    AllData{d}.T_cell_fixed    = T_cell_fixed;    % Cell temp — fixed [°C]
    AllData{d}.f_derate_log    = f_derate_log;    % Thermal derating factor [—]
    AllData{d}.IAM_tracker_log = IAM_tracker_log; % Incident Angle Modifier — tracker [—]
    AllData{d}.T_ambient       = T_ambient;       % Seasonal ambient scalar [°C]
    AllData{d}.delta_deg       = delta_deg;       % Solar declination [°]
    AllData{d}.julian_day      = representative_days(d);  % Representative day for month d
    AllData{d}.month_days      = month_lengths(d);         % Days in this month
    AllData{d}.E_fixed_cum     = cumtrapz(time_vec, P_fixed)         / 3600;
    AllData{d}.E_delivered_cum = cumtrapz(time_vec, P_delivered)     / 3600;  % Use delivered (≥0)
    AllData{d}.E_gross_cum     = cumtrapz(time_vec, P_tracker_gross) / 3600;

end  % day loop

%% ════════════════════════════════════════════════════════════════════════
%% ANNUAL EXTRAPOLATION — Using Duffie & Beckman method with actual month lengths
%% ═════════════════════════════════════════════

E_fixed_yr = 0; E_gross_yr = 0; E_para_yr = 0; E_net_yr = 0;
for d = 1:nDays
    % Weight = number of days in month (28, 30, or 31)
    w = month_lengths(d);
    E_fixed_yr = E_fixed_yr + Results(d).E_fixed * w;
    E_gross_yr = E_gross_yr + Results(d).E_gross * w;
    E_para_yr  = E_para_yr  + Results(d).E_para  * w;
    E_net_yr   = E_net_yr   + Results(d).E_net   * w;
end
Para_yr = 100 * E_para_yr / (E_gross_yr + 1e-9);
Gain_yr = 100 * (E_net_yr  - E_fixed_yr) / (E_fixed_yr + 1e-9);

fprintf('\n\n');
fprintf('════════════════════════════════════════════════════════════════\n');
fprintf('  ANNUAL YIELD SUMMARY — %s', Geo.Name);
fprintf('  Micro-Tracker: %.4f m² (4 petals)  | Controller: %s | Physics: %s\n', ...
    PANEL_AREA, upper(CONTROL_MODE), PHYSICS_MODEL);
fprintf('════════════════════════════════════════════════════════════════\n');
fprintf('  E_fixed   = %8.1f Wh/yr  = %6.2f kWh/yr\n', E_fixed_yr,  E_fixed_yr/1000);
fprintf('  E_gross   = %8.1f Wh/yr  = %6.2f kWh/yr\n', E_gross_yr,  E_gross_yr/1000);
fprintf('  E_para    = %8.1f Wh/yr  = %6.3f kWh/yr\n', E_para_yr,   E_para_yr/1000);
fprintf('  E_net     = %8.1f Wh/yr  = %6.2f kWh/yr\n', E_net_yr,    E_net_yr/1000);
fprintf('  Parasitic Ratio    : %.2f %%\n', Para_yr);
fprintf('  Net Efficiency Gain: %+.2f %%\n', Gain_yr);
fprintf('════════════════════════════════════════════════════════════════\n\n');

% Academic output for scatter plotting
fprintf('LAT: %.2f | GAIN: %+.2f%%\n\n', Geo.Lat, Gain_yr);

%% ════════════════════════════════════════════════════════════════════════
%% GLOBAL FIGURE DEFAULTS — LaTeX Interpreter + White Background
%% ════════════════════════════════════════════════════════════════════════

set(groot, 'defaultTextInterpreter',              'latex');
set(groot, 'defaultAxesTickLabelInterpreter',     'latex');
set(groot, 'defaultLegendInterpreter',            'latex');
set(groot, 'defaultColorbarTickLabelInterpreter', 'latex');

% ── Publication Colour Palette ───────────────────────────────────────────
C_GOLD    = [0.93, 0.69, 0.13];   % Warm Gold   — Tracker Net
C_NAVY    = [0.12, 0.30, 0.47];   % Deep Navy   — Fixed Panel
C_LTGREY  = [0.50, 0.50, 0.50];   % Steel Grey  — Irradiance dotted line
C_CRIMSON = [0.75, 0.15, 0.15];   % Crimson     — Motor / Parasitic
C_IDLE_BG = [0.93, 0.93, 0.93];   % Very Light Grey — IDLE sleep shading
C_BKGREY  = [0.78, 0.78, 0.78];   % Bar Grey    — Gross energy bar

% Three key reference-day indices (Summer | Spring Equinox | Winter)
ref3     = [6, 3, 12];
ref3_lbl = {'June (Summer Solstice)', 'March (Vernal Equinox)', 'December (Winter Solstice)'};

%% ════════════════════════════════════════════════════════════════════════
%% FIGURE 1 — Micro-Dynamics & Motor Heartbeat  (3-Day Time Series)
%% Layout: tiledlayout(2, 3)  →  Top row: Power generation
%%                             →  Bottom row: Motor heartbeat / parasitics
%% ════════════════════════════════════════════════════════════════════════

fig1 = figure('Name','Micro-Dynamics & Motor Heartbeat', ...
    'Color','w', 'Position',[40 40 1560 720], 'NumberTitle','off');
tl1  = tiledlayout(fig1, 2, 3, 'TileSpacing','compact', 'Padding','compact');
title(tl1, ['\textbf{Micro-Dynamics \& Motor Heartbeat} --- ' ...
    Geo.Name ' $|$ ' upper(CONTROL_MODE) ' Controller $|$ PVGIS 2023'], ...
    'FontSize', 13);

for ci = 1:3
    d  = ref3(ci);
    D  = AllData{d};
    th = (D.time_vec - D.t_start_s) / 3600;   % hours from dawn  [0 … 15]
    idle_mask = strcmp(D.FSM_log, 'IDLE');

    %% ── TOP ROW: Power Generation with dual Y-axis ───────────────────
    ax_t = nexttile(ci);
    hold(ax_t, 'on');

    yyaxis(ax_t, 'left');
    % Tracker Net (Warm Gold) — base layer
    h_net = area(ax_t, th, max(0, D.P_tracker_net), ...
        'FaceColor', C_GOLD, 'FaceAlpha', 0.65, ...
        'EdgeColor', C_GOLD .* 0.75, 'LineWidth', 0.6);
    % Fixed Panel (Deep Navy) — overlaid with transparency
    h_fix = area(ax_t, th, D.P_fixed, ...
        'FaceColor', C_NAVY, 'FaceAlpha', 0.55, ...
        'EdgeColor', C_NAVY, 'LineWidth', 0.6);
    p_top = max([max(D.P_tracker_net), max(D.P_fixed)]);
    ylim(ax_t, [0, p_top * 1.22 + 1e-4]);
    ylabel(ax_t, 'Power (W)', 'FontSize', 10);
    ax_t.YAxis(1).Color = 'k';

    yyaxis(ax_t, 'right');
    % Raw PVGIS irradiance — dotted steel-grey reference line
    h_irr = plot(ax_t, th, D.G_pvgis, '--', ...
        'Color', C_LTGREY, 'LineWidth', 1.2);
    ylabel(ax_t, 'Irradiance (W\,m$^{-2}$)', 'FontSize', 10);
    ax_t.YAxis(2).Color = C_LTGREY;

    title(ax_t, ['\textbf{' ref3_lbl{ci} '}'], 'FontSize', 11);
    xlabel(ax_t, 'Hour of Day (h)', 'FontSize', 10);
    set(ax_t, 'Box','on', 'LineWidth',1.2, 'XGrid','on', 'YGrid','on', 'Color','w');
    subtitle(ax_t, ...
        sprintf('Net $=$ %.2f\\,Wh $\\quad$ Fixed $=$ %.2f\\,Wh $\\quad$ Gain $=$ $%+.1f$\\%%', ...
        Results(d).E_net, Results(d).E_fixed, Results(d).Net_gain), ...
        'FontSize', 9);
    if ci == 1
        legend(ax_t, [h_net, h_fix, h_irr], ...
            {'Tracker Net', 'Fixed Panel', 'Irradiance $G$'}, ...
            'Location','northwest', 'FontSize', 9, 'NumColumns', 1);
    end

    %% ── BOTTOM ROW: Motor Heartbeat / Parasitic Power ────────────────
    ax_b = nexttile(3 + ci);
    hold(ax_b, 'on');

    % Crimson "heartbeat" area — discrete batch-interval spikes
    area(ax_b, th, D.P_parasitic, ...
        'FaceColor', C_CRIMSON, 'FaceAlpha', 0.85, 'EdgeColor', 'none');

    % Grey IDLE sleep shading pushed behind the area
    p_ymax = max(D.P_parasitic) * 1.30 + 1e-4;
    ylim(ax_b, [0, p_ymax]);
    shadeIdleRegions(ax_b, th, idle_mask, C_IDLE_BG, p_ymax);

    xlabel(ax_b, 'Hour of Day (h)', 'FontSize', 10);
    ylabel(ax_b, 'Motor Power (W)', 'FontSize', 10);
    set(ax_b, 'Box','on', 'LineWidth',1.2, 'XGrid','on', 'YGrid','on', 'Color','w');
    subtitle(ax_b, ...
        sprintf('$E_{\\rm para} = %.3f$\\,Wh $\\quad$ Parasitic Ratio $= %.2f$\\%%', ...
        Results(d).E_para, Results(d).Para_r), 'FontSize', 9);

    % Bottom-row legend (proxy patches)
    h_pa = patch(ax_b, NaN, NaN, C_CRIMSON, 'EdgeColor','none', 'FaceAlpha',0.85);
    h_sl = patch(ax_b, NaN, NaN, C_IDLE_BG, 'EdgeColor','none', 'FaceAlpha',0.8);
    legend(ax_b, [h_pa, h_sl], {'Motor Active', 'FSM: IDLE (Sleep)'}, ...
        'Location','northwest', 'FontSize', 9);
end
clear ci d D th idle_mask ax_t ax_b h_net h_fix h_irr h_pa h_sl p_top p_ymax

%% ════════════════════════════════════════════════════════════════════════
%% FIGURE 2 — Techno-Economic Waterfall & Summary  (1×2 layout)
%% LEFT:  Grouped monthly energy bar (Fixed | Gross | Net) — 12 months
%% RIGHT: Net Efficiency Gain (green/red bars) + Parasitic Ratio (line)
%% ════════════════════════════════════════════════════════════════════════

Mo_labels = {Results.label};           % 12 month abbreviations
Mo_Efixed = [Results.E_fixed];         % Daily energy arrays [Wh]
Mo_Egross = [Results.E_gross];
Mo_Enet   = [Results.E_net];
Mo_gain   = [Results.Net_gain];        % Net efficiency gain [%]
Mo_para   = [Results.Para_r];          % Parasitic ratio [%]

fig2 = figure('Name','Techno-Economic Waterfall & Summary', ...
    'Color','w', 'Position',[80 60 1440 600], 'NumberTitle','off');
tl2  = tiledlayout(fig2, 1, 2, 'TileSpacing','loose', 'Padding','compact');
title(tl2, ['\textbf{Techno-Economic Waterfall \& Summary} --- ' ...
    Geo.Name ' $|$ ' upper(CONTROL_MODE) ' Controller'], 'FontSize', 13);

%% ── LEFT TILE: Grouped Energy Budget (Fixed | Gross | Net) ──────────
ax_L = nexttile(1);
hold(ax_L, 'on');

Emat = [Mo_Efixed; Mo_Egross; Mo_Enet]';        % nDays × 3
bh   = bar(ax_L, 1:nDays, Emat, 'grouped');
bh(1).FaceColor = C_NAVY;    bh(1).EdgeColor = 'none';
bh(2).FaceColor = C_BKGREY;  bh(2).EdgeColor = 'none';
bh(3).FaceColor = C_GOLD;    bh(3).EdgeColor = 'none';

% Rotated value labels on Fixed and Net bars (Gross omitted to reduce clutter)
yrng_L = max(Mo_Egross) * 0.016;
for mi = 1:nDays
    text(ax_L, bh(1).XEndPoints(mi), bh(1).YEndPoints(mi) + yrng_L, ...
        sprintf('%.1f', Mo_Efixed(mi)), ...
        'HorizontalAlignment','center', 'FontSize',6, 'Rotation',90, ...
        'Color', C_NAVY);
    text(ax_L, bh(3).XEndPoints(mi), bh(3).YEndPoints(mi) + yrng_L, ...
        sprintf('%.1f', Mo_Enet(mi)), ...
        'HorizontalAlignment','center', 'FontSize',6, 'Rotation',90, ...
        'Color', C_GOLD .* 0.75);
end

set(ax_L, 'XTick',1:nDays, 'XTickLabel',Mo_labels, ...
    'Box','on', 'LineWidth',1.2, 'YGrid','on', 'XGrid','off', 'Color','w');
ylabel(ax_L, 'Daily Energy (Wh)', 'FontSize', 11);
xlabel(ax_L, 'Month', 'FontSize', 11);
title(ax_L, '\textbf{Monthly Energy Budget: Fixed vs.\ Gross vs.\ Net}', 'FontSize', 11);
legend(ax_L, bh, {'Fixed', 'Gross (pre-parasitic)', 'Net (delivered)'}, ...
    'Location','northeast', 'FontSize', 9);

%% ── RIGHT TILE: Net Gain (green/red bars) + Parasitic Ratio (line) ──
ax_R = nexttile(2);
hold(ax_R, 'on');

C_GREEN = [0.18, 0.63, 0.23];
C_RED   = [0.80, 0.15, 0.10];

yyaxis(ax_R, 'left');
pos_idx = find(Mo_gain >= 0);
neg_idx = find(Mo_gain < 0);
if ~isempty(pos_idx)
    bar(ax_R, pos_idx, Mo_gain(pos_idx), 0.65, ...
        'FaceColor', C_GREEN, 'EdgeColor','none', 'FaceAlpha',0.85);
end
if ~isempty(neg_idx)
    bar(ax_R, neg_idx, Mo_gain(neg_idx), 0.65, ...
        'FaceColor', C_RED,   'EdgeColor','none', 'FaceAlpha',0.85);
end
yline(ax_R, 0, '-k', 'LineWidth', 1.0, 'HandleVisibility','off');
ylabel(ax_R, 'Net Efficiency Gain (\%)', 'FontSize', 11);
ax_R.YAxis(1).Color = 'k';

yyaxis(ax_R, 'right');
plot(ax_R, 1:nDays, Mo_para, '-ko', ...
    'LineWidth', 2.0, 'MarkerSize', 6, 'MarkerFaceColor','k');
ylabel(ax_R, 'Parasitic Ratio (\%)', 'FontSize', 11);
ax_R.YAxis(2).Color = 'k';

set(ax_R, 'XTick',1:nDays, 'XTickLabel',Mo_labels, ...
    'Box','on', 'LineWidth',1.2, 'YGrid','on', 'XGrid','off', 'Color','w');
xlabel(ax_R, 'Month', 'FontSize', 11);
title(ax_R, '\textbf{Efficiency Gain vs.\ Motor Parasitic Cost}', 'FontSize', 11);

h_gn  = patch(ax_R, NaN, NaN, C_GREEN, 'EdgeColor','none', 'FaceAlpha',0.85);
h_rd  = patch(ax_R, NaN, NaN, C_RED,   'EdgeColor','none', 'FaceAlpha',0.85);
h_ln  = plot(ax_R,  NaN, NaN, '-ko', 'LineWidth',2.0, 'MarkerFaceColor','k');
legend(ax_R, [h_gn, h_rd, h_ln], ...
    {'Gain $> 0$', 'Gain $< 0$', 'Parasitic Ratio'}, ...
    'Location','best', 'FontSize', 9);

clear Mo_labels Mo_Efixed Mo_Egross Mo_Enet Mo_gain Mo_para ...
      Emat bh ax_L ax_R pos_idx neg_idx yrng_L h_gn h_rd h_ln

%% ════════════════════════════════════════════════════════════════════════
%% FIGURE 3 — FSM State Distribution  (100% Stacked Bar, 12 Months)
%% Each bar = one month; segments = % time in TRACKING / HOLD / SEARCH / IDLE
%% ════════════════════════════════════════════════════════════════════════

fsm_state_names = {'TRACKING','HOLD','SEARCH','IDLE'};
fsm_cols = [0.22, 0.56, 0.24;   % TRACKING — Forest Green
            0.13, 0.47, 0.71;   % HOLD     — Steel Blue
            0.95, 0.73, 0.00;   % SEARCH   — Amber
            0.80, 0.80, 0.80];  % IDLE     — Light Grey

% Build 12 × 4 percentage matrix
pct_fsm = zeros(nDays, 4);
for d = 1:nDays
    n_total = length(AllData{d}.FSM_log);
    for k = 1:4
        pct_fsm(d, k) = 100 * sum(strcmp(AllData{d}.FSM_log, fsm_state_names{k})) / n_total;
    end
end

fig3 = figure('Name','FSM State Distribution (100% Stacked)', ...
    'Color','w', 'Position',[120 100 1200 500], 'NumberTitle','off');
ax3  = axes(fig3, 'Color','w');
hold(ax3, 'on');

bh3 = bar(ax3, 1:nDays, pct_fsm, 1.0, 'stacked');
for k = 1:4
    bh3(k).FaceColor = fsm_cols(k,:);
    bh3(k).EdgeColor = 'w';
    bh3(k).LineWidth = 0.6;
    bh3(k).DisplayName = fsm_state_names{k};
end

% Percentage labels centred inside each segment
cumPct = zeros(1, nDays);
for k = 1:4
    for d = 1:nDays
        mid_y = cumPct(d) + pct_fsm(d, k) / 2;
        if pct_fsm(d, k) > 5   % label only segments wide enough to read
            txt_col = 'w';
            if k == 4, txt_col = [0.25 0.25 0.25]; end  % grey on grey → dark text
            text(ax3, d, mid_y, sprintf('%.0f\\%%', pct_fsm(d, k)), ...
                'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
                'FontSize', 7.5, 'FontWeight','bold', 'Color', txt_col);
        end
    end
    cumPct = cumPct + pct_fsm(:, k)';
end

ylim(ax3, [0, 100]);
set(ax3, 'XTick',1:nDays, 'XTickLabel',{Results.label}, ...
    'Box','on', 'LineWidth',1.2, 'YGrid','off', 'XGrid','off');
ylabel(ax3, 'Time Distribution (\%)', 'FontSize', 11);
xlabel(ax3, 'Month', 'FontSize', 11);
title(ax3, ['\textbf{FSM State Distribution} --- ' ...
    Geo.Name ' $|$ ' upper(CONTROL_MODE) ' Controller'], 'FontSize', 12);
legend(ax3, bh3, 'Location','eastoutside', 'FontSize', 10);

clear d k n_total pct_fsm cumPct mid_y txt_col bh3 ax3

%% ── Save All Figures ──────────────────────────────────────────────────
res_dir = 'Results';
if ~isfolder(res_dir), mkdir(res_dir); end
ts       = char(datetime('now','Format','yyyy-MM-dd_HH-mm-ss'));
ctrl_tag = sprintf('%s_%s', upper(CONTROL_MODE), ts);
try
    exportgraphics(fig1, fullfile(res_dir, sprintf('Fig1_MicroDynamics_%s.png',  ctrl_tag)), 'Resolution',200);
    exportgraphics(fig2, fullfile(res_dir, sprintf('Fig2_Waterfall_%s.png',      ctrl_tag)), 'Resolution',200);
    exportgraphics(fig3, fullfile(res_dir, sprintf('Fig3_FSM_StateBar_%s.png',   ctrl_tag)), 'Resolution',200);
catch
    saveas(fig1, fullfile(res_dir, sprintf('Fig1_MicroDynamics_%s.png',  ctrl_tag)));
    saveas(fig2, fullfile(res_dir, sprintf('Fig2_Waterfall_%s.png',      ctrl_tag)));
    saveas(fig3, fullfile(res_dir, sprintf('Fig3_FSM_StateBar_%s.png',   ctrl_tag)));
end
fprintf('\xe2\x9c\x93 Figures saved to Results/\n\n');

%% ════════════════════════════════════════════════════════════════════════
%% LOCAL HELPERS
%% ════════════════════════════════════════════════════════════════════════

function shadeIdleRegions(ax, th, idle_mask, col, ymax)
%SHADEIDLEREGIONS  Draw background patches wherever idle_mask == true,
%  then push them to the bottom of the drawing stack so plotted data shows
%  on top.  th and idle_mask must be the same length.
    in_idle = false;  t0 = th(1);
    for k = 1:length(idle_mask)
        if idle_mask(k) && ~in_idle
            t0 = th(k);  in_idle = true;
        elseif ~idle_mask(k) && in_idle
            p = patch(ax, [t0 th(k) th(k) t0], [0 0 ymax ymax], col, ...
                'EdgeColor','none', 'FaceAlpha',0.60, 'HandleVisibility','off');
            uistack(p, 'bottom');
            in_idle = false;
        end
    end
    if in_idle   % close any open region at the end of the window
        p = patch(ax, [t0 th(end) th(end) t0], [0 0 ymax ymax], col, ...
            'EdgeColor','none', 'FaceAlpha',0.60, 'HandleVisibility','off');
        uistack(p, 'bottom');
    end
end