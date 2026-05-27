%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  CompareYield_Direct.m                                               ║
%% ║                                                                      ║
%% ║  Fixed vs. Dual-Axis Tracker — Direct PVGIS TMY loading              ║
%% ║                                                                      ║
%% ║  DATA PIPELINE (replaces pre-baked _Data.csv approach):              ║
%% ║    1. Loads CITY_TMY.csv once via loadPVGIS()                        ║
%% ║    2. For each of 12 Klein representative days:                      ║
%% ║         a. filterPVGISbyDate() → 24 hourly rows                     ║
%% ║         b. Linear interp → 86 400 s vectors for GHI, Beam, DHI,     ║
%% ║                             T2m, WS10m                               ║
%% ║         c. Sun geometry (elevation, azimuth) computed from Klein     ║
%% ║            Julian day n via vectorised solar position equations      ║
%% ║            (Option A — consistent with paper methodology)            ║
%% ║    3. Faiman cell-temperature model at every second                  ║
%% ║    4. Net energy yield with parasitic subtraction                    ║
%% ║                                                                      ║
%% ║  DEPENDENCIES:  loadPVGIS, filterPVGISbyDate, getGeoConfig,          ║
%% ║                 StateManagerFSM, PID_VelocityController,             ║
%% ║                 stepTheoreticalServo, readLDRs, applyFlipLogic        ║
%% ║                                                                      ║
%% ║  NO LONGER NEEDED:  CITY_Data.csv, CITY_MonthlyAvg.csv               ║
%% ╚══════════════════════════════════════════════════════════════════════╝

if ~exist('BATCH_MODE','var')
    clear; clc; close all;
else
    clc; close all;
end
% Set script directory as working directory
script_dir = fileparts(mfilename('fullpath'));
cd(script_dir);
addpath(genpath(pwd));

set(groot,'defaultTextInterpreter',              'tex');
set(groot,'defaultAxesTickLabelInterpreter',     'tex');
set(groot,'defaultLegendInterpreter',            'tex');
set(groot,'defaultColorbarTickLabelInterpreter', 'tex');

%% ── Output directory ─────────────────────────────────────────────────────
if exist('BATCH_MODE','var') && BATCH_MODE && exist('loc_name','var')
    res_dir = fullfile('Results', upper(loc_name));
else
    res_dir = 'Results';
end
if ~isfolder(res_dir), mkdir(res_dir); end

%% ── Location ─────────────────────────────────────────────────────────────
if ~exist('loc_name','var'), loc_name = 'ISTANBUL'; end
try
    Geo = getGeoConfig_month(loc_name);
catch
    % Construct folder with proper casing: first letter uppercase, rest lowercase
    loc_folder = [upper(loc_name(1)), lower(loc_name(2:end))];
    Geo.Name       = loc_name;
    Geo.Lat        = 41.05;
    Geo.Lon        = 29.01;
    Geo.TZ         = 3;
    Geo.PVGIS_File = fullfile('DATA', loc_folder, sprintf('%s_HOURLY_12dates.csv', upper(loc_name)));
end

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║    FIXED vs TRACKER — DIRECT PVGIS TMY | OPTION-A SUN GEO   ║\n');
fprintf('║  %s | Faiman Temperature Model | 12 Klein Days       ║\n', Geo.Name);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

%% ── Control / physics flags ──────────────────────────────────────────────
CONTROL_MODE  = 'pid';
PHYSICS_MODEL = 'THEORETICAL';

dt_outer = 1.00;
dt_inner = 0.01;
N_sub    = round(dt_outer / dt_inner);  % 100 sub-steps per outer step

fprintf('CONTROL_MODE  : %s\n',   upper(CONTROL_MODE));
fprintf('PHYSICS_MODEL : %s  + Faiman Cell-Temperature Model\n', PHYSICS_MODEL);
fprintf('dt_outer      : %.2f s\n', dt_outer);
fprintf('dt_inner      : %.2f s  (%d sub-steps per outer step)\n\n', dt_inner, N_sub);

%% ── Calendar constants ───────────────────────────────────────────────────
season_names  = {'Jan','Feb','Mar','Apr','May','Jun', ...
                 'Jul','Aug','Sep','Oct','Nov','Dec'};
month_lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
nDays         = 12;

% Klein (1977) / Duffie–Beckman representative Julian days (one per month)
klein_days = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];

%% ── Panel parameters ─────────────────────────────────────────────────────
PANEL_AREA = 0.04;    % [m²]   four 10×10 cm petals
ETA_STC    = 0.20;    % [-]    STC efficiency

% Faiman / IEC 61853-2 cell-temperature model
U0      = 25.0;    % [W m⁻² K⁻¹]       free-convection coefficient
U1      =  6.84;   % [W m⁻² K⁻¹/(m/s)] wind-dependent coefficient
T_STC   = 25.0;    % [°C]               STC reference temperature
gamma_P = -0.004;  % [1/°C]             power temperature coefficient (c-Si)

