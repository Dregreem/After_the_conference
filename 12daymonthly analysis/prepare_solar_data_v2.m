function prepare_solar_data_v2(location, output_filename)
%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  prepare_solar_data_v2.m                                             ║
%% ║                                                                      ║
%% ║  Reshapes a single PVGIS 5.3 / SARAH3 TMY CSV into a high-detail    ║
%% ║  1-second resolution dataset ready for CompareYield_Direct.          ║
%% ║                                                                      ║
%% ║  KEY IMPROVEMENTS over prepare_solar_data.m:                         ║
%% ║    • One input file only — CITY_TMY.csv (no 12 monthly files)        ║
%% ║    • T2m and WS10m columns included (Faiman model ready)             ║
%% ║    • Sun geometry vectorised (no per-second getSunVector loop)       ║
%% ║    • Linear interp matches CompareYield_Direct exactly               ║
%% ║    • Klein_n column written so the reader can verify rep. day        ║
%% ║    • Validation report: irradiance energy balance per month          ║
%% ║    • Optional: write per-month stats to a separate summary CSV       ║
%% ║                                                                      ║
%% ║  OUTPUT CSV COLUMNS:                                                 ║
%% ║    Month, Klein_n, Time_s, GHI, Beam, DHI,                          ║
%% ║    T2m, WS10m, Sun_Elevation, Sun_Azimuth                           ║
%% ║                                                                      ║
%% ║  OUTPUT SIZE:  12 months × 86 400 s  =  1 036 800 rows              ║
%% ║  (no 86401 fence-post — final second of day not doubled)            ║
%% ║                                                                      ║
%% ║  USAGE:                                                              ║
%% ║    prepare_solar_data_v2()                          % ISTANBUL        ║
%% ║    prepare_solar_data_v2('ANKARA')                                   ║
%% ║    prepare_solar_data_v2('ANTALYA', 'ANTALYA_v2.csv')               ║
%% ╚══════════════════════════════════════════════════════════════════════╝

    %% ── Defaults ─────────────────────────────────────────────────────────
    if nargin < 1 || isempty(location),        location        = 'ISTANBUL';          end
    if nargin < 2 || isempty(output_filename), output_filename = ...
            sprintf('%s_HOURLY.csv', upper(location));                               end

    addpath(genpath(pwd));

    %% ── Banner ───────────────────────────────────────────────────────────
    fprintf('\n╔════════════════════════════════════════════════════════════════╗\n');
    fprintf('║  SOLAR DATA PREPROCESSOR  v2                                   ║\n');
    fprintf('║  PVGIS TMY → 1-second | Klein Days | Option-A Sun Geometry     ║\n');
    fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

    %% ── Geographic config ────────────────────────────────────────────────
    try
        Geo = getGeoConfig_month(location);
    catch
        % Build path relative to this script's location
        script_dir = fileparts(mfilename('fullpath'));
        % Construct folder with proper casing: first letter uppercase, rest lowercase
        loc_folder = [upper(location(1)), lower(location(2:end))];
        
        Geo.Name       = upper(location);
        Geo.Lat        = 41.05;
        Geo.Lon        = 29.01;
        Geo.TZ         = 3;
        Geo.PVGIS_File = fullfile(script_dir, 'DATA', loc_folder, sprintf('%s_HOURLY_12dates.csv', upper(location)));
    end
    fprintf('  Location    : %s  (%.4f N, %.4f E | UTC%+d)\n', ...
            Geo.Name, Geo.Lat, Geo.Lon, Geo.TZ);
    fprintf('  TMY source  : %s\n', Geo.PVGIS_File);
    fprintf('  Output      : %s\n\n', output_filename);

    %% ── Constants ────────────────────────────────────────────────────────
    klein_days    = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];
    month_names   = {'January','February','March','April','May','June', ...
                     'July','August','September','October','November','December'};
    month_lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    N_sec         = 86400;    % seconds per day (no fence-post)
    t_sec         = (0 : N_sec-1)';   % [86400×1]

    %% ── Load TMY once ────────────────────────────────────────────────────
    if ~isfile(Geo.PVGIS_File)
        error('[prepare_solar_data_v2] TMY file not found: %s', Geo.PVGIS_File);
    end
    fprintf('  Loading TMY ... ');
    TMY = loadPVGIS(Geo.PVGIS_File);
    fprintf('✓  %d records  (%s → %s)\n\n', numel(TMY.time), ...
            char(TMY.time(1), 'yyyy-MM-dd'), char(TMY.time(end), 'yyyy-MM-dd'));

    pvgis_year = year(TMY.time(1));

    %% ── Pre-allocate output arrays ───────────────────────────────────────
    TOTAL = N_sec * 12;
    out_Month    = zeros(TOTAL, 1, 'uint8');
    out_KleinN   = zeros(TOTAL, 1, 'uint16');
    out_Time_s   = zeros(TOTAL, 1, 'uint32');
    out_GHI      = zeros(TOTAL, 1, 'single');
    out_Beam     = zeros(TOTAL, 1, 'single');
    out_DHI      = zeros(TOTAL, 1, 'single');
    out_T2m      = zeros(TOTAL, 1, 'single');
    out_WS10m    = zeros(TOTAL, 1, 'single');
    out_SunElev  = zeros(TOTAL, 1, 'single');
    out_SunAz    = zeros(TOTAL, 1, 'single');

    %% ── Summary struct (per-month validation) ────────────────────────────
    MonthStats(12) = struct('month',0,'klein_n',0,'rep_date',NaT, ...
        'pvgis_rows',0,'G_peak',0,'daylight_h',0,'insolation_pvgis',0, ...
        'insolation_interp',0,'T2m_mean',0,'WS_mean',0,'ok',false);

    fprintf('┌─────────────────────────────────────────────────────────────────┐\n');
    fprintf('│  Month        Klein n   Date        G_peak  Daylight  Insolation │\n');
    fprintf('│                                     W/m²    hours     Wh/m²      │\n');
    fprintf('├─────────────────────────────────────────────────────────────────┤\n');

    %% ── Main loop over 12 months ─────────────────────────────────────────
    for m = 1:12

        n_julian = klein_days(m);
        rep_date = datetime(pvgis_year, 1, 1) + days(n_julian - 1);

        %% STEP 1 — Extract 24 hourly PVGIS rows for the Klein date ─────────
        try
            [Day24, DayStats] = filterPVGISbyDate(TMY, 'DAILY', rep_date);
        catch ME
            warning('\n  [Month %d] filterPVGISbyDate failed: %s', m, ME.message);
            continue;
        end

        n24 = numel(Day24.time);
        if n24 < 24
            warning('\n  [Month %d] Only %d rows found (expected 24). Skipping.', m, n24);
            continue;
        end

        %% STEP 2 — Anchor times ─────────────────────────────────────────────
        %  PVGIS timestamps are always at HH:10 (10 minutes into each hour).
        %  Compute elapsed seconds from midnight of the representative day.
        midnight = dateshift(Day24.time(1), 'start', 'day');
        t_anchor = seconds(Day24.time - midnight);  % [24×1]  e.g. 600, 4200, …

        %% STEP 3 — Irradiance interpolation (linear, zero-clamped) ─────────
        %  Slope=0: GHI = Gb + Gd,  Beam = Gb (beam-horiz),  DHI = Gd
        GHI_raw  = Day24.Gb + Day24.Gd;
        Beam_raw = Day24.Gb;
        DHI_raw  = Day24.Gd;

        GHI_s  = max(0, interp1(t_anchor, GHI_raw,  t_sec, 'linear', 'extrap'));
        Beam_s = max(0, interp1(t_anchor, Beam_raw, t_sec, 'linear', 'extrap'));
        DHI_s  = max(0, interp1(t_anchor, DHI_raw,  t_sec, 'linear', 'extrap'));

        %% STEP 4 — Meteorological channels ─────────────────────────────────
        T2m_s  = interp1(t_anchor, Day24.T2m,   t_sec, 'linear', 'extrap');
        WS_s   = max(0.1, interp1(t_anchor, Day24.WS10m, t_sec, 'linear', 'extrap'));

        %% STEP 5 — Vectorised sun geometry (Option A — Klein Julian n) ──────
        %
        %  Equations from getSunVector.m, vectorised over 86 400 seconds.
        %  Using Klein / Spencer (1971) declination and EoT.
        %
        %  All angles in radians internally; outputs in degrees.
        %  phi_deg ∈ [0, 360), measured from North clockwise (ENU convention).

        lat_r    = deg2rad(Geo.Lat);
        B_r      = deg2rad(360/364 * (n_julian - 81));
        delta_r  = asin(sin(deg2rad(23.45)) * sin(deg2rad(360/365 * (n_julian - 81))));
        EoT      = 9.87*sin(2*B_r) - 7.53*cos(B_r) - 1.5*sin(B_r);   % [min]
        TC_h     = (4*(Geo.Lon - 15*Geo.TZ) + EoT) / 60;              % [h]

        t_h_vec  = double(t_sec) / 3600;           % [86400×1] hours from midnight
        LST_vec  = t_h_vec + TC_h;                 % local solar time
        omega_v  = deg2rad(15 * (LST_vec - 12));   % hour angle [rad]

        sin_a    = sin(lat_r)*sin(delta_r) + cos(lat_r)*cos(delta_r)*cos(omega_v);
        sin_a    = max(-1, min(1, sin_a));
        alpha_v  = rad2deg(asin(sin_a));            % elevation [deg]

        az_rad_v = atan2(-sin(omega_v) .* cos(delta_r), ...
                          cos(lat_r)*sin(delta_r) - sin(lat_r)*cos(delta_r).*cos(omega_v));
        phi_v    = mod(rad2deg(az_rad_v), 360);     % azimuth [deg], 0=N CW

        % Night gate: force irradiance to exactly zero below horizon
        night    = (alpha_v <= 0);
        GHI_s(night)  = 0;
        Beam_s(night) = 0;
        DHI_s(night)  = 0;

        %% STEP 6 — Write to pre-allocated output arrays ─────────────────────
        i1 = (m-1)*N_sec + 1;
        i2 = m*N_sec;

        out_Month(i1:i2)   = uint8(m);
        out_KleinN(i1:i2)  = uint16(n_julian);
        out_Time_s(i1:i2)  = uint32(t_sec);
        out_GHI(i1:i2)     = single(GHI_s);
        out_Beam(i1:i2)    = single(Beam_s);
        out_DHI(i1:i2)     = single(DHI_s);
        out_T2m(i1:i2)     = single(T2m_s);
        out_WS10m(i1:i2)   = single(WS_s);
        out_SunElev(i1:i2) = single(alpha_v);
        out_SunAz(i1:i2)   = single(phi_v);

        %% STEP 7 — Per-month validation stats ───────────────────────────────
        insolation_pvgis   = trapz(double(t_anchor)/3600, GHI_raw);  % Wh/m² from 24 pts
        insolation_interp  = trapz(double(t_sec)/3600,    GHI_s);    % Wh/m² from 86400 pts
        daylight_h         = sum(~night) / 3600;

        MonthStats(m).month             = m;
        MonthStats(m).klein_n           = n_julian;
        MonthStats(m).rep_date          = rep_date;
        MonthStats(m).pvgis_rows        = n24;
        MonthStats(m).G_peak            = max(GHI_s);
        MonthStats(m).daylight_h        = daylight_h;
        MonthStats(m).insolation_pvgis  = insolation_pvgis;
        MonthStats(m).insolation_interp = insolation_interp;
        MonthStats(m).T2m_mean          = mean(T2m_s(~night));
        MonthStats(m).WS_mean           = mean(WS_s(~night));
        MonthStats(m).ok                = true;

        fprintf('│  %-10s  n=%3d    %s   %5.1f   %5.1f h   %6.1f     │\n', ...
            month_names{m}, n_julian, char(rep_date,'dd-MMM'), ...
            MonthStats(m).G_peak, daylight_h, insolation_interp);
    end

    fprintf('└─────────────────────────────────────────────────────────────────┘\n\n');

    %% ── Assemble and write main CSV ──────────────────────────────────────
    fprintf('  Assembling output table ... ');
    T_out = table( ...
        double(out_Month),   double(out_KleinN),  double(out_Time_s), ...
        double(out_GHI),     double(out_Beam),    double(out_DHI), ...
        double(out_T2m),     double(out_WS10m), ...
        double(out_SunElev), double(out_SunAz), ...
        'VariableNames', { ...
            'Month', 'Klein_n', 'Time_s', ...
            'GHI', 'Beam', 'DHI', ...
            'T2m', 'WS10m', ...
            'Sun_Elevation', 'Sun_Azimuth'});
    fprintf('✓\n');

    fprintf('  Writing CSV ... ');
    writetable(T_out, output_filename);
    finfo = dir(output_filename);
    fprintf('✓  %.1f MB\n\n', finfo.bytes / 1e6);

    %% ── Write per-month summary CSV ──────────────────────────────────────
    summary_file = strrep(output_filename, '.csv', '_Summary.csv');
    valid_m = [MonthStats.ok];
    T_sum = table( ...
        [MonthStats(valid_m).month]', ...
        [MonthStats(valid_m).klein_n]', ...
        month_lengths(valid_m)', ...
        [MonthStats(valid_m).G_peak]', ...
        [MonthStats(valid_m).daylight_h]', ...
        [MonthStats(valid_m).insolation_pvgis]', ...
        [MonthStats(valid_m).insolation_interp]', ...
        [MonthStats(valid_m).T2m_mean]', ...
        [MonthStats(valid_m).WS_mean]', ...
        'VariableNames', {'Month','Klein_n','Days_in_month', ...
            'G_peak_W_m2','Daylight_h','Insolation_24pt_Wh_m2', ...
            'Insolation_1s_Wh_m2','T2m_daytime_mean_C','WS_daytime_mean_m_s'});
    writetable(T_sum, summary_file);
    fprintf('  Summary CSV : %s\n', summary_file);

    %% ── Validation report ────────────────────────────────────────────────
    fprintf('\n╔════════════════════════════════════════════════════════════════╗\n');
    fprintf('║  VALIDATION REPORT                                             ║\n');
    fprintf('╠════════════════════════════════════════════════════════════════╣\n');
    fprintf('║  %-10s  %8s  %10s  %10s  %6s  %6s\n', ...
        'Month','G_peak','Insol.PVGIS','Insol.1sec','T2m°C','WS m/s');
    fprintf('║  %s\n', repmat('-',1,62));
    annual_insol = 0;
    for m = 1:12
        if ~MonthStats(m).ok, continue; end
        err_pct = 100*(MonthStats(m).insolation_interp - MonthStats(m).insolation_pvgis) / ...
                      (MonthStats(m).insolation_pvgis + 1e-9);
        annual_insol = annual_insol + MonthStats(m).insolation_interp * month_lengths(m);
        fprintf('║  %-10s  %8.1f  %10.1f  %10.1f  %6.1f  %6.2f  (err %+.2f%%)\n', ...
            month_names{m}, ...
            MonthStats(m).G_peak, MonthStats(m).insolation_pvgis, ...
            MonthStats(m).insolation_interp, MonthStats(m).T2m_mean, ...
            MonthStats(m).WS_mean, err_pct);
    end
    fprintf('║  %s\n', repmat('-',1,62));
    fprintf('║  Annual insolation (weighted): %.1f Wh/m²/yr  = %.2f kWh/m²/yr\n', ...
        annual_insol, annual_insol/1000);
    fprintf('║\n');
    fprintf('║  Output rows  : %d  (%d months × %d s)\n', ...
        height(T_out), sum(valid_m), N_sec);
    fprintf('║  Columns      : %s\n', strjoin(T_out.Properties.VariableNames, ', '));
    fprintf('║  File         : %s\n', output_filename);
    fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

    %% ── Usage hint ───────────────────────────────────────────────────────
    fprintf('  ── How to use in CompareYield_Direct ─────────────────────────\n');
    fprintf('  Add this block before the month loop:\n\n');
    fprintf('    USE_PREBUILT_CSV = true;\n');
    fprintf('    prebuilt_csv = ''%s'';\n', output_filename);
    fprintf('    if USE_PREBUILT_CSV && isfile(prebuilt_csv)\n');
    fprintf('        PreData = readtable(prebuilt_csv);\n');
    fprintf('    end\n\n');
    fprintf('  Then inside the loop replace filterPVGISbyDate + interp blocks\n');
    fprintf('  with:  rows = PreData(PreData.Month == d, :);\n\n');
    fprintf('  Done!\n\n');
end
