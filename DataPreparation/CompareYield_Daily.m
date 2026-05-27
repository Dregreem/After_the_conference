%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  CompareYield_Daily.m                                                ║
%% ║  FIXED vs TRACKER — WITH CELL TEMPERATURE MODEL (DAILY + INTERP)     ║
%% ║                                                                       ║
%% ║  Base: CompareYield_TMY_Temp.m                                        ║
%% ║  Data: prepareDataForAnalysis_Daily() → prepared_data_DAILY_*.mat    ║
%% ║                                                                       ║
%% ║  Key Features:                                                        ║
%% ║    • Loads pre-processed DAILY data (daily + sinusoidal interpolation)║
%% ║    • Faiman cell-temperature model at every second                    ║
%% ║    • Temperature-corrected efficiency (fixed & tracker)               ║
%% ║    • Full servo control (PID + FSM) simulation                        ║
%% ║    • Annual roll-up with monthly breakdown                            ║
%% ║    • Detailed timestep CSV + figures                                  ║
%% ║                                                                       ║
%% ║  Data Source: DAILY-INTERPOLATED (daily PVGIS + daily T/WS)          ║
%% ║                                                                       ║
%% ╚══════════════════════════════════════════════════════════════════════╝

if ~exist('BATCH_MODE','var')
    clear; clc; close all;
else
    clc; close all;
end
addpath(genpath(pwd));

set(groot,'defaultTextInterpreter',              'tex');
set(groot,'defaultAxesTickLabelInterpreter',     'tex');
set(groot,'defaultLegendInterpreter',            'tex');
set(groot,'defaultColorbarTickLabelInterpreter', 'tex');

if ~exist('loc_name', 'var'), loc_name = 'ISTANBUL'; end
if exist('RESULTS_BASE','var')
    res_dir = fullfile(RESULTS_BASE, 'Results', upper(loc_name), 'Daily');
else
    res_dir = fullfile(fileparts(mfilename('fullpath')), 'Results', upper(loc_name), 'Daily');
end
if ~isfolder(res_dir), mkdir(res_dir); end

%% ── DATA TYPE IDENTIFIER ─────────────────────────────────────────────────
data_source = 'DAILY';

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║    FIXED vs TRACKER — DAILY DATA (with Temperature)          ║\n');
fprintf('║  %s | 1-Second Resolution | Representative Days       ║\n', upper(loc_name));
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% ── LOAD PREPARED DATA (HOURLY) ──────────────────────────────────────────
fprintf('LOADING PREPARED DATA:\n');
fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
fprintf('Data Source: %s\n', data_source);
fprintf('Location   : %s\n\n', upper(loc_name));

addpath(genpath('DataPreparation'));  % Ensure DataPreparation functions are available

try
    PreparedData = loadPreparedData(loc_name);
catch ME
    error('Failed to load prepared data: %s\n%s', loc_name, ME.message);
end

fprintf('  ✓ Data loaded successfully\n');
fprintf('  ✓ Data type: %s\n', PreparedData.data_type);
fprintf('  ✓ Records: %d\n\n', PreparedData.n_records);

% Extract prepared data
Geo = PreparedData.Geo;
solar_data = PreparedData.solar_data;
T2m_lut = PreparedData.T2m_lut;
WS_lut = PreparedData.WS_lut;
season_names = PreparedData.season_names;
month_lengths = PreparedData.month_lengths;

fprintf('Location : %s\n', Geo.Name);
fprintf('Coords   : %.2f°N  %.2f°E  UTC%+d\n\n', Geo.Lat, Geo.Lon, Geo.TZ);

%% ── CONTROL & PHYSICS PARAMETERS ─────────────────────────────────────────
CONTROL_MODE  = 'pid';
PHYSICS_MODEL = 'THEORETICAL';

dt_outer = 1.00;
dt_inner = 0.01;
N_sub    = round(dt_outer / dt_inner);

fprintf('CONTROL_MODE  : %s\n',   upper(CONTROL_MODE));
fprintf('PHYSICS_MODEL : %s  + Faiman Cell-Temperature Model\n', PHYSICS_MODEL);
fprintf('dt_outer      : %.2f s\n', dt_outer);
fprintf('dt_inner      : %.2f s  (%d sub-steps per outer step)\n\n', dt_inner, N_sub);

%% ── PANEL PARAMETERS ─────────────────────────────────────────────────────
PANEL_AREA = 0.04;    % [m²]
ETA_STC    = 0.20;    % efficiency at STC (25°C, 1000 W/m²)
ETA_PANEL  = ETA_STC;