%% ── FSM / supervisor parameters ──────────────────────────────────────────
SupervisorParams = struct();
SupervisorParams.night_threshold     = 0.10;
SupervisorParams.sun_lost_threshold  = 0.15;
SupervisorParams.sun_found_threshold = 0.30;
SupervisorParams.lock_threshold      = 1.5;
SupervisorParams.tracking_deadband   = 3.0;
SupervisorParams.batch_interval      = 300.0;
SupervisorParams.max_burst_time      = 2.0;
SupervisorParams.search_speed        = 3.0;
SupervisorParams.zenith_pan_lock     = false;
SupervisorParams.tau_derivative      = 2.0;

V_SUPPLY = 6.0;  % [V] servo supply voltage

%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  FAST-PATH — Pre-built CSV (generated by prepare_solar_data_v2)     ║
%% ║                                                                      ║
%% ║  Set USE_PREBUILT_CSV = true to skip loadPVGIS / filterPVGISbyDate  ║
%% ║  and the per-month interp+sun-geometry block entirely.               ║
%% ║  Run prepare_solar_data_v2(loc_name) once to generate the file.     ║
%% ╚══════════════════════════════════════════════════════════════════════╝
if ~exist('USE_PREBUILT_CSV','var'), USE_PREBUILT_CSV = false; end

prebuilt_csv  = sprintf('%s_Data_v2.csv', upper(loc_name));
PreData       = [];   % populated below if fast-path is active

% Try prebuilt format first; if not found, check for Klein 12-day format
if ~isfile(prebuilt_csv)
    klein_12day_csv = fullfile('DATA', [upper(loc_name(1)) lower(loc_name(2:end))], sprintf('%s_HOURLY_12dates.csv', upper(loc_name)));
    if isfile(klein_12day_csv)
        prebuilt_csv = klein_12day_csv;
        USE_PREBUILT_CSV = true;  % Auto-enable if Klein data is found
    end
end

if USE_PREBUILT_CSV && isfile(prebuilt_csv)
    fprintf('  Fast-path    : loading pre-built CSV  %s ... ', prebuilt_csv);
    PreData = readtable(prebuilt_csv);
    fprintf('✓  %d rows\n\n', height(PreData));
elseif USE_PREBUILT_CSV
    warning('USE_PREBUILT_CSV=true but file not found: %s\n  Falling back to live TMY path.', prebuilt_csv);
    USE_PREBUILT_CSV = false;
end

%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  STEP 0 — LOAD PVGIS TMY FILE (once, before the month loop)         ║
%% ╚══════════════════════════════════════════════════════════════════════╝
%
%  loadPVGIS() expects the PVGIS 5.3 / SARAH3 export format:
%    8 metadata lines, then header, then data rows:
%    20230101:0010, Gb(i), Gd(i), Gr(i), H_sun, T2m, WS10m, Int
%
%  Each hourly row is timestamped at HH:10 (PVGIS convention).
%  For horizontal panel (slope=0): GHI = Gb + Gd,  Beam_h = Gb,  DHI = Gd
%  Gr ≈ 0 for a horizontal surface (no tilted face to receive ground refl.)

if ~USE_PREBUILT_CSV
    pvgis_file = Geo.PVGIS_File;
    if ~isfile(pvgis_file)
        error('[CompareYield_Direct] PVGIS TMY file not found: %s', pvgis_file);
    end
    fprintf('Loading PVGIS TMY: %s ... ', pvgis_file);
    TMY = loadPVGIS(pvgis_file);
    fprintf('✓  %d hourly records\n', numel(TMY.time));
    pvgis_year = year(TMY.time(1));
else
    TMY = [];  pvgis_year = 2023;
end
fprintf('Location : %s\n', Geo.Name);
fprintf('Coords   : %.3f°N  %.3f°E  UTC%+d\n\n', Geo.Lat, Geo.Lon, Geo.TZ);

%% ── Pre-allocate results ─────────────────────────────────────────────────
Results = struct();
AllData = cell(nDays, 1);

%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  MAIN LOOP — 12 Klein representative days                           ║
%% ╚══════════════════════════════════════════════════════════════════════╝

