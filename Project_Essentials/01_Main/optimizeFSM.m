%% ╔══════════════════════════════════════════════════════════════════════════════╗
%% ║                         optimizeFSM.m — FSM Parameter Sweep                 ║
%% ║    Parametric optimization of tracking_deadband and batch_interval          ║
%% ║             for ISTANBUL location using three representative days           ║
%% ╚══════════════════════════════════════════════════════════════════════════════╝
%
%  Sweeps two FSM parameters across realistic ranges:
%    • tracking_deadband:  1.0° → 5.0° (step 1.0°)
%    • batch_interval:    30 s → 120 s (step 30 s)
%
%  For each (deadband, interval) pair, runs a 12-month simulation and
%  records the Annual Net Efficiency Gain (%). Results are visualized
%  as a 3D surface plot suitable for publication (LaTeX rendering).
%
%  Runtime: ~3–5 minutes depending on machine. Progress printed per iteration.

clear; clc; close all;
addpath(genpath(pwd));

% ═══════════════════════════════════════════════════════════════════════════════
% SETUP: Global configuration
% ═══════════════════════════════════════════════════════════════════════════════

LOCATION = 'ISTANBUL';              % Fixed location for sweep
CONTROL_MODE = 'pid';               % 'pid' or 'fuzzy'
PHYSICS_MODEL = 'THEORETICAL';      % servo model
SUPPRESS_PLOTS = true;              % Suppress figure generation during sweep

% ── SPEED OPTIMIZATION SETTINGS ─────────────────────────────────────────────
USE_PARFOR = true;                  % true: parallel for (faster if toolbox available)
SPEED_MODE = 'fast';                % 'fast'=reduced dt, 'normal'=full resolution
% fast mode settings:
%   dt_outer = 5 s (instead of 1 s)  → 5× fewer iterations
%   N_sub = 50  (instead of 100)      → 2× fewer servo sub-steps
%   month_select = 4 months only
MONTH_SELECT = [1, 2, 11, 12];      % Jan, Feb, Nov, Dec (first 2 + last 2)

% Parameter sweep ranges
DEADBAND_MIN   = 1.0;               % [°]
DEADBAND_MAX   = 5.0;
DEADBAND_STEP  = 1.0;
BATCH_INTERVAL_MIN   = 30;          % [s]
BATCH_INTERVAL_MAX   = 120;
BATCH_INTERVAL_STEP  = 30;

% Build sweep vectors
deadbands = DEADBAND_MIN:DEADBAND_STEP:DEADBAND_MAX;
batch_intervals = BATCH_INTERVAL_MIN:BATCH_INTERVAL_STEP:BATCH_INTERVAL_MAX;
n_deadband = length(deadbands);
n_batch = length(batch_intervals);

fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════════════════╗\n');
fprintf('║                      FSM PARAMETER SWEEP OPTIMIZATION                 ║\n');
fprintf('║                          Location: %s                            ║\n', LOCATION);
fprintf('║                      Control: %s  |  Physics: %s         ║\n', upper(CONTROL_MODE), PHYSICS_MODEL);
fprintf('║                    ⚡ FAST MODE: 4 months | dt_outer=%d s | N_sub=50      ║\n', ...
    strcmp(SPEED_MODE, 'fast') * 5 + strcmp(SPEED_MODE, 'normal') * 1);
fprintf('╚════════════════════════════════════════════════════════════════════════╝\n\n');
fprintf('Sweep Configuration:\n');
fprintf('  Tracking Deadband:  %.1f° → %.1f° (step %.1f°)  →  %d points\n', ...
    DEADBAND_MIN, DEADBAND_MAX, DEADBAND_STEP, n_deadband);
fprintf('  Batch Interval:     %d s → %d s (step %d s)  →  %d points\n', ...
    BATCH_INTERVAL_MIN, BATCH_INTERVAL_MAX, BATCH_INTERVAL_STEP, n_batch);
fprintf('  Months analyzed:    Jan, Feb, Nov, Dec (4 months)\n');
fprintf('  Total simulations:  %d × %d = %d runs\n\n', n_deadband, n_batch, n_deadband*n_batch);
if USE_PARFOR
    fprintf('  Parallelization:    ON (parfor)\n');
else
    fprintf('  Parallelization:    OFF (for)\n');
end
fprintf('  Speed mode:         %s\n', SPEED_MODE);
fprintf('  Expected speedup:   ~10–15× over full 12-month normal mode\n\n');