% Temperature model (Faiman / IEC 61853-2)
U0      = 25.0;   % free-convection coefficient  [W m⁻² K⁻¹]
U1      =  6.84;  % wind-dependent coefficient   [W m⁻² K⁻¹ / (m/s)]
T_STC   = 25.0;   % STC reference temperature    [°C]
gamma_P = -0.004; % power temperature coefficient [1/°C]

%% ── FSM PARAMETERS ───────────────────────────────────────────────────────
SupervisorParams = struct();
SupervisorParams.night_threshold     = 0.10;
SupervisorParams.sun_lost_threshold  = 0.15;
SupervisorParams.sun_found_threshold = 0.30;
SupervisorParams.lock_threshold      = 1.5;
SupervisorParams.tracking_deadband   = 3.0;
SupervisorParams.batch_interval      = 150.0;
SupervisorParams.max_burst_time      = 2.0;
SupervisorParams.search_speed        = 3.0;
SupervisorParams.zenith_pan_lock     = false;
SupervisorParams.tau_derivative      = 2.0;

V_SUPPLY = 6.0;

%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% MAIN SIMULATION LOOP (12 representative days / months)
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

nDays = 12;
Results = struct();
AllData = cell(nDays, 1);

for d = 1:nDays
    month_data = solar_data(solar_data.Month == d, :);
    N = height(month_data);

    if N < 86400
        warning('Month %d has fewer than 86400 rows. Skipping.', d);
        continue;
    end

    representative_days = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];
    n_julian  = representative_days(d);
    delta_deg = 23.45 * sin(deg2rad((360/365) * (284 + n_julian)));
    G_peak    = max(month_data.GHI);
    daylight_count = sum(month_data.Sun_Elevation > 0 & month_data.GHI >= 10);
    daylight_hours = daylight_count / 3600;

    fprintf('══════════════════════════════════════════════════════════\n');
    fprintf('  Month  %d/12 : %s\n', d, season_names{d});
    fprintf('  Julian n=%-3d | delta=%+.2f deg | PID | %s\n', n_julian, delta_deg, Geo.Name);
    fprintf('══════════════════════════════════════════════════════════\n');
    fprintf('  G_peak: %.1f W/m2 | Active Daylight: %.1f h\n', G_peak, daylight_hours);

    time_vec  = month_data.Time_in_Seconds;
    t_start_s = time_vec(1);

    % Precompute hourly T2m and WS for this month (one value per second)
    utc_hour_idx = min(23, floor(double(time_vec) / 3600));  % 0-based
    T_amb_vec = T2m_lut(d, utc_hour_idx + 1)';   % [N×1]
    WS_vec    = WS_lut (d, utc_hour_idx + 1)';   % [N×1]

    % Initialise servo angles from first lit second
    noon_idx = find(month_data.Sun_Elevation > 0 & month_data.GHI >= 10, 1, 'first');
    if ~isempty(noon_idx)
        init_el  = month_data.Sun_Elevation(noon_idx);
        init_pan = month_data.Sun_Azimuth(noon_idx);
        if init_pan > 180, init_pan = init_pan - 360; end
        init_pan  = max(-90, min(90, init_pan));
        init_tilt = max(0,   min(85, 90 - init_el));
    else
        init_pan  = 0;
        init_tilt = 45;
    end

    StatePan  = struct('Angle', init_pan,  'Velocity', 0, 'Current', 0, 'Energy', 0);
    StateTilt = struct('Angle', init_tilt, 'Velocity', 0, 'Current', 0, 'Energy', 0);
    fprintf('  Init: Pan=%.1f°  Tilt=%.1f°\n\n', StatePan.Angle, StateTilt.Angle);

    FSM_State = struct('mode','IDLE', ...
        'e_pan_prev',0, 'e_tilt_prev',0, ...
        'de_pan_filtered',0, 'de_tilt_filtered',0, ...
        'search_phase',0, 'hold_timer',0, 'burst_timer',0, ...
        'was_night',false, 'park_target_pan',0, 'park_target_tilt',90, ...
        'e_total_prev', 90);

    ControlState     = struct('I_pan',0,'I_tilt',0,'de_pan_filt',0,'de_tilt_filt',0);
    CommandSmoothing = struct('target_pan_smoothed', StatePan.Angle, ...
                              'target_tilt_smoothed', StateTilt.Angle);

    %% Pre-allocate logs
    G_log           = zeros(N,1);
    P_fixed         = zeros(N,1);
    P_tracker_gross = zeros(N,1);
    P_parasitic     = zeros(N,1);
    P_tracker_net   = zeros(N,1);
    cos_theta_log   = zeros(N,1);
    theta_tilt_log  = zeros(N,1);
    FSM_log         = cell(N,1);
    for k = 1:N, FSM_log{k} = 'IDLE'; end

    % Temperature logs
    T_cell_fix_log  = zeros(N,1);
    T_cell_trk_log  = zeros(N,1);
    eta_fix_log     = zeros(N,1);
    eta_trk_log     = zeros(N,1);

    was_in_override = false;

    tic;
    for i = 1:N

        ghi_now  = month_data.GHI(i);
        beam_now = month_data.Beam(i);
        dhi_now  = month_data.DHI(i);
        sun_elev = month_data.Sun_Elevation(i);
        sun_az   = month_data.Sun_Azimuth(i);
        T_amb    = T_amb_vec(i);
        WS       = WS_vec(i);

        G_log(i) = ghi_now;

        %% Night / pre-dawn gate
        if sun_elev <= 0 || ghi_now < 10
            FSM_log{i}        = 'IDLE';
            T_cell_fix_log(i) = T_amb;
            T_cell_trk_log(i) = T_amb;
            eta_fix_log(i)    = ETA_STC;
            eta_trk_log(i)    = ETA_STC;
            continue;
        end

        %% STEP 1 — Fixed panel power WITH temperature correction
        T_cell_fix = T_amb + ghi_now / (U0 + U1*WS);
        T_cell_fix = max(T_amb, T_cell_fix);
        eta_fix    = ETA_STC * (1 + gamma_P * (T_cell_fix - T_STC));
        eta_fix    = max(0.01, eta_fix);

        P_fixed(i) = ghi_now * PANEL_AREA * eta_fix;

        T_cell_fix_log(i) = T_cell_fix;
        eta_fix_log(i)    = eta_fix;

        %% STEP 2 — Sun vector in world frame
        el_rad = deg2rad(sun_elev);
        az_rad = deg2rad(sun_az);
        S_vec  = [cos(el_rad)*sin(az_rad); cos(el_rad)*cos(az_rad); sin(el_rad)];

        %% STEP 3 — Body-frame sun vector & LDR simulation
        theta_p_curr = StatePan.Angle;
        theta_t_curr = StateTilt.Angle;

        cp = cosd(theta_p_curr); sp = sind(theta_p_curr);
        ct = cosd(theta_t_curr); st = sind(theta_t_curr);
        Sx = cp*S_vec(1) - sp*S_vec(2);
        Sy = sp*S_vec(1) + cp*S_vec(2);
        S_body   = [Sx; ct*Sy - st*S_vec(3); st*Sy + ct*S_vec(3)];
        S_body_n = S_body / (norm(S_body) + 1e-8);

        [~, LDR_V, ~, ~, ~, ~] = readLDRs(S_body_n);

        %% STEP 3b — Ephemeris target + conditional flip
        ideal_pan  = sun_az;
        if ideal_pan > 180, ideal_pan = ideal_pan - 360; end
        ideal_tilt = max(0, min(85, 90 - sun_elev));

        use_ephemeris_override = false;
        override_target_pan    = ideal_pan;
        override_target_tilt   = ideal_tilt;
        is_flip                = false;

        if abs(ideal_pan) > 90
            [adj_pan, adj_tilt, is_flip, ~] = applyFlipLogic(ideal_pan, ideal_tilt);
            adj_tilt = max(-85, min(85, adj_tilt));
            override_target_pan   = adj_pan;
            override_target_tilt  = adj_tilt;
            use_ephemeris_override = true;
        end

        %% STEP 4 — FSM
        [ErrorSignal, FSM_State, ~, ~] = StateManagerFSM_copy( ...
            LDR_V, S_body_n, theta_p_curr, theta_t_curr, ...
            FSM_State, SupervisorParams, dt_outer, is_flip);

        fsm_active = ismember(FSM_State.mode, {'TRACKING','SEARCH','PARK'});
        if ~fsm_active
            ErrorSignal.pan  = 0;
            ErrorSignal.tilt = 0;
        end

        %% STEP 5 — Integrator reset on override exit
        if ~use_ephemeris_override && was_in_override
            ControlState.I_pan  = 0;
            ControlState.I_tilt = 0;
        end

        I_pan_accum  = 0;
        I_tilt_accum = 0;

        %% STEP 5 — Inner PID loop
        for s = 1:N_sub
            [VelCmd, ControlState, ~, ~] = PID_VelocityController( ...
                ErrorSignal, ControlState, struct(), dt_inner);

            if fsm_active
                v_pan_actual  = VelCmd.v_pan;
                v_tilt_actual = VelCmd.v_tilt;
            else
                v_pan_actual  = 0;
                v_tilt_actual = 0;
            end

            theta_pan_curr  = StatePan.Angle;
            theta_tilt_curr = StateTilt.Angle;

            if use_ephemeris_override
                tgt_pan  = max(-90, min(90, override_target_pan));
                tgt_tilt = max(-90, min(90, override_target_tilt));
            else
                tgt_pan  = max(-90, min(90, theta_pan_curr  + v_pan_actual  * dt_inner));
                tgt_tilt = max(-90, min(90, theta_tilt_curr + v_tilt_actual * dt_inner));
            end

            smooth_a = 0.50;
            if fsm_active
                CommandSmoothing.target_pan_smoothed  = ...
                    (1-smooth_a)*CommandSmoothing.target_pan_smoothed  + smooth_a*tgt_pan;
                CommandSmoothing.target_tilt_smoothed = ...
                    (1-smooth_a)*CommandSmoothing.target_tilt_smoothed + smooth_a*tgt_tilt;
            else
                CommandSmoothing.target_pan_smoothed  = theta_pan_curr;
                CommandSmoothing.target_tilt_smoothed = theta_tilt_curr;
            end

            [StatePan,  ~, ~] = stepTheoreticalServo(StatePan,  ...
                CommandSmoothing.target_pan_smoothed,  dt_inner, 'Pan');
            [StateTilt, ~, ~] = stepTheoreticalServo(StateTilt, ...
                CommandSmoothing.target_tilt_smoothed, dt_inner, 'Tilt');

            I_pan_accum  = I_pan_accum  + StatePan.Current;
            I_tilt_accum = I_tilt_accum + StateTilt.Current;
        end

        %% POST-LOOP — Update FSM alignment state
        cp_post  = cosd(StatePan.Angle);  sp_post = sind(StatePan.Angle);
        ct_post  = cosd(StateTilt.Angle); st_post = sind(StateTilt.Angle);
        Sx_post  = cp_post*S_vec(1) - sp_post*S_vec(2);
        Sy_post  = sp_post*S_vec(1) + cp_post*S_vec(2);
        S_post   = [Sx_post; ct_post*Sy_post - st_post*S_vec(3); ...
                             st_post*Sy_post + ct_post*S_vec(3)];
        S_post_n = S_post / (norm(S_post) + 1e-8);
        FSM_State.e_total_prev = acosd(max(-1.0, min(1.0, S_post_n(3))));
        was_in_override = use_ephemeris_override;

        %% STEP 6 — Tracker panel power (POA irradiance) WITH temperature
        theta_pan_f  = StatePan.Angle;
        theta_tilt_f = StateTilt.Angle;

        cp2 = cosd(theta_pan_f); sp2 = sind(theta_pan_f);
        ct2 = cosd(theta_tilt_f); st2 = sind(theta_tilt_f);
        Sx2 = cp2*S_vec(1) - sp2*S_vec(2);
        Sy2 = sp2*S_vec(1) + cp2*S_vec(2);
        S_body_final   = [Sx2; ct2*Sy2 - st2*S_vec(3); st2*Sy2 + ct2*S_vec(3)];
        S_body_final_n = S_body_final / (norm(S_body_final) + 1e-8);

        zenith = 90 - sun_elev;
        if zenith < 88.0 && sun_elev >= 5.0
            DNI = beam_now / max(cosd(zenith), 0.174);
            DNI = min(DNI, 1200);
        else
            DNI = 0;
        end

        cos_t         = max(0, S_body_final_n(3));
        G_POA_tracker = (DNI * cos_t) + (dhi_now * (1 + cosd(theta_tilt_f)) / 2);

        % Temperature correction for tracker (uses tracker POA irradiance)
        T_cell_trk = T_amb + G_POA_tracker / (U0 + U1*WS);
        T_cell_trk = max(T_amb, T_cell_trk);
        eta_trk    = ETA_STC * (1 + gamma_P * (T_cell_trk - T_STC));
        eta_trk    = max(0.01, eta_trk);

        P_tracker_gross(i) = G_POA_tracker * PANEL_AREA * eta_trk;

        cos_theta_log(i)  = cos_t;
        theta_tilt_log(i) = theta_tilt_f;
        T_cell_trk_log(i) = T_cell_trk;
        eta_trk_log(i)    = eta_trk;

        %% STEP 7 — Parasitic motor power
        is_hold = ismember(FSM_State.mode, {'HOLD','IDLE'});
        if is_hold || ~fsm_active
            I_motor = 0;
        else
            I_motor = (I_pan_accum + I_tilt_accum) / N_sub;
        end
        P_parasitic(i)   = I_motor * V_SUPPLY;
        P_tracker_net(i) = P_tracker_gross(i) - P_parasitic(i);
        FSM_log{i}       = FSM_State.mode;

    end % outer loop
    elapsed = toc;
    fprintf('  Done in %.1f s\n', elapsed);

    n_track = sum(strcmp(FSM_log,'TRACKING'));
    n_hold  = sum(strcmp(FSM_log,'HOLD'));
    n_srch  = sum(strcmp(FSM_log,'SEARCH'));
    n_idle  = sum(strcmp(FSM_log,'IDLE'));

    fprintf('  FSM: TRACKING=%ds | HOLD=%ds | SEARCH=%ds | IDLE=%ds\n', ...
            n_track, n_hold, n_srch, n_idle);

    %% Energy integrals
    E_fixed  = trapz(time_vec, P_fixed)               / 3600;
    E_gross  = trapz(time_vec, P_tracker_gross)        / 3600;
    E_para   = trapz(time_vec, P_parasitic)            / 3600;
    E_net    = trapz(time_vec, max(0, P_tracker_net))  / 3600;
    Para_r   = 100 * E_para  / (E_gross + 1e-9);
    Net_gain = 100 * (E_net - E_fixed) / (E_fixed + 1e-9);

    % Temperature statistics (daytime only)
    idx_day    = (G_log > 10);
    T_cell_fix_mean = mean(T_cell_fix_log(idx_day));
    T_cell_trk_mean = mean(T_cell_trk_log(idx_day));
    eta_fix_mean    = mean(eta_fix_log(idx_day));
    eta_trk_mean    = mean(eta_trk_log(idx_day));
    T_amb_mean      = mean(T_amb_vec(idx_day));

    fprintf('  E_fixed=%.2fWh | E_gross=%.2fWh | E_para=%.2fWh | E_net=%.2fWh\n', ...
            E_fixed, E_gross, E_para, E_net);
    fprintf('  Net Gain=%+.2f%%  |  Parasitic=%.2f%%\n', Net_gain, Para_r);
    fprintf('  T_amb=%.1f°C | T_cell_fix=%.1f°C | T_cell_trk=%.1f°C\n', ...
            T_amb_mean, T_cell_fix_mean, T_cell_trk_mean);
    fprintf('  η_fix=%.4f | η_trk=%.4f  (STC: %.4f)\n\n', ...
            eta_fix_mean, eta_trk_mean, ETA_STC);

    %% cos(theta) gain bands
    idx_cos095 = cos_theta_log >= 0.95;
    idx_cos090 = cos_theta_log >= 0.90;
    idx_cos080 = cos_theta_log >= 0.80;
    Gain_095 = 0; Gain_090 = 0; Gain_080 = 0;
    if sum(idx_cos095)>0
        Gain_095 = 100*(trapz(time_vec(idx_cos095),max(0,P_tracker_net(idx_cos095))) - ...
                        trapz(time_vec(idx_cos095),P_fixed(idx_cos095))) / ...
                       (trapz(time_vec(idx_cos095),P_fixed(idx_cos095))+1e-9);
    end
    if sum(idx_cos090)>0
        Gain_090 = 100*(trapz(time_vec(idx_cos090),max(0,P_tracker_net(idx_cos090))) - ...
                        trapz(time_vec(idx_cos090),P_fixed(idx_cos090))) / ...
                       (trapz(time_vec(idx_cos090),P_fixed(idx_cos090))+1e-9);
    end
    if sum(idx_cos080)>0
        Gain_080 = 100*(trapz(time_vec(idx_cos080),max(0,P_tracker_net(idx_cos080))) - ...
                        trapz(time_vec(idx_cos080),P_fixed(idx_cos080))) / ...
                       (trapz(time_vec(idx_cos080),P_fixed(idx_cos080))+1e-9);
    end

    %% Store Results
    Results(d).label          = season_names{d};
    Results(d).month_length   = month_lengths(d);
    Results(d).E_fixed        = E_fixed;
    Results(d).E_gross        = E_gross;
    Results(d).E_para         = E_para;
    Results(d).E_net          = E_net;
    Results(d).Para_r         = Para_r;
    Results(d).Net_gain       = Net_gain;
    Results(d).n_track        = n_track;
    Results(d).n_hold         = n_hold;
    Results(d).n_srch         = n_srch;
    Results(d).n_idle         = n_idle;
    Results(d).cos_theta_log  = cos_theta_log;
    Results(d).theta_tilt_log = theta_tilt_log;
    Results(d).Gain_095       = Gain_095;
    Results(d).Gain_090       = Gain_090;
    Results(d).Gain_080       = Gain_080;
    % Temperature additions
    Results(d).T_amb_mean      = T_amb_mean;
    Results(d).T_cell_fix_mean = T_cell_fix_mean;
    Results(d).T_cell_trk_mean = T_cell_trk_mean;
    Results(d).eta_fix_mean    = eta_fix_mean;
    Results(d).eta_trk_mean    = eta_trk_mean;

    AllData{d}.time_vec        = time_vec;
    AllData{d}.t_start_s       = t_start_s;
    AllData{d}.P_fixed         = P_fixed;
    AllData{d}.P_tracker_gross = P_tracker_gross;
    AllData{d}.P_tracker_net   = P_tracker_net;
    AllData{d}.P_parasitic     = P_parasitic;
    AllData{d}.G_log           = G_log;
    AllData{d}.FSM_log         = FSM_log;
    AllData{d}.cos_theta_log   = cos_theta_log;
    AllData{d}.theta_tilt_log  = theta_tilt_log;
    % Temperature logs saved in AllData
    AllData{d}.T_amb           = T_amb_vec;
    AllData{d}.T_cell_fix      = T_cell_fix_log;
    AllData{d}.T_cell_trk      = T_cell_trk_log;
    AllData{d}.eta_fix         = eta_fix_log;
    AllData{d}.eta_trk         = eta_trk_log;

    %% ── SAVE DETAILED TIMESTEP CSV (includes temperature) ───────────────
    csv_detail_file = fullfile(res_dir, ...
        sprintf('DetailedTimestep_%s_Month%02d_Daily.csv', loc_name, d));
    T_detail = table( ...
        time_vec, ...
        month_data.Sun_Elevation, month_data.Sun_Azimuth, ...
        month_data.GHI, month_data.Beam, month_data.DHI, ...
        T_amb_vec, T_cell_fix_log, T_cell_trk_log, ...
        eta_fix_log, eta_trk_log, ...
        cos_theta_log, theta_tilt_log, ...
        P_fixed, P_tracker_gross, P_parasitic, P_tracker_net, ...
        G_log, FSM_log, ...
        'VariableNames', { ...
            'Time_s', ...
            'Sun_Elev_deg', 'Sun_Az_deg', ...
            'GHI_W_m2', 'Beam_W_m2', 'DHI_W_m2', ...
            'T_amb_C', 'T_cell_fixed_C', 'T_cell_tracker_C', ...
            'eta_fixed', 'eta_tracker', ...
            'cos_theta', 'Tilt_deg', ...
            'P_fixed_W', 'P_tracker_gross_W', 'P_parasitic_W', 'P_tracker_net_W', ...
            'POA_irr_W_m2', 'FSM_State'});
    writetable(T_detail, csv_detail_file);
    fprintf('  ✓ Detailed CSV (with temp): %s\n', csv_detail_file);