for d = 1:nDays

    n_julian = klein_days(d);

    fprintf('══════════════════════════════════════════════════════════\n');
    fprintf('  Month %2d/12 : %s  (Klein Julian n=%d)\n', d, season_names{d}, n_julian);
    fprintf('══════════════════════════════════════════════════════════\n');

    %% ── STEPS A–B: Irradiance + met vectors for this month ──────────────
    N     = 86400;
    t_sec = (0 : N-1)';

    if USE_PREBUILT_CSV
        %% Fast-path — read from pre-built v2 CSV (1-second, all channels)
        rows = PreData(PreData.Month == d, :);
        if height(rows) < N
            warning('Pre-built CSV: only %d rows for month %d. Skipping.', height(rows), d);
            continue;
        end
        GHI_sec   = rows.GHI(1:N);
        Beam_sec  = rows.Beam(1:N);
        DHI_sec   = rows.DHI(1:N);
        T2m_sec   = rows.T2m(1:N);
        WS_sec    = max(0.5, rows.WS10m(1:N));
        alpha_vec = rows.Sun_Elevation(1:N);   % pre-computed Option-A geometry
        phi_vec   = rows.Sun_Azimuth(1:N);
        rep_date  = datetime(pvgis_year, 1, 1) + days(n_julian - 1);
        fprintf('  Fast-path   : %d rows from pre-built CSV\n', N);

    else
        %% Live-path — extract 24 PVGIS hourly rows and interpolate
        rep_date = datetime(pvgis_year, 1, 1) + days(n_julian - 1);
        try
            [Day24, DayStats] = filterPVGISbyDate(TMY, 'DAILY', rep_date);
        catch ME
            warning('  filterPVGISbyDate failed: %s  — skipping.', ME.message);
            continue;
        end
        if numel(Day24.time) < 24
            warning('  Only %d hourly rows for %s. Skipping.', numel(Day24.time), datestr(rep_date));
            continue;
        end
        fprintf('  PVGIS date  : %s  (%d rows)\n', char(rep_date,'dd-MMM-yyyy'), numel(Day24.time));
        fprintf('  Peak GHI    : %.1f W/m2  |  Insolation: %.1f Wh/m2\n', ...
                DayStats.peak_irradiance, DayStats.daily_insolation);
        t_anchor = seconds(Day24.time - dateshift(Day24.time(1), 'start', 'day'));
        GHI_sec  = max(0, interp1(t_anchor, Day24.Gb + Day24.Gd, t_sec, 'linear', 'extrap'));
        Beam_sec = max(0, interp1(t_anchor, Day24.Gb,             t_sec, 'linear', 'extrap'));
        DHI_sec  = max(0, interp1(t_anchor, Day24.Gd,             t_sec, 'linear', 'extrap'));
        T2m_sec  = interp1(t_anchor, Day24.T2m,   t_sec, 'linear', 'extrap');
        WS_sec   = max(0.5, interp1(t_anchor, Day24.WS10m, t_sec, 'linear', 'extrap'));
    end

    if ~USE_PREBUILT_CSV
        %% ── STEP C: Vectorised sun geometry (Option A — Klein Julian day) ────
        %
        %  Sun position is computed entirely from the Klein Julian day n,
        %  NOT from the PVGIS H_sun column.  This keeps the methodology
        %  consistent with Duffie–Beckman representative-day theory.
        %
        %  Equations reproduce getSunVector.m vectorially over 86 400 seconds:
        %    delta  = solar declination (Spencer 1971)
        %    EoT    = equation of time
        %    LST    = local solar time
        %    omega  = hour angle
        %    alpha  = elevation angle
        %    phi    = azimuth (0° = North, clockwise)
    
        lat_r  = deg2rad(Geo.Lat);
        lon_d  = Geo.Lon;
        tz_h   = Geo.TZ;
    
        % Declination (Spencer 1971, ±0.035° accuracy)
        delta_r = asin(sin(deg2rad(23.45)) * sin(deg2rad(360/365 * (n_julian - 81))));
    
        % Equation of time [minutes]
        B_r = deg2rad(360/364 * (n_julian - 81));
        EoT = 9.87*sin(2*B_r) - 7.53*cos(B_r) - 1.5*sin(B_r);
    
        % Time correction [hours] — same for all seconds of this day
        TC_h = (4*(lon_d - 15*tz_h) + EoT) / 60;
    
        % Local standard time → local solar time [hours] for each second
        t_h_vec = t_sec / 3600;            % [N×1] hours from midnight (LST)
        LST_vec = t_h_vec + TC_h;          % [N×1] local solar time [h]
    
        % Hour angle [rad]
        omega_vec = deg2rad(15 * (LST_vec - 12));
    
        % Solar elevation [rad]  →  [deg]
        sin_alpha = sin(lat_r)*sin(delta_r) + ...
                    cos(lat_r)*cos(delta_r)*cos(omega_vec);
        sin_alpha = max(-1, min(1, sin_alpha));
        alpha_vec = rad2deg(asin(sin_alpha));          % elevation [deg]
    
        % Solar azimuth [rad, measured from North clockwise] → [deg]
        az_rad_vec = atan2(-sin(omega_vec).*cos(delta_r), ...
                            cos(lat_r)*sin(delta_r) - ...
                            sin(lat_r)*cos(delta_r).*cos(omega_vec));
        phi_vec = mod(rad2deg(az_rad_vec), 360);       % azimuth [deg], 0=N CW
        
        delta_deg_val = rad2deg(delta_r);

    else
        % Fast-path: sun geometry already in CSV, compute delta from Klein day
        delta_r = asin(sin(deg2rad(23.45)) * sin(deg2rad(360/365 * (n_julian - 81))));
        delta_deg_val = rad2deg(delta_r);
    end

    % Night gate: elevation ≤ 0 → zero irradiance (overrides interpolation)
    night_mask = (alpha_vec <= 0);
    GHI_sec(night_mask)  = 0;
    Beam_sec(night_mask) = 0;
    DHI_sec(night_mask)  = 0;

    G_peak        = max(GHI_sec);
    daylight_h    = sum(~night_mask) / 3600;

    fprintf('  Klein delta : %+.2f°  |  G_peak: %.1f W/m²  |  Daylight: %.1f h\n', ...
            delta_deg_val, G_peak, daylight_h);

    %% ── Initialise servo angles from first lit second ─────────────────────
    first_lit = find(~night_mask & GHI_sec >= 10, 1, 'first');
    if ~isempty(first_lit)
        init_el  = alpha_vec(first_lit);
        init_pan = phi_vec(first_lit);
        if init_pan > 180, init_pan = init_pan - 360; end
        init_pan  = max(-90, min(90,  init_pan));
        init_tilt = max(0,   min(85,  90 - init_el));
    else
        init_pan  = 0;
        init_tilt = 45;
    end

    StatePan  = struct('Angle', init_pan,  'Velocity', 0, 'Current', 0, 'Energy', 0);
    StateTilt = struct('Angle', init_tilt, 'Velocity', 0, 'Current', 0, 'Energy', 0);
    fprintf('  Init        : Pan=%.1f°  Tilt=%.1f°\n\n', init_pan, init_tilt);

    FSM_State = struct('mode','IDLE', ...
        'e_pan_prev',0, 'e_tilt_prev',0, ...
        'de_pan_filtered',0, 'de_tilt_filtered',0, ...
        'search_phase',0, 'hold_timer',0, 'burst_timer',0, ...
        'was_night',false, 'park_target_pan',0, 'park_target_tilt',90, ...
        'e_total_prev', 90);

    ControlState     = struct('I_pan',0,'I_tilt',0,'de_pan_filt',0,'de_tilt_filt',0);
    CommandSmoothing = struct('target_pan_smoothed',  init_pan, ...
                              'target_tilt_smoothed', init_tilt);

    %% ── Pre-allocate logs ────────────────────────────────────────────────
    P_fixed         = zeros(N,1);
    P_tracker_gross = zeros(N,1);
    P_parasitic     = zeros(N,1);
    P_tracker_net   = zeros(N,1);
    cos_theta_log   = zeros(N,1);
    theta_tilt_log  = zeros(N,1);
    T_cell_fix_log  = zeros(N,1);
    T_cell_trk_log  = zeros(N,1);
    eta_fix_log     = zeros(N,1);
    eta_trk_log     = zeros(N,1);
    FSM_log         = repmat({'IDLE'}, N, 1);

    was_in_override = false;

    %% ╔════════════════════════════════════════════════════════════════╗
    %% ║  INNER SIMULATION LOOP — 86 400 seconds                       ║
    %% ╚════════════════════════════════════════════════════════════════╝
    tic;
    for i = 1:N

        ghi_now  = GHI_sec(i);
        beam_now = Beam_sec(i);
        dhi_now  = DHI_sec(i);
        sun_elev = alpha_vec(i);
        sun_az   = phi_vec(i);
        T_amb    = T2m_sec(i);
        WS       = WS_sec(i);

        %% Night gate — skip computation, set logs to ambient
        if sun_elev <= 0 || ghi_now < 10
            FSM_log{i}        = 'IDLE';
            T_cell_fix_log(i) = T_amb;
            T_cell_trk_log(i) = T_amb;
            eta_fix_log(i)    = ETA_STC;
            eta_trk_log(i)    = ETA_STC;
            continue;
        end

        %% — Fixed panel power with Faiman temperature correction ──────────
        T_cell_fix = T_amb + ghi_now / (U0 + U1*WS);
        T_cell_fix = max(T_amb, T_cell_fix);
        eta_fix    = max(0.01, ETA_STC * (1 + gamma_P * (T_cell_fix - T_STC)));

        P_fixed(i)        = ghi_now * PANEL_AREA * eta_fix;
        T_cell_fix_log(i) = T_cell_fix;
        eta_fix_log(i)    = eta_fix;

        %% — Sun vector in ENU world frame ─────────────────────────────────
        el_r  = deg2rad(sun_elev);
        az_r  = deg2rad(sun_az);
        S_vec = [cos(el_r)*sin(az_r); cos(el_r)*cos(az_r); sin(el_r)];

        %% — Body-frame sun vector & LDR simulation ────────────────────────
        theta_p_curr = StatePan.Angle;
        theta_t_curr = StateTilt.Angle;

        cp = cosd(theta_p_curr); sp = sind(theta_p_curr);
        ct = cosd(theta_t_curr); st = sind(theta_t_curr);
        Sx = cp*S_vec(1) - sp*S_vec(2);
        Sy = sp*S_vec(1) + cp*S_vec(2);
        S_body   = [Sx; ct*Sy - st*S_vec(3); st*Sy + ct*S_vec(3)];
        S_body_n = S_body / (norm(S_body) + 1e-8);

        [~, LDR_V, ~, ~, ~, ~] = readLDRs(S_body_n);

        %% — Ephemeris target + conditional flip ───────────────────────────
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
            override_target_pan    = adj_pan;
            override_target_tilt   = adj_tilt;
            use_ephemeris_override = true;
        end

        %% — FSM ───────────────────────────────────────────────────────────
        [ErrorSignal, FSM_State, ~, ~] = StateManagerFSM( ...
            LDR_V, S_body_n, theta_p_curr, theta_t_curr, ...
            FSM_State, SupervisorParams, dt_outer, is_flip);

        fsm_active = ismember(FSM_State.mode, {'TRACKING','SEARCH','PARK'});
        if ~fsm_active
            ErrorSignal.pan  = 0;
            ErrorSignal.tilt = 0;
        end

        %% — Integrator reset on override exit ────────────────────────────
        if ~use_ephemeris_override && was_in_override
            ControlState.I_pan  = 0;
            ControlState.I_tilt = 0;
        end

        I_pan_accum  = 0;
        I_tilt_accum = 0;

        %% — Inner velocity-control loop ──────────────────────────────────
        for s = 1:N_sub
            [VelCmd, ControlState, ~, ~] = PID_VelocityController( ...
                ErrorSignal, ControlState, struct(), dt_inner);

            v_pan_actual  = fsm_active * VelCmd.v_pan;
            v_tilt_actual = fsm_active * VelCmd.v_tilt;

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

            [StatePan,  ~, ~] = stepTheoreticalServo(StatePan, ...
                CommandSmoothing.target_pan_smoothed,  dt_inner, 'Pan');
            [StateTilt, ~, ~] = stepTheoreticalServo(StateTilt, ...
                CommandSmoothing.target_tilt_smoothed, dt_inner, 'Tilt');

            I_pan_accum  = I_pan_accum  + StatePan.Current;
            I_tilt_accum = I_tilt_accum + StateTilt.Current;
        end

        %% — Post-loop: update FSM alignment state ─────────────────────────
        cp2 = cosd(StatePan.Angle); sp2 = sind(StatePan.Angle);
        ct2 = cosd(StateTilt.Angle); st2 = sind(StateTilt.Angle);
        Sx2 = cp2*S_vec(1) - sp2*S_vec(2);
        Sy2 = sp2*S_vec(1) + cp2*S_vec(2);
        S_post   = [Sx2; ct2*Sy2 - st2*S_vec(3); st2*Sy2 + ct2*S_vec(3)];
        S_post_n = S_post / (norm(S_post) + 1e-8);
        FSM_State.e_total_prev = acosd(max(-1, min(1, S_post_n(3))));
        was_in_override        = use_ephemeris_override;

        %% — Tracker POA irradiance ─────────────────────────────────────────
        theta_pan_f  = StatePan.Angle;
        theta_tilt_f = StateTilt.Angle;

        cp3 = cosd(theta_pan_f); sp3 = sind(theta_pan_f);
        ct3 = cosd(theta_tilt_f); st3 = sind(theta_tilt_f);
        Sx3 = cp3*S_vec(1) - sp3*S_vec(2);
        Sy3 = sp3*S_vec(1) + cp3*S_vec(2);
        S_body_f = [Sx3; ct3*Sy3 - st3*S_vec(3); st3*Sy3 + ct3*S_vec(3)];
        S_body_fn = S_body_f / (norm(S_body_f) + 1e-8);

        % DNI from beam-horizontal (guard against low-elevation singularities)
        zenith = 90 - sun_elev;
        if zenith < 88.0 && sun_elev >= 5.0
            DNI = beam_now / max(cosd(zenith), 0.174);
            DNI = min(DNI, 1200);
        else
            DNI = 0;
        end

        cos_t         = max(0, S_body_fn(3));
        G_POA_tracker = (DNI * cos_t) + (dhi_now * (1 + cosd(theta_tilt_f)) / 2);

        % Faiman temperature correction for tracker
        T_cell_trk = T_amb + G_POA_tracker / (U0 + U1*WS);
        T_cell_trk = max(T_amb, T_cell_trk);
        eta_trk    = max(0.01, ETA_STC * (1 + gamma_P * (T_cell_trk - T_STC)));

        P_tracker_gross(i) = G_POA_tracker * PANEL_AREA * eta_trk;

        cos_theta_log(i)  = cos_t;
        theta_tilt_log(i) = theta_tilt_f;
        T_cell_trk_log(i) = T_cell_trk;
        eta_trk_log(i)    = eta_trk;

        %% — Parasitic power (PWM detached in HOLD/IDLE → I_motor = 0) ─────
        is_hold  = ismember(FSM_State.mode, {'HOLD','IDLE'});
        I_motor  = ternary(is_hold || ~fsm_active, 0, ...
                           (I_pan_accum + I_tilt_accum) / N_sub);
        P_parasitic(i)   = I_motor * V_SUPPLY;
        P_tracker_net(i) = P_tracker_gross(i) - P_parasitic(i);
        FSM_log{i}       = FSM_State.mode;

    end % inner loop
    elapsed = toc;

    %% ── FSM state-time summary ────────────────────────────────────────────
    n_track = sum(strcmp(FSM_log,'TRACKING'));
    n_hold  = sum(strcmp(FSM_log,'HOLD'));
    n_srch  = sum(strcmp(FSM_log,'SEARCH'));
    n_idle  = sum(strcmp(FSM_log,'IDLE'));
    fprintf('  Done in %.1f s\n', elapsed);
    fprintf('  FSM : TRACKING=%ds | HOLD=%ds | SEARCH=%ds | IDLE=%ds\n', ...
            n_track, n_hold, n_srch, n_idle);

    %% ── Energy integrals (trapezoidal rule) ──────────────────────────────
    E_fixed  = trapz(t_sec, P_fixed)               / 3600;  % [Wh]
    E_gross  = trapz(t_sec, P_tracker_gross)        / 3600;
    E_para   = trapz(t_sec, P_parasitic)            / 3600;
    E_net    = trapz(t_sec, max(0, P_tracker_net))  / 3600;
    Para_r   = 100 * E_para  / (E_gross + 1e-9);
    Net_gain = 100 * (E_net - E_fixed) / (E_fixed + 1e-9);

    % Temperature statistics (daytime only)
    idx_day         = (GHI_sec > 10);
    T_amb_mean      = mean(T2m_sec(idx_day));
    T_cell_fix_mean = mean(T_cell_fix_log(idx_day));
    T_cell_trk_mean = mean(T_cell_trk_log(idx_day));
    eta_fix_mean    = mean(eta_fix_log(idx_day));
    eta_trk_mean    = mean(eta_trk_log(idx_day));

    fprintf('  E_fixed=%.2fWh | E_gross=%.2fWh | E_para=%.2fWh | E_net=%.2fWh\n', ...
            E_fixed, E_gross, E_para, E_net);
    fprintf('  Net Gain=%+.2f%%  |  Parasitic=%.2f%%\n', Net_gain, Para_r);
    fprintf('  T_amb=%.1f°C | T_cell_fix=%.1f°C | T_cell_trk=%.1f°C\n\n', ...
            T_amb_mean, T_cell_fix_mean, T_cell_trk_mean);

    %% ── cos(θ) gain bands ────────────────────────────────────────────────
    Gain_095 = 0; Gain_090 = 0; Gain_080 = 0;
    thresholds = {0.95, 'Gain_095'; 0.90, 'Gain_090'; 0.80, 'Gain_080'};
    for row = 1:size(thresholds, 1)
        thresh = thresholds{row, 1};
        varname = thresholds{row, 2};
        idx_c = (cos_theta_log >= thresh);
        if sum(idx_c) > 0
            eval(sprintf('%s = 100*(trapz(t_sec(idx_c), max(0,P_tracker_net(idx_c))) - trapz(t_sec(idx_c),P_fixed(idx_c))) / (trapz(t_sec(idx_c),P_fixed(idx_c))+1e-9);', varname));
        end
    end

    %% ── Store results ─────────────────────────────────────────────────────
    Results(d).label           = season_names{d};
    Results(d).month_length    = month_lengths(d);
    Results(d).n_julian        = n_julian;
    Results(d).rep_date        = rep_date;
    Results(d).E_fixed         = E_fixed;
    Results(d).E_gross         = E_gross;
    Results(d).E_para          = E_para;
    Results(d).E_net           = E_net;
    Results(d).Para_r          = Para_r;
    Results(d).Net_gain        = Net_gain;
    Results(d).n_track         = n_track;
    Results(d).n_hold          = n_hold;
    Results(d).n_srch          = n_srch;
    Results(d).n_idle          = n_idle;
    Results(d).Gain_095        = Gain_095;
    Results(d).Gain_090        = Gain_090;
    Results(d).Gain_080        = Gain_080;
    Results(d).T_amb_mean      = T_amb_mean;
    Results(d).T_cell_fix_mean = T_cell_fix_mean;
    Results(d).T_cell_trk_mean = T_cell_trk_mean;
    Results(d).eta_fix_mean    = eta_fix_mean;
    Results(d).eta_trk_mean    = eta_trk_mean;

    AllData{d}.t_sec           = t_sec;
    AllData{d}.GHI             = GHI_sec;
    AllData{d}.Beam            = Beam_sec;
    AllData{d}.DHI             = DHI_sec;
    AllData{d}.Sun_Elevation   = alpha_vec;
    AllData{d}.Sun_Azimuth     = phi_vec;
    AllData{d}.T2m             = T2m_sec;
    AllData{d}.WS              = WS_sec;
    AllData{d}.P_fixed         = P_fixed;
    AllData{d}.P_tracker_gross = P_tracker_gross;
    AllData{d}.P_tracker_net   = P_tracker_net;
    AllData{d}.P_parasitic     = P_parasitic;
    AllData{d}.cos_theta       = cos_theta_log;
    AllData{d}.theta_tilt      = theta_tilt_log;
    AllData{d}.T_cell_fix      = T_cell_fix_log;
    AllData{d}.T_cell_trk      = T_cell_trk_log;
    AllData{d}.eta_fix         = eta_fix_log;
    AllData{d}.eta_trk         = eta_trk_log;
    AllData{d}.FSM_log         = FSM_log;

    %% ── Detailed per-second CSV ───────────────────────────────────────────
    csv_out = fullfile(res_dir, sprintf('Detailed_%s_Month%02d.csv', loc_name, d));
    T_detail = table(t_sec, alpha_vec, phi_vec, GHI_sec, Beam_sec, DHI_sec, ...
        T2m_sec, WS_sec, T_cell_fix_log, T_cell_trk_log, ...
        eta_fix_log, eta_trk_log, cos_theta_log, theta_tilt_log, ...
        P_fixed, P_tracker_gross, P_parasitic, P_tracker_net, FSM_log, ...
        'VariableNames', {'Time_s','Sun_Elev_deg','Sun_Az_deg', ...
            'GHI_W_m2','Beam_W_m2','DHI_W_m2','T_amb_C','WS_m_s', ...
            'T_cell_fixed_C','T_cell_tracker_C','eta_fixed','eta_tracker', ...
            'cos_theta','Tilt_deg', ...
            'P_fixed_W','P_tracker_gross_W','P_parasitic_W','P_tracker_net_W', ...
            'FSM_State'});
    writetable(T_detail, csv_out);
    fprintf('  ✓ CSV: %s\n', csv_out);