% Initialize results matrix
Gain_annual = zeros(n_deadband, n_batch);
Energy_net = zeros(n_deadband, n_batch);
Energy_para = zeros(n_deadband, n_batch);
ParaRatio = zeros(n_deadband, n_batch);

% ═══════════════════════════════════════════════════════════════════════════════
% PARAMETRIC SWEEP LOOP (with optional parallelization)
% ═══════════════════════════════════════════════════════════════════════════════

total_runs = n_deadband * n_batch;
tic;

fprintf('Starting sweep...\n');
fprintf('─────────────────────────────────────────\n');

if USE_PARFOR
    % ── PARALLEL EXECUTION (faster) ─────────────────────────────────────────
    try
        parpool('threads'); % Request thread-based pool
    catch
        % parpool already exists or toolbox unavailable
    end
    
    % Pre-compute loop parameters (meshgrid style)
    [db_grid, bi_grid] = meshgrid(deadbands, batch_intervals);
    all_db = db_grid(:);
    all_bi = bi_grid(:);
    
    % Initialize results as column vectors
    Gain_vec    = zeros(total_runs, 1);
    Energy_net_vec  = zeros(total_runs, 1);
    Energy_para_vec = zeros(total_runs, 1);
    ParaRatio_vec   = zeros(total_runs, 1);
    
    % Parallel loop
    parfor k = 1:total_runs
        [Gain_yr, E_net_yr, E_para_yr, Para_yr] = runAnnualSimulation(...
            LOCATION, CONTROL_MODE, PHYSICS_MODEL, ...
            all_db(k), all_bi(k), true, ...
            SPEED_MODE, MONTH_SELECT);
        
        Gain_vec(k) = Gain_yr;
        Energy_net_vec(k) = E_net_yr;
        Energy_para_vec(k) = E_para_yr;
        ParaRatio_vec(k) = Para_yr;
    end
    
    % Reshape back to 2D matrices
    Gain_annual = reshape(Gain_vec, n_batch, n_deadband)';
    Energy_net = reshape(Energy_net_vec, n_batch, n_deadband)';
    Energy_para = reshape(Energy_para_vec, n_batch, n_deadband)';
    ParaRatio = reshape(ParaRatio_vec, n_batch, n_deadband)';
    
else
    % ── SEQUENTIAL EXECUTION (slower, but fallback) ─────────────────────────
    run_counter = 0;
    
    for i_db = 1:n_deadband
        for i_bi = 1:n_batch
            run_counter = run_counter + 1;
            
            current_deadband = deadbands(i_db);
            current_batch = batch_intervals(i_bi);
            
            fprintf('  [%3d/%3d]  DB=%.1f°  BI=%3d s  →  ', run_counter, total_runs, ...
                current_deadband, current_batch);
            
            [Gain_yr, E_net_yr, E_para_yr, Para_yr] = runAnnualSimulation(...
                LOCATION, CONTROL_MODE, PHYSICS_MODEL, ...
                current_deadband, current_batch, true, ...
                SPEED_MODE, MONTH_SELECT);
            
            Gain_annual(i_db, i_bi) = Gain_yr;
            Energy_net(i_db, i_bi) = E_net_yr;
            Energy_para(i_db, i_bi) = E_para_yr;
            ParaRatio(i_db, i_bi) = Para_yr;
            
            fprintf('Gain=%+6.2f%%  Para=%.2f%%\n', Gain_yr, Para_yr);
        end
    end
    
end

elapsed = toc;
fprintf('─────────────────────────────────────────\n');
fprintf('✓ Parametric sweep complete!  (%.1f s)\n\n', elapsed);

% ═══════════════════════════════════════════════════════════════════════════════
% POST-PROCESSING: Find optimum, extract statistics
% ═══════════════════════════════════════════════════════════════════════════════

% Find the optimal (deadband, batch_interval) pair
[max_gain, idx_max] = max(Gain_annual(:));
[opt_i_db, opt_i_bi] = ind2sub(size(Gain_annual), idx_max);
opt_deadband = deadbands(opt_i_db);
opt_batch = batch_intervals(opt_i_bi);
opt_para = ParaRatio(opt_i_db, opt_i_bi);

fprintf('╔════════════════════════════════════════════════════════════════════════╗\n');
fprintf('║                          OPTIMIZATION RESULTS                         ║\n');
fprintf('╚════════════════════════════════════════════════════════════════════════╝\n\n');
fprintf('OPTIMAL PARAMETERS (Maximum Annual Net Gain):\n');
fprintf('  Tracking Deadband:  %.1f°\n', opt_deadband);
fprintf('  Batch Interval:     %d s\n', opt_batch);
fprintf('  Annual Net Gain:    %+.2f%%\n', max_gain);
fprintf('  Parasitic Ratio:    %.2f%%\n', opt_para);