end % month loop

%% ── ANNUAL ROLL-UP ───────────────────────────────────────────────────────
E_fixed_yr = 0; E_gross_yr = 0; E_para_yr = 0; E_net_yr = 0;
n_track_yr = 0; n_hold_yr  = 0; n_idle_yr = 0;
T_amb_yr = 0; T_fix_yr = 0; T_trk_yr = 0;
for d = 1:nDays
    w = month_lengths(d);
    E_fixed_yr = E_fixed_yr + Results(d).E_fixed  * w;
    E_gross_yr = E_gross_yr + Results(d).E_gross  * w;
    E_para_yr  = E_para_yr  + Results(d).E_para   * w;
    E_net_yr   = E_net_yr   + Results(d).E_net    * w;
    n_track_yr = n_track_yr + Results(d).n_track  * w;
    n_hold_yr  = n_hold_yr  + Results(d).n_hold   * w;
    n_idle_yr  = n_idle_yr  + Results(d).n_idle   * w;
    T_amb_yr   = T_amb_yr   + Results(d).T_amb_mean      * w;
    T_fix_yr   = T_fix_yr   + Results(d).T_cell_fix_mean * w;
    T_trk_yr   = T_trk_yr   + Results(d).T_cell_trk_mean * w;
end
T_amb_yr = T_amb_yr / sum(month_lengths);
T_fix_yr = T_fix_yr / sum(month_lengths);
T_trk_yr = T_trk_yr / sum(month_lengths);
Para_yr  = 100 * E_para_yr / (E_gross_yr + 1e-9);
Gain_yr  = 100 * (E_net_yr  - E_fixed_yr) / (E_fixed_yr + 1e-9);