end % month loop

%% ══════════════════════════════════════════════════════════════════════════
%%  ANNUAL ROLL-UP
%% ══════════════════════════════════════════════════════════════════════════
E_fixed_yr = 0; E_gross_yr = 0; E_para_yr = 0; E_net_yr = 0;
n_track_yr = 0; n_hold_yr  = 0; n_idle_yr  = 0;
T_amb_yr   = 0; T_fix_yr   = 0; T_trk_yr   = 0;

for d = 1:nDays
    if isempty(Results(d).label), continue; end
    w          = month_lengths(d);
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

fprintf('\n════════════════════════════════════════════════════════════════\n');
fprintf('  ANNUAL YIELD SUMMARY (Direct PVGIS | Faiman Temp | Option-A)\n');
fprintf('  Location : %s\n', Geo.Name);
fprintf('════════════════════════════════════════════════════════════════\n');
fprintf('  E_fixed = %8.1f Wh/yr  =  %6.2f kWh/yr\n',  E_fixed_yr, E_fixed_yr/1000);
fprintf('  E_gross = %8.1f Wh/yr  =  %6.2f kWh/yr\n',  E_gross_yr, E_gross_yr/1000);
fprintf('  E_para  = %8.1f Wh/yr  =  %6.3f kWh/yr\n',  E_para_yr,  E_para_yr/1000);
fprintf('  E_net   = %8.1f Wh/yr  =  %6.2f kWh/yr\n',  E_net_yr,   E_net_yr/1000);
fprintf('  Net Gain      : %+.2f %%\n', Gain_yr);
fprintf('  Parasitic     : %.2f %%\n',  Para_yr);
fprintf('  Avg T_amb     : %.1f °C\n',  T_amb_yr);
fprintf('  Avg T_cell (fix) : %.1f °C\n', T_fix_yr);
fprintf('  Avg T_cell (trk) : %.1f °C\n', T_trk_yr);
fprintf('════════════════════════════════════════════════════════════════\n\n');

