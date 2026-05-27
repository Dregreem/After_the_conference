function prepare_solar_data(location, output_filename)
    % PREPARE_SOLAR_DATA - Preprocess PVGIS hourly data to 1-second solar dataset
    %
    % DESCRIPTION:
    %   Reads 12 monthly PVGIS "Average Daily Profile" CSV files (hourly data),
    %   interpolates to 1-second resolution, appends precise Sun kinematics
    %   using Klein's representative days, and exports consolidated dataset.
    %
    % USAGE:
    %   prepare_solar_data()
    %   prepare_solar_data('ISTANBUL')
    %   prepare_solar_data('ISTANBUL', 'my_output.csv')
    %
    % OUTPUT COLUMNS:
    %   Month, Time_in_Seconds, GHI, Beam, DHI, Sun_Elevation, Sun_Azimuth
    %
    % REFERENCE (Klein's Representative Days, Spencer 1971):
    %   Jan 17, Feb 16, Mar 16, Apr 15, May 15, Jun 11,
    %   Jul 17, Aug 16, Sep 15, Oct 15, Nov 14, Dec 10
    % ═══════════════════════════════════════════════════════════════════════════

    %% DEFAULTS
    if nargin < 1 || isempty(location),        location        = 'ANTALYA';                    end
    if nargin < 2 || isempty(output_filename), output_filename = 'ANTALYA_Data.csv'; end

    %% RESOLVE PATHS (independent of current working directory)
    script_dir   = fileparts(mfilename('fullpath'));   % .../SolarDataPreprocessing
    project_root = fileparts(script_dir);              % .../Finalized_system_model_PI
    data_dir     = fullfile(project_root, 'Antalya_Data');

    % Add project folders to path so getGeoConfig / getSunVector are found
    addpath(project_root);
    addpath(fullfile(project_root, 'Sun'));

    %% BANNER
    fprintf('\n╔════════════════════════════════════════════════════════════════╗\n');
    fprintf('║  SOLAR DATA PREPROCESSING PIPELINE                            ║\n');
    fprintf('║  Klein''s Representative Days → 1-second Resolution            ║\n');
    fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');
    fprintf('  Data folder : %s\n', data_dir);

    %% GEOGRAPHIC CONFIG
    Geo = getGeoConfig(location);
    fprintf('  Location    : %s  (%.3f N, %.3f E | UTC%+d)\n\n', ...
            Geo.Name, Geo.Lat, Geo.Lon, Geo.TZ);

    %% KLEIN'S REPRESENTATIVE DAYS
    klein_days  = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];
    month_names = {'January','February','March','April','May','June', ...
                   'July','August','September','October','November','December'};

    %% PRE-ALLOCATE OUTPUT  (86401 pts x 12 months)
    total_rows = 86401 * 12;
    Month_col  = zeros(total_rows, 1);
    Time_col   = zeros(total_rows, 1);
    GHI_col    = zeros(total_rows, 1);
    Beam_col   = zeros(total_rows, 1);
    DHI_col    = zeros(total_rows, 1);
    Elev_col   = zeros(total_rows, 1);
    Az_col     = zeros(total_rows, 1);
    row_idx    = 1;

    %% MAIN LOOP
    fprintf('+-  Processing Monthly Data ----------------------------------------+\n');

    for month = 1:12
        fprintf('| %-10s (%2d/12) ... ', month_names{month}, month);

        % ── STEP 1: FIND & READ FILE ─────────────────────────────────
        fname      = sprintf('Dailydata_%.3f_%.3f_SA3_%02d_0deg_0deg.csv', ...
                             Geo.Lat, Geo.Lon, month);
        pvgis_file = fullfile(data_dir, fname);

        if ~isfile(pvgis_file)
            % Fallback: loose pattern search
            hits = dir(fullfile(data_dir, sprintf('*SA3*%02d*.csv', month)));
            if isempty(hits)
                fprintf('SKIP  (not found: %s)\n', fname);
                continue;
            end
            pvgis_file = fullfile(data_dir, hits(1).name);
        end

        % Read entire file as text lines
        try
            lines = readlines(pvgis_file);
        catch ME
            fprintf('ERROR (read failed: %s)\n', ME.message);
            continue;
        end

        % ── STEP 2: PARSE 24-HOUR DATA BLOCK ─────────────────────────
        % Find first line starting with "00:00"
        start_idx = find(startsWith(strtrim(lines), "00:00"), 1);
        if isempty(start_idx)
            fprintf('ERROR ("00:00" marker not found)\n');
            continue;
        end

        ghi_vals  = zeros(24, 1);
        beam_vals = zeros(24, 1);
        dhi_vals  = zeros(24, 1);
        parse_ok  = true;

        for h = 1:24
            raw   = strtrim(lines(start_idx + h - 1));
            parts = split(raw);
            parts = parts(parts ~= "");      % remove empty tokens

            if numel(parts) < 4
                fprintf('ERROR (line %d: < 4 columns)\n', start_idx + h - 1);
                parse_ok = false;
                break;
            end

            ghi_vals(h)  = str2double(parts(2));   % G(i)
            beam_vals(h) = str2double(parts(3));   % Gb(i)
            dhi_vals(h)  = str2double(parts(4));   % Gd(i)
        end

        if ~parse_ok || any(isnan(ghi_vals)) || any(isnan(beam_vals)) || any(isnan(dhi_vals))
            fprintf('ERROR (NaN in parsed data)\n');
            continue;
        end

        % ── STEP 3: INTERPOLATE TO 1-SECOND RESOLUTION ───────────────
        hour_seconds = (0:23)' * 3600;     % 24 breakpoints in seconds
        time_vec     = (0:86400)';         % 86401 output points, 0 to 86400 s

        ghi_interp  = interp1(hour_seconds, ghi_vals,  time_vec, 'pchip', 'extrap');
        beam_interp = interp1(hour_seconds, beam_vals, time_vec, 'pchip', 'extrap');
        dhi_interp  = interp1(hour_seconds, dhi_vals,  time_vec, 'pchip', 'extrap');

        % Clamp to zero — irradiance cannot be negative
        ghi_interp(ghi_interp < 0)   = 0;
        beam_interp(beam_interp < 0) = 0;
        dhi_interp(dhi_interp < 0)   = 0;

        n_pts = numel(time_vec);    % 86401

        % ── STEP 4: SUN KINEMATICS FOR EACH SECOND ───────────────────
        rep_date = datetime(2024, 1, 1) + caldays(klein_days(month) - 1);

        sun_elevation = zeros(n_pts, 1);
        sun_azimuth   = zeros(n_pts, 1);

        for k = 1:n_pts
            frac_hr = time_vec(k) / 3600;                    % decimal hours
            dt_k    = rep_date + duration(frac_hr, 0, 0);    % exact datetime
            [~, elev, az] = getSunVector(Geo.Lat, Geo.Lon, dt_k, Geo.TZ);
            sun_elevation(k) = elev;
            sun_azimuth(k)   = az;
        end

        % ── ENFORCE PHYSICAL BOUNDARIES: Nighttime = Zero Irradiance ────
        % Find all indices where sun is below horizon (sun_elevation <= 0)
        night_mask = sun_elevation <= 0;
        % Set irradiance to EXACTLY 0 at night (not floating-point artifacts)
        ghi_interp(night_mask)  = 0;
        beam_interp(night_mask) = 0;
        dhi_interp(night_mask)  = 0;

        % ── STEP 5: WRITE TO OUTPUT ARRAYS ───────────────────────────
        e = row_idx + n_pts - 1;
        Month_col(row_idx:e) = month;
        Time_col(row_idx:e)  = time_vec;
        GHI_col(row_idx:e)   = ghi_interp;
        Beam_col(row_idx:e)  = beam_interp;
        DHI_col(row_idx:e)   = dhi_interp;
        Elev_col(row_idx:e)  = sun_elevation;
        Az_col(row_idx:e)    = sun_azimuth;
        row_idx = e + 1;

        fprintf('OK  (%d rows)\n', n_pts);
    end

    fprintf('+------------------------------------------------------------------+\n\n');

    %% ASSEMBLE & EXPORT TABLE
    actual       = row_idx - 1;
    output_table = table( ...
        Month_col(1:actual),  Time_col(1:actual), ...
        GHI_col(1:actual),    Beam_col(1:actual),  DHI_col(1:actual), ...
        Elev_col(1:actual),   Az_col(1:actual), ...
        'VariableNames', {'Month','Time_in_Seconds','GHI','Beam','DHI', ...
                          'Sun_Elevation','Sun_Azimuth'});

    out_path = fullfile(script_dir, output_filename);
    writetable(output_table, out_path);

    fprintf('  Exported    : %s\n', out_path);
    fprintf('  Total rows  : %d  (%d months)\n\n', actual, round(actual/86401));

    %% SUMMARY STATISTICS
    if actual > 0
        fprintf('+-  Dataset Statistics ---------------------------------------------+\n');
        fprintf('| GHI   [W/m2]  Min=%7.1f  Max=%7.1f  Mean=%7.1f\n', ...
                min(output_table.GHI),  max(output_table.GHI),  mean(output_table.GHI));
        fprintf('| Beam  [W/m2]  Min=%7.1f  Max=%7.1f  Mean=%7.1f\n', ...
                min(output_table.Beam), max(output_table.Beam), mean(output_table.Beam));
        fprintf('| DHI   [W/m2]  Min=%7.1f  Max=%7.1f  Mean=%7.1f\n', ...
                min(output_table.DHI),  max(output_table.DHI),  mean(output_table.DHI));
        fprintf('| Elevation [deg]  Min=%6.1f   Max=%6.1f\n', ...
                min(output_table.Sun_Elevation), max(output_table.Sun_Elevation));
        fprintf('| Azimuth   [deg]  Min=%6.1f   Max=%6.1f\n', ...
                min(output_table.Sun_Azimuth),   max(output_table.Sun_Azimuth));
        fprintf('+------------------------------------------------------------------+\n\n');
    end

    fprintf('Done!\n\n');
end