fprintf('════════════════════════════════════════════════════════════════\n');
fprintf('  ANNUAL YIELD SUMMARY (DAILY DATA WITH TEMPERATURE) — %s\n', Geo.Name);
fprintf('════════════════════════════════════════════════════════════════\n');
fprintf('  E_fixed = %8.1f Wh/yr = %6.2f kWh/yr\n',  E_fixed_yr, E_fixed_yr/1000);
fprintf('  E_gross = %8.1f Wh/yr = %6.2f kWh/yr\n',  E_gross_yr, E_gross_yr/1000);
fprintf('  E_para  = %8.1f Wh/yr = %6.3f kWh/yr\n',  E_para_yr,  E_para_yr/1000);
fprintf('  E_net   = %8.1f Wh/yr = %6.2f kWh/yr\n',  E_net_yr,   E_net_yr/1000);
fprintf('  Net Gain      : %+.2f %%\n', Gain_yr);
fprintf('  Parasitic     : %.2f %%\n',  Para_yr);
fprintf('  Avg T_amb     : %.1f °C\n',  T_amb_yr);
fprintf('  Avg T_cell (fixed)   : %.1f °C\n', T_fix_yr);
fprintf('  Avg T_cell (tracker) : %.1f °C\n', T_trk_yr);
fprintf('════════════════════════════════════════════════════════════════\n\n');