%% Monthly breakdown table
fprintf('  %-5s | %4s | %5s | %9s | %8s | %7s | %6s | %8s | %8s\n', ...
    'Month','n','Date','E_Net(Wh)','Gain(%)','Para(%)','T_amb','T_fix','T_trk');
fprintf('  %s\n', repmat('-',1,82));
for d = 1:nDays
    if isempty(Results(d).label), continue; end
    fprintf('  %-5s | %3d | %5s | %9.1f | %+8.2f | %7.2f | %6.1f | %8.1f | %8.1f\n', ...
        Results(d).label, Results(d).n_julian, ...
        char(Results(d).rep_date,'dd-MMM'), ...
        Results(d).E_net, Results(d).Net_gain, Results(d).Para_r, ...
        Results(d).T_amb_mean, Results(d).T_cell_fix_mean, Results(d).T_cell_trk_mean);
end
fprintf('  %s\n\n', repmat('-',1,82));

%% Save .mat
mat_out = fullfile(res_dir, sprintf('%s_Results_Direct.mat', upper(loc_name)));
save(mat_out, 'Results', 'AllData', 'Geo', 'Gain_yr', 'Para_yr', ...
              'T_amb_yr', 'T_fix_yr', 'T_trk_yr', ...
              'E_fixed_yr', 'E_net_yr', 'E_gross_yr', 'E_para_yr');