% Secondary statistics
min_gain = min(Gain_annual(:));
mean_gain = mean(Gain_annual(:));
std_gain = std(Gain_annual(:), 0, 'all');
fprintf('\nGain Statistics Across Sweep:\n');
fprintf('  Maximum:  %+.2f%%\n', max_gain);
fprintf('  Minimum:  %+.2f%%\n', min_gain);
fprintf('  Mean:     %+.2f%%\n', mean_gain);
fprintf('  Std Dev:  %.2f%%\n', std_gain);

% ═══════════════════════════════════════════════════════════════════════════════
% PUBLICATION-GRADE VISUALIZATION
% ═══════════════════════════════════════════════════════════════════════════════

% Set global LaTeX rendering
set(groot, 'defaultTextInterpreter',              'latex');
set(groot, 'defaultAxesTickLabelInterpreter',     'latex');
set(groot, 'defaultLegendInterpreter',            'latex');

% Figure 1: 3D Surface Plot — Gain vs. Deadband & Batch Interval
fig1 = figure('Name','FSM Optimization Landscape', ...
    'Color','w', 'Position',[50 50 1200 800], 'NumberTitle','off');
ax1 = axes(fig1, 'Color','w');
hold(ax1, 'on');

% Create mesh grid for surface
[DB_mesh, BI_mesh] = meshgrid(deadbands, batch_intervals);

% Plot surface with jet colormap
surf(ax1, DB_mesh, BI_mesh, Gain_annual', ...
    'FaceAlpha', 0.85, 'EdgeColor','none', 'FaceColor','interp');

% Overlay the optimum point
scatter3(ax1, opt_deadband, opt_batch, max_gain, ...
    150, 'r', 'filled', 'MarkerEdgeColor',[0.55 0 0], 'LineWidth',2, ...
    'DisplayName',sprintf('Optimum: %.1f°, %ds', opt_deadband, opt_batch));

xlabel(ax1, 'Tracking Deadband ($^\circ$)', 'FontSize',12);
ylabel(ax1, 'Batch Interval (s)', 'FontSize',12);
zlabel(ax1, 'Annual Net Efficiency Gain (\%)', 'FontSize',12);
title(ax1, ['\textbf{FSM Parameter Optimization Surface} --- ' ...
    LOCATION ' $|$ ' upper(CONTROL_MODE) ' Controller'], 'FontSize', 13);

colorbar(ax1, 'Label','Gain (\%)', 'FontSize',11);
set(ax1, 'Box','on', 'LineWidth',1.2, 'FontSize',11, ...
    'XGrid','on', 'YGrid','on', 'ZGrid','on');
view(45, 30);
legend(ax1, 'Location','best', 'FontSize',10);

% Figure 2: Heatmap with contour lines
fig2 = figure('Name','FSM Optimization Heatmap', ...
    'Color','w', 'Position',[100 70 1100 750], 'NumberTitle','off');
ax2 = axes(fig2, 'Color','w');
hold(ax2, 'on');