fprintf('  MONTHLY BREAKDOWN:\n');
fprintf('  %-5s | %9s | %8s | %7s | %6s | %8s | %8s | %7s\n', ...
    'Month','E_Net(Wh)','Gain(%)','Para(%)','T_amb','T_fix','T_trk','η_fix');
fprintf('  %s\n', repmat('-',1,75));
for d = 1:nDays
    fprintf('  %-5s | %9.1f | %+8.2f | %7.2f | %6.1f | %8.1f | %8.1f | %7.4f\n', ...
        season_names{d}, Results(d).E_net, Results(d).Net_gain, Results(d).Para_r, ...
        Results(d).T_amb_mean, Results(d).T_cell_fix_mean, Results(d).T_cell_trk_mean, ...
        Results(d).eta_fix_mean);
end
fprintf('  %s\n\n', repmat('-',1,75));

%% ── SAVE RESULTS .mat ────────────────────────────────────────────────────
mat_file = fullfile(res_dir, sprintf('%s_Results_Daily.mat', upper(loc_name)));
save(mat_file, 'Results', 'AllData', 'Geo', 'Gain_yr', 'Para_yr', ...
               'T_amb_yr', 'T_fix_yr', 'T_trk_yr', 'PreparedData');
fprintf('  ✓ Results saved: %s\n\n', mat_file);