fprintf('  ✓ Results saved: %s\n\n', mat_out);

%% ══════════════════════════════════════════════════════════════════════════
%%  FIGURES
%% ══════════════════════════════════════════════════════════════════════════
fprintf('Generating figures...\n');

FN      = 'Times New Roman';
FSs = 9; FSr = 11; FSl = 12; FSt = 13;
C_fix   = [0.13 0.29 0.53];
C_net   = [0.93 0.69 0.13];
C_para  = [0.75 0.15 0.15];
C_temp  = [0.85 0.33 0.10];
mon_labels = {Results.label};

valid_d = find(~cellfun(@isempty, {Results.label}));

%% Fig 1 — Net energy & breakdown (bar) ───────────────────────────────────
fig1 = figure('Color','w','NumberTitle','off','Visible','off');
fig1.Position = [50 50 1400 580];
ax1 = axes(fig1);
set(ax1,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',valid_d,'XTickLabel',mon_labels(valid_d), ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');
hold(ax1,'on');

E_net_v   = [Results(valid_d).E_net];
E_fixed_v = [Results(valid_d).E_fixed];
E_para_v  = [Results(valid_d).E_para];

b1 = bar(ax1, valid_d, [E_net_v; E_fixed_v; E_para_v]', 0.7, 'grouped');
b1(1).FaceColor = C_net;    b1(1).EdgeColor = 'none';
b1(2).FaceColor = C_fix;    b1(2).EdgeColor = 'none';
b1(3).FaceColor = C_para;   b1(3).EdgeColor = 'none';

gains_v = [Results(valid_d).Net_gain];
for k = 1:numel(valid_d)
    text(ax1, valid_d(k) + b1(1).XOffset, E_net_v(k)*1.03, ...
        sprintf('%+.1f%%', gains_v(k)), ...
        'HorizontalAlignment','center','FontSize',FSs,'FontName',FN,'FontWeight','bold');
end

ylabel(ax1,'Energy (Wh/day)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax1,'Month',          'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax1, sprintf('Monthly Energy Yield — %s  (Direct PVGIS | Klein Days | Faiman Temp)', Geo.Name), ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax1, b1, {'Tracker net','Fixed','Parasitic'}, ...
    'Location','northwest','FontName',FN,'FontSize',FSr,'Box','on');
exportgraphics(fig1, fullfile(res_dir,'Fig1_EnergyBreakdown_Direct.png'), 'Resolution',300);
close(fig1);
fprintf('  ✓ Fig1_EnergyBreakdown_Direct.png\n');

%% Fig 2 — Cell temperature ───────────────────────────────────────────────
fig2 = figure('Color','w','NumberTitle','off','Visible','off');
fig2.Position = [50 50 1400 560];
ax2 = axes(fig2);
set(ax2,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',valid_d,'XTickLabel',mon_labels(valid_d), ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');
hold(ax2,'on');
T_amb_v = [Results(valid_d).T_amb_mean];
T_fix_v = [Results(valid_d).T_cell_fix_mean];
T_trk_v = [Results(valid_d).T_cell_trk_mean];
plot(ax2, valid_d, T_amb_v, '-o','Color',[0.4 0.4 0.8],'LineWidth',2.0,'MarkerSize',7,'DisplayName','T_{amb}');
plot(ax2, valid_d, T_fix_v, '-s','Color',C_fix,        'LineWidth',2.0,'MarkerSize',7,'DisplayName','T_{cell} fixed');
plot(ax2, valid_d, T_trk_v, '-^','Color',C_temp,       'LineWidth',2.0,'MarkerSize',7,'DisplayName','T_{cell} tracker');
yline(ax2, T_STC,'--k','LineWidth',1.2,'Label','STC 25°C');
ylabel(ax2,'Temperature (°C)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax2,'Month',            'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax2, sprintf('Monthly Cell Temperature — %s  (Faiman / IEC 61853-2)', Geo.Name), ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax2,'Location','northwest','FontName',FN,'FontSize',FSr,'Box','on');
exportgraphics(fig2, fullfile(res_dir,'Fig2_CellTemperature_Direct.png'), 'Resolution',300);
close(fig2);
fprintf('  ✓ Fig2_CellTemperature_Direct.png\n');

%% Fig 3 — Net gain bar ───────────────────────────────────────────────────
fig3 = figure('Color','w','NumberTitle','off','Visible','off');
fig3.Position = [50 50 1400 560];
ax3 = axes(fig3);
set(ax3,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',valid_d,'XTickLabel',mon_labels(valid_d), ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');
hold(ax3,'on');
gains_v = [Results(valid_d).Net_gain];
b3 = bar(ax3, valid_d, gains_v, 0.65, 'FaceAlpha',0.85,'EdgeColor','none');
b3.FaceColor = 'flat';
nrm = (gains_v - min(gains_v)) ./ (max(gains_v) - min(gains_v) + 1e-9);
for k = 1:numel(valid_d)
    b3.CData(k,:) = (1-nrm(k))*C_fix + nrm(k)*C_net;
    text(ax3, valid_d(k), gains_v(k) + max(gains_v)*0.025, ...
        sprintf('%+.1f%%', gains_v(k)), ...
        'HorizontalAlignment','center','FontSize',FSs,'FontName',FN,'FontWeight','bold');
end
annotation(fig3,'textbox',[0.72 0.68 0.20 0.20], ...
    'String', sprintf('Annual Net Gain\n%+.2f%%\nT_{fix}: %.1f°C\nT_{trk}: %.1f°C', ...
                      Gain_yr, T_fix_yr, T_trk_yr), ...
    'FontName',FN,'FontSize',FSr,'HorizontalAlignment','center', ...
    'EdgeColor',[0.7 0.7 0.7],'LineWidth',1,'BackgroundColor',[1 1 0.95]);
ylabel(ax3,'Net Efficiency Gain (%)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax3,'Month',                  'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax3, sprintf('Monthly Net Gain — Tracker vs Fixed — %s', Geo.Name), ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
exportgraphics(fig3, fullfile(res_dir,'Fig3_NetGain_Direct.png'), 'Resolution',300);
close(fig3);
fprintf('  ✓ Fig3_NetGain_Direct.png\n');

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  CompareYield_Direct COMPLETE                                 ║\n');
fprintf('║  Location : %-48s║\n', Geo.Name);
fprintf('║  Net Gain : %+.2f %%                                          ║\n', Gain_yr);
fprintf('║  Results  : %s\n', res_dir);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');