imagesc(ax2, deadbands, batch_intervals, Gain_annual');
set(ax2, 'YDir','normal');
colormap(ax2, 'jet');
cb = colorbar(ax2, 'FontSize',11);
cb.Label.String = 'Gain (\%)';

% Overlay contour lines
[C, h_contour] = contour(ax2, deadbands, batch_intervals, Gain_annual', 12, ...
    'LineWidth',1.0, 'Color',[0.3 0.3 0.3]);
clabel(C, h_contour, 'FontSize',8);

% Mark the optimum
scatter(ax2, opt_deadband, opt_batch, 200, 'r', 'filled', ...
    'MarkerEdgeColor',[0.55 0 0], 'LineWidth', 2.5);
text(ax2, opt_deadband, opt_batch + 5, ...
    sprintf('Opt\n(%+.1f%%)', max_gain), ...
    'Color',[0.55 0 0], 'FontWeight','bold','FontSize',10, ...
    'HorizontalAlignment','center', 'VerticalAlignment','bottom', ...
    'Backgroundcolor','w', 'EdgeColor',[0.55 0 0]);

xlabel(ax2, 'Tracking Deadband ($^\circ$)', 'FontSize',12);
ylabel(ax2, 'Batch Interval (s)', 'FontSize',12);
title(ax2, ['\textbf{FSM Optimization Heatmap with Contours} --- ' ...
    LOCATION ' $|$ ' upper(CONTROL_MODE) ' Controller'], 'FontSize', 13);

set(ax2, 'Box','on', 'LineWidth',1.2, 'FontSize',11, ...
    'XTick',deadbands, 'YTick',batch_intervals, 'XGrid','on', 'YGrid','on');

% Figure 3: Slice plots showing 1D projections
fig3 = figure('Name','FSM Optimization Slices', ...
    'Color','w', 'Position',[150 100 1400 600], 'NumberTitle','off');
tl3 = tiledlayout(fig3, 1, 2, 'TileSpacing','compact', 'Padding','compact');
title(tl3, ['\textbf{FSM Optimization: 1D Slices} --- ' ...
    LOCATION ' $|$ ' upper(CONTROL_MODE)], 'FontSize', 13);

% Left tile: Gain vs. Deadband (at optimal batch_interval)
ax3L = nexttile(1);
plot(ax3L, deadbands, Gain_annual(:, opt_i_bi), '-o', ...
    'LineWidth', 2.0, 'MarkerSize', 7, 'Color', [0.2 0.6 0.2]);
scatter(ax3L, opt_deadband, max_gain, 150, 'r', 'filled', ...
    'MarkerEdgeColor',[0.55 0 0], 'LineWidth', 2);
grid(ax3L, 'on');
xlabel(ax3L, 'Tracking Deadband ($^\circ$)', 'FontSize',11);
ylabel(ax3L, 'Annual Net Gain (\%)', 'FontSize',11);
title(ax3L, sprintf('Gain vs.\ Deadband  (BI = %d s)', opt_batch), 'FontSize',11);
set(ax3L, 'Box','on', 'LineWidth',1.2, 'FontSize',10);

% Right tile: Gain vs. Batch Interval (at optimal deadband)
ax3R = nexttile(2);
plot(ax3R, batch_intervals, Gain_annual(opt_i_db, :), '-o', ...
    'LineWidth', 2.0, 'MarkerSize', 7, 'Color', [0.2 0.4 0.8]);
scatter(ax3R, opt_batch, max_gain, 150, 'r', 'filled', ...
    'MarkerEdgeColor',[0.55 0 0], 'LineWidth', 2);
grid(ax3R, 'on');
xlabel(ax3R, 'Batch Interval (s)', 'FontSize',11);
ylabel(ax3R, 'Annual Net Gain (\%)', 'FontSize',11);
title(ax3R, sprintf('Gain vs.\ Batch Interval  (DB = %.1f$$\\,^\\circ$$)', opt_deadband), 'FontSize',11);
set(ax3R, 'Box','on', 'LineWidth',1.2, 'FontSize',10);

% ─────────────────────────────────────────────────────────────────────────────
% SAVE FIGURES
% ─────────────────────────────────────────────────────────────────────────────

res_dir = 'Results';
if ~isfolder(res_dir), mkdir(res_dir); end
ts = char(datetime('now','Format','yyyy-MM-dd_HH-mm-ss'));
tag = sprintf('FSMOpt_%s_%s', LOCATION, ts);

try
    exportgraphics(fig1, fullfile(res_dir, sprintf('%s_Surface.png', tag)), 'Resolution',200);
    exportgraphics(fig2, fullfile(res_dir, sprintf('%s_Heatmap.png', tag)), 'Resolution',200);
    exportgraphics(fig3, fullfile(res_dir, sprintf('%s_Slices.png',  tag)), 'Resolution',200);
catch
    saveas(fig1, fullfile(res_dir, sprintf('%s_Surface.png', tag)));
    saveas(fig2, fullfile(res_dir, sprintf('%s_Heatmap.png', tag)));
    saveas(fig3, fullfile(res_dir, sprintf('%s_Slices.png',  tag)));
end
fprintf('\n✓ Figures saved to Results/\n\n');

% ═══════════════════════════════════════════════════════════════════════════════
% NESTED FUNCTION: Core 12-month simulation with custom FSM parameters
% ═══════════════════════════════════════════════════════════════════════════════

function [Gain_yr, E_net_yr, E_para_yr, Para_yr] = runAnnualSimulation(...
    loc_name, control_mode, physics_model, deadband, batch_int, suppress_figs, ...
    speed_mode, month_select)
    %RUNANNUALSIMULATION  Run monthly simulation with FSM parameter override.
    %
    % Inputs:
    %   loc_name       — 'ISTANBUL', 'HELSINKI', 'ASWAN'
    %   control_mode   — 'pid' or 'fuzzy'
    %   physics_model  — 'THEORETICAL'
    %   deadband       — tracking_deadband [°]
    %   batch_int      — batch_interval [s]
    %   suppress_figs  — logical
    %   speed_mode     — 'fast' or 'normal'
    %   month_select   — array of month indices [1..12] to simulate (e.g., [1,2,11,12])
    %
    % Outputs:
    %   Gain_yr   — Annual Net Efficiency Gain [%]
    %   E_net_yr  — Annual Net Energy [Wh]
    %   E_para_yr — Annual Parasitic Energy [Wh]
    %   Para_yr   — Parasitic Ratio [%]
    
    % Default arguments
    if nargin < 7, speed_mode = 'normal'; end
    if nargin < 8, month_select = 1:12; end  % All months by default
    
    % Progress message
    fprintf('[Run] Deadband=%.1f°  Batch Interval=%3d s\n', deadband, batch_int);
    
    % Speed mode configuration
    if strcmp(speed_mode, 'fast')
        dt_outer = 5.00;    % 5 sec outer step (instead of 1 sec)
        N_sub = 50;         % 50 sub-steps (instead of 100)
    else
        dt_outer = 1.00;    % Default: 1 sec
        N_sub = 100;        % Default: 100 sub-steps
    end
    dt_inner = 0.01;        % Always 0.01 s (servo control rate)
    
    % Load geographic config
    Geo = getGeoConfig(loc_name);
    
    % Build Scenario
    Scenario = struct();
    Scenario.lat = Geo.Lat;
    Scenario.lon = Geo.Lon;
    Scenario.tz = Geo.TZ;
    Scenario.pvgis_file = Geo.PVGIS_File;
    Scenario.t_start_hour = 5;       % 5 AM
    Scenario.duration_sec = 15*3600; % 15-hour window
    
    % Load PVGIS
    try
        PVData_full = loadPVGIS(Geo.PVGIS_File);
    catch
        Gain_yr = nan; E_net_yr = nan; E_para_yr = nan; Para_yr = nan;
        return;
    end
    
    % Configuration constants (same as CompareYield.m)
    representative_days = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];
    month_lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    
    % Select only the requested months
    if ~isempty(month_select)
        representative_days = representative_days(month_select);
        month_lengths = month_lengths(month_select);
    end
    nDays = length(representative_days);
    
    PANEL_AREA = 0.04;   % [m²]
    ETA_PANEL = 0.20;    % 20% efficiency
    TILT_DEG = Geo.Lat;
    b0 = 0.05;           % ASHRAE IAM coefficient
    N_fixed = [0; -cosd(TILT_DEG); sind(TILT_DEG)];
    N_fixed = N_fixed / norm(N_fixed);
    NOCT = 45.0;
    GAMMA_T = 0.004;
    
    % FSM Parameters — with sweep overrides
    SupervisorParams = struct();
    SupervisorParams.night_threshold = 0.10;
    SupervisorParams.sun_lost_threshold = 0.15;
    SupervisorParams.sun_found_threshold = 0.30;
    SupervisorParams.lock_threshold = 0.50;
    SupervisorParams.tracking_deadband = deadband;   % ← SWEEP PARAMETER
    SupervisorParams.batch_interval = batch_int;     % ← SWEEP PARAMETER
    SupervisorParams.max_burst_time = 2.0;
    SupervisorParams.search_speed = 3.0;
    SupervisorParams.zenith_pan_lock = false;
    SupervisorParams.tau_derivative = 2.0;
    
    % Parasitic model
    I_SPIN_BASE = 0.17;
    V_SUPPLY = 6.0;
    
    % Servo query (for reference only)
    tmpState = struct('Angle',0,'Velocity',0,'Current',0,'Energy',0);
    [~, ~, ServoProps] = stepTheoreticalServo(tmpState, 0, dt_inner, 'Pan');
    
    % Initialize results storage
    Results = struct();
    AllData = cell(nDays, 1);
    
    % ───────────────────────────────────────────────────────────────────────────
    % MAIN SIMULATION LOOP — 12 months (same logic as CompareYield.m)
    % ───────────────────────────────────────────────────────────────────────────
    
    for d = 1:nDays
        n = representative_days(d);
        delta_deg = 23.45 * sin(deg2rad((360/365) * (284 + n)));
        pvgis_year = year(PVData_full.time(1));
        ref_date = datetime(pvgis_year, 1, 1) + days(n - 1);
        
        T_mean_loc = max(5.0, 32.0 - 0.45 * Geo.Lat);
        Delta_T_loc = max(5.0, 13.0 - 0.10 * Geo.Lat);
        T_ambient = T_mean_loc + Delta_T_loc * cos(2*pi*(n - 205)/365); % Klein (1977), sign fixed
        
        [PVData, DayStats] = filterPVGISbyDate(PVData_full, 'DAILY', ref_date);
        
        t_start_s = Scenario.t_start_hour * 3600;
        t_end_s = t_start_s + Scenario.duration_sec;
        time_vec = (t_start_s : dt_outer : t_end_s)';
        N = length(time_vec);
        SimDate = DayStats.date + hours(Scenario.t_start_hour);
        
        % Logging arrays
        G_pvgis = zeros(N,1);
        P_fixed = zeros(N,1);
        P_tracker_gross = zeros(N,1);
        P_parasitic = zeros(N,1);
        P_tracker_net = zeros(N,1);
        P_delivered = zeros(N,1);
        FSM_log = cell(N,1);
        for k=1:N, FSM_log{k}='IDLE'; end
        T_cell_tracker = zeros(N,1);
        T_cell_fixed = zeros(N,1);
        f_derate_log = ones(N,1);
        IAM_tracker_log = zeros(N,1);
        
        % Initialize tracker at sun position
        current_time_init = SimDate;
        [S_init, el_init, az_init] = getSunVector(...
            Scenario.lat, Scenario.lon, current_time_init, Scenario.tz);
        
        if el_init > 0
            init_pan = az_init; if init_pan > 180, init_pan = init_pan - 360; end
            init_tilt = max(-90, min(90, 90 - el_init));
            [adj_pan0, adj_tilt0, ~, ~] = applyFlipLogic(init_pan, init_tilt);
            StatePan = struct('Angle',adj_pan0, 'Velocity',0,'Current',0,'Energy',0);
            StateTilt = struct('Angle',adj_tilt0, 'Velocity',0,'Current',0,'Energy',0);
        else
            StatePan = struct('Angle',0, 'Velocity',0,'Current',0,'Energy',0);
            StateTilt = struct('Angle',80, 'Velocity',0,'Current',0,'Energy',0);
        end
        
        % FSM state
        FSM_State = struct('mode','TRACKING', ...
            'e_pan_prev',0,'e_tilt_prev',0, ...
            'de_pan_filtered',0,'de_tilt_filtered',0, ...
            'search_phase',0,'hold_timer',0,'burst_timer',0, ...
            'was_night',false,'park_target_pan',0,'park_target_tilt',90);
        
        ControlState = struct('I_pan',0,'I_tilt',0,'de_pan_filt',0,'de_tilt_filt',0);
        
        CommandSmoothing = struct(...
            'target_pan_smoothed', StatePan.Angle, ...
            'target_tilt_smoothed', StateTilt.Angle);
        
        % ───────────────────────────────────────────────────────────────────────
        % OUTER LOOP (1 Hz) + INNER LOOP (100 Hz sub-stepping)
        % ───────────────────────────────────────────────────────────────────────
        
        for i = 1:N
            sim_t = time_vec(i);
            current_time = SimDate + seconds(sim_t - t_start_s);
            
            [G_now, ~] = getPVGISatTime(sim_t, PVData);
            G_pvgis(i) = G_now;
            
            [S_vec, elevation, azimuth] = getSunVector(...
                Scenario.lat, Scenario.lon, current_time, Scenario.tz);
            
            if elevation <= 0 || G_now < 1
                FSM_log{i} = 'IDLE';
                continue;
            end
            
            % Fixed panel power
            cos_f = max(0, dot(S_vec, N_fixed));
            if cos_f > 0.01
                IAM_f = max(0, 1 - b0*(1/cos_f - 1));
            else
                IAM_f = 0;
            end
            P_fixed(i) = G_now * PANEL_AREA * ETA_PANEL * cos_f * IAM_f;
            
            % Ideal tracker angles
            [az_deg, el_deg] = cartesian2spherical(S_vec);
            ideal_pan = az_deg; if ideal_pan > 180, ideal_pan = ideal_pan - 360; end
            ideal_tilt = max(-90, min(90, 90 - el_deg));
            [adj_pan, adj_tilt, is_flip, is_reachable] = applyFlipLogic(ideal_pan, ideal_tilt);
            
            % LDR readout
            theta_p_prev = StatePan.Angle;
            theta_t_prev = StateTilt.Angle;
            cp=cosd(theta_p_prev); sp=sind(theta_p_prev); ct=cosd(theta_t_prev); st=sind(theta_t_prev);
            Sx = cp*S_vec(1)-sp*S_vec(2); Sy = sp*S_vec(1)+cp*S_vec(2);
            S_body_1hz = [Sx; ct*Sy-st*S_vec(3); st*Sy+ct*S_vec(3)];
            S_body_1hz_n = S_body_1hz / (norm(S_body_1hz)+1e-8);
            [~, LDR_V, ~, ~, ~, ~] = readLDRs(S_body_1hz_n);
            
            % FSM step
            [ErrorSignal, FSM_State, ~, ~] = StateManagerFSM(...
                LDR_V, S_body_1hz, theta_p_prev, theta_t_prev, ...
                FSM_State, SupervisorParams, dt_outer, is_flip);
            
            % Thermodynamic cutoff
            if G_now < 250
                FSM_State.mode = 'IDLE';
            end
            
            fsm_active = ismember(FSM_State.mode, {'TRACKING','SEARCH','PARK'});
            
            % ───────────────────────────────────────────────────────────────
            % INNER LOOP: PID + Servo (100 Hz)
            % ───────────────────────────────────────────────────────────────
            
            I_pan_accum = 0;
            I_tilt_accum = 0;
            
            for s = 1:N_sub
                if strcmp(control_mode, 'fuzzy')
                    [VelCmd, ControlState, ~, ~] = FuzzyLogicController(...
                        ErrorSignal, ControlState, dt_inner);
                else
                    [VelCmd, ControlState, ~, ~] = PID_VelocityController(...
                        ErrorSignal, ControlState, struct(), dt_inner);
                end
                
                theta_pan_curr = StatePan.Angle;
                theta_tilt_curr = StateTilt.Angle;
                tgt_pan = max(-180, min(180, theta_pan_curr + VelCmd.v_pan * dt_inner));
                tgt_tilt = max(-90, min(90, theta_tilt_curr + VelCmd.v_tilt * dt_inner));
                
                if is_reachable && fsm_active
                    tgt_pan = tgt_pan + 0.5*(adj_pan - tgt_pan);
                    tgt_tilt = tgt_tilt + 0.5*(adj_tilt - tgt_tilt);
                end
                
                smooth_a = 0.95;
                if fsm_active
                    CommandSmoothing.target_pan_smoothed = ...
                        (1-smooth_a)*CommandSmoothing.target_pan_smoothed + smooth_a*tgt_pan;
                    CommandSmoothing.target_tilt_smoothed = ...
                        (1-smooth_a)*CommandSmoothing.target_tilt_smoothed + smooth_a*tgt_tilt;
                else
                    CommandSmoothing.target_pan_smoothed = theta_pan_curr;
                    CommandSmoothing.target_tilt_smoothed = theta_tilt_curr;
                end
                
                [StatePan, ~, ~] = stepTheoreticalServo(...
                    StatePan, CommandSmoothing.target_pan_smoothed, dt_inner, 'Pan');
                [StateTilt, ~, ~] = stepTheoreticalServo(...
                    StateTilt, CommandSmoothing.target_tilt_smoothed, dt_inner, 'Tilt');
                
                I_pan_accum = I_pan_accum + StatePan.Current;
                I_tilt_accum = I_tilt_accum + StateTilt.Current;
            end
            
            % ───────────────────────────────────────────────────────────────
            % LOGGING (1 Hz, after inner loop)
            % ───────────────────────────────────────────────────────────────
            
            theta_pan_f = StatePan.Angle;
            theta_tilt_f = StateTilt.Angle;
            cp2=cosd(theta_pan_f); sp2=sind(theta_pan_f);
            ct2=cosd(theta_tilt_f); st2=sind(theta_tilt_f);
            Sx2=cp2*S_vec(1)-sp2*S_vec(2); Sy2=sp2*S_vec(1)+cp2*S_vec(2);
            Sb = [Sx2; ct2*Sy2-st2*S_vec(3); st2*Sy2+ct2*S_vec(3)];
            Sbn = Sb / (norm(Sb)+1e-8);
            
            cos_t = max(0, Sbn(3));
            if cos_t > 0.01
                IAM_t = max(0, 1 - b0*(1/cos_t - 1));
            else
                IAM_t = 0;
            end
            IAM_tracker_log(i) = IAM_t;
            P_tracker_gross(i) = G_now * PANEL_AREA * ETA_PANEL * cos_t * IAM_t;
            
            T_cell_tracker(i) = T_ambient + ((NOCT - 20) / 800) * G_now * IAM_t;
            T_cell_fixed(i) = T_ambient + ((NOCT - 20) / 800) * G_now * IAM_f;
            
            f_derate_tracker = 1 - GAMMA_T * max(0, T_cell_tracker(i) - 25);
            f_derate_fixed = 1 - GAMMA_T * max(0, T_cell_fixed(i) - 25);
            f_derate_log(i) = f_derate_tracker;
            
            P_tracker_gross(i) = P_tracker_gross(i) * f_derate_tracker;
            P_fixed(i) = P_fixed(i) * f_derate_fixed;
            
            is_hold = ismember(FSM_State.mode, {'HOLD','IDLE'});
            if is_hold
                I_motor = 0;
            else
                I_pan_avg = I_pan_accum / N_sub;
                I_tilt_avg = I_tilt_accum / N_sub;
                I_motor = I_pan_avg + I_tilt_avg;
            end
            P_parasitic(i) = I_motor * V_SUPPLY;
            P_tracker_net(i) = P_tracker_gross(i) - P_parasitic(i);
            P_delivered(i) = max(0, P_tracker_net(i));
            FSM_log{i} = FSM_State.mode;
        end
        
        % ───────────────────────────────────────────────────────────────────
        % DAY ENERGY SUMMATION
        % ───────────────────────────────────────────────────────────────────
        
        E_fixed = trapz(time_vec, P_fixed) / 3600;
        E_gross = trapz(time_vec, P_tracker_gross) / 3600;
        E_para = trapz(time_vec, P_parasitic) / 3600;
        E_net = trapz(time_vec, P_delivered) / 3600;
        Para_r = 100 * E_para / (E_gross + 1e-9);
        Net_gain = 100 * (E_net - E_fixed) / (E_fixed + 1e-9);
        
        % Store in Results struct
        Results(d).label = sprintf('M%02d', d);
        Results(d).month_length = month_lengths(d);
        Results(d).DayStats = DayStats;
        Results(d).E_fixed = E_fixed;
        Results(d).E_gross = E_gross;
        Results(d).E_para = E_para;
        Results(d).E_net = E_net;
        Results(d).Para_r = Para_r;
        Results(d).Net_gain = Net_gain;
        Results(d).T_ambient = T_ambient;
        Results(d).delta_deg = delta_deg;
        Results(d).julian_day = representative_days(d);
        
        AllData{d}.time_vec = time_vec;
        AllData{d}.t_start_s = t_start_s;
        AllData{d}.P_fixed = P_fixed;
        AllData{d}.P_tracker_gross = P_tracker_gross;
        AllData{d}.P_tracker_net = P_tracker_net;
        AllData{d}.P_delivered = P_delivered;
        AllData{d}.P_parasitic = P_parasitic;
        AllData{d}.G_pvgis = G_pvgis;
        AllData{d}.FSM_log = FSM_log;
        AllData{d}.T_cell_tracker = T_cell_tracker;
        AllData{d}.T_cell_fixed = T_cell_fixed;
        AllData{d}.f_derate_log = f_derate_log;
        AllData{d}.IAM_tracker_log = IAM_tracker_log;
        AllData{d}.T_ambient = T_ambient;
        AllData{d}.delta_deg = delta_deg;
        AllData{d}.julian_day = representative_days(d);
        AllData{d}.month_days = month_lengths(d);
        AllData{d}.E_fixed_cum = cumtrapz(time_vec, P_fixed) / 3600;
        AllData{d}.E_delivered_cum = cumtrapz(time_vec, P_delivered) / 3600;
        AllData{d}.E_gross_cum = cumtrapz(time_vec, P_tracker_gross) / 3600;
    end
    
    % ───────────────────────────────────────────────────────────────────────
    % ANNUAL EXTRAPOLATION
    % ───────────────────────────────────────────────────────────────────────
    
    E_fixed_yr = 0;
    E_gross_yr = 0;
    E_para_yr = 0;
    E_net_yr = 0;
    
    for d = 1:nDays
        w = month_lengths(d);
        E_fixed_yr = E_fixed_yr + Results(d).E_fixed * w;
        E_gross_yr = E_gross_yr + Results(d).E_gross * w;
        E_para_yr = E_para_yr + Results(d).E_para * w;
        E_net_yr = E_net_yr + Results(d).E_net * w;
    end
    
    Para_yr = 100 * E_para_yr / (E_gross_yr + 1e-9);
    Gain_yr = 100 * (E_net_yr - E_fixed_yr) / (E_fixed_yr + 1e-9);
    
    % Close figures if requested (with error handling for graphics issues)
    if suppress_figs
        try
            close all;
        catch
            % Silently ignore graphics errors (parfor may have issues closing figs)
        end
    end
    
end

% ═══════════════════════════════════════════════════════════════════════════════
% END OF optimizeFSM.m
% ═══════════════════════════════════════════════════════════════════════════════