%% ── FIGURES ─────────────────────────────────────────────────────────────
fprintf('Generating figures...\n');

FN  = 'Times New Roman';
FSs = 9; FSr = 11; FSl = 12; FSt = 13;
C_fix   = [0.13 0.29 0.53];
C_net   = [0.93 0.69 0.13];
C_para  = [0.75 0.15 0.15];
C_temp  = [0.85 0.33 0.10];
C_trk   = [0.22 0.56 0.24];
mon_labels = {Results.label};

%% FIG T1 — Monthly Cell Temperature (fixed vs tracker) ───────────────────
figT1 = figure('Color','w','NumberTitle','off','Visible','off');
figT1.Position = [50 50 1400 560];
axT1 = axes(figT1);
set(axT1,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45, ...
    'XTick',1:12,'XTickLabel',mon_labels,'TickDir','out');
hold(axT1,'on');

T_amb_v   = [Results.T_amb_mean];
T_fix_v   = [Results.T_cell_fix_mean];
T_trk_v   = [Results.T_cell_trk_mean];

plot(axT1, 1:12, T_amb_v,  '-o','Color',[0.4 0.4 0.8],'LineWidth',2.0,'MarkerSize',7,'DisplayName','T_{amb}');
plot(axT1, 1:12, T_fix_v,  '-s','Color',C_fix,        'LineWidth',2.0,'MarkerSize',7,'DisplayName','T_{cell} fixed');
plot(axT1, 1:12, T_trk_v,  '-^','Color',C_temp,       'LineWidth',2.0,'MarkerSize',7,'DisplayName','T_{cell} tracker');
yline(axT1, T_STC, '--k','LineWidth',1.2,'Label','STC 25°C');

ylabel(axT1,'Temperature (°C)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(axT1,'Month',            'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(axT1, sprintf('Monthly Average Cell Temperature — %s, TR (Daily Data + Interp)', Geo.Name), ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(axT1,'Location','northwest','FontName',FN,'FontSize',FSr,'Box','on');
exportgraphics(figT1, fullfile(res_dir,'FigT1_CellTemperature_Daily.png'), 'Resolution',300);
close(figT1);
fprintf('  ✓ FigT1_CellTemperature_Daily.png\n');

%% FIG T2 — Monthly Efficiency (fixed vs tracker) ────────────────────────
figT2 = figure('Color','w','NumberTitle','off','Visible','off');
figT2.Position = [50 50 1400 560];
axT2 = axes(figT2);
set(axT2,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45, ...
    'XTick',1:12,'XTickLabel',mon_labels,'TickDir','out');
hold(axT2,'on');

eta_fix_v = [Results.eta_fix_mean] * 100;
eta_trk_v = [Results.eta_trk_mean] * 100;

plot(axT2, 1:12, eta_fix_v, '-s','Color',C_fix, 'LineWidth',2.0,'MarkerSize',7,'DisplayName','\eta fixed');
plot(axT2, 1:12, eta_trk_v, '-^','Color',C_temp,'LineWidth',2.0,'MarkerSize',7,'DisplayName','\eta tracker');
yline(axT2, ETA_STC*100,'--k','LineWidth',1.2,'Label','STC efficiency');

for d = 1:12
    diff_eta = eta_trk_v(d) - eta_fix_v(d);
    if abs(diff_eta) > 0.01
        text(axT2, d, (eta_fix_v(d)+eta_trk_v(d))/2, sprintf('%+.2f%%', diff_eta), ...
            'HorizontalAlignment','center','FontSize',FSs,'FontName',FN,...
            'Color',C_temp);
    end
end

ylabel(axT2,'Panel Efficiency (%)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(axT2,'Month',               'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(axT2, sprintf('Monthly Temperature-Corrected Panel Efficiency — %s, TR (Daily)', Geo.Name), ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(axT2,'Location','best','FontName',FN,'FontSize',FSr,'Box','on');
exportgraphics(figT2, fullfile(res_dir,'FigT2_PanelEfficiency_Daily.png'), 'Resolution',300);
close(figT2);
fprintf('  ✓ FigT2_PanelEfficiency_Daily.png\n');

%% FIG T3 — Net Gain comparison ─────────────────────────────────────────
figT3 = figure('Color','w','NumberTitle','off','Visible','off');
figT3.Position = [50 50 1400 560];
axT3 = axes(figT3);
set(axT3,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45, ...
    'XTick',1:12,'XTickLabel',mon_labels,'TickDir','out');
hold(axT3,'on');

gains_v = [Results.Net_gain];
bT3 = bar(axT3, gains_v, 0.65, 'FaceAlpha',0.85,'EdgeColor','none');
bT3.FaceColor = 'flat';
nrm = (gains_v - min(gains_v))./(max(gains_v)-min(gains_v)+1e-9);
for d = 1:12
    bT3.CData(d,:) = (1-nrm(d))*C_fix + nrm(d)*C_net;
end
for d = 1:12
    text(axT3, d, gains_v(d)+max(gains_v)*0.025, sprintf('%+.1f%%', gains_v(d)), ...
        'HorizontalAlignment','center','FontSize',FSs,'FontName',FN,'FontWeight','bold');
end

annotation(figT3,'textbox',[0.72 0.70 0.20 0.18], ...
    'String', sprintf('Annual Net Gain\n%+.2f%%\n\nAvg T_{cell}(fix)\n%.1f°C\n\nAvg T_{cell}(trk)\n%.1f°C', ...
                      Gain_yr, T_fix_yr, T_trk_yr), ...
    'FontName',FN,'FontSize',FSr,'HorizontalAlignment','center', ...
    'EdgeColor',[0.7 0.7 0.7],'LineWidth',1,'BackgroundColor',[1 1 0.95]);

ylabel(axT3,'Net Efficiency Gain (%)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(axT3,'Month',                  'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(axT3, sprintf('Monthly Net Gain with Cell Temperature Correction — %s, TR (Daily)', Geo.Name), ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
exportgraphics(figT3, fullfile(res_dir,'FigT3_NetGain_Daily.png'), 'Resolution',300);
close(figT3);
fprintf('  ✓ FigT3_NetGain_Daily.png\n');

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  CompareYield_Hourly COMPLETE                                ║\n');
fprintf('║  Data Source: %s\n', data_source);
fprintf('║  Results in: %s\n', res_dir);
fprintf('║  ✓ DetailedTimestep_*_Hourly.csv (per-second + temp)        ║\n');
fprintf('║  ✓ %s_Results_Hourly.mat                                     ║\n', upper(loc_name));
fprintf('║  ✓ Figures (3× PNG @ 300 dpi)                                ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');