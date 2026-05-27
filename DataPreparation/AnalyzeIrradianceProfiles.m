function approved = AnalyzeIrradianceProfiles(loc_name, data_mode, results_base)
%% ANALYZEIRRADIANCEPROFILES  Simülasyon öncesi veri analizi ve grafikleri
%
%  Kullanım:
%    approved = AnalyzeIrradianceProfiles('YTU_FROM_NASA')
%    approved = AnalyzeIrradianceProfiles('ANTALYA', 'HOURLY')
%
%  Çıktı:
%    approved = true  → Kullanıcı onayladı, simülasyona geç
%    approved = false → Kullanıcı reddetti veya sorun var

if nargin < 1, loc_name  = 'YTU_FROM_NASA'; end
if nargin < 2, data_mode = 'HOURLY'; end

approved = false;

set(groot,'defaultTextInterpreter',              'tex');
set(groot,'defaultAxesTickLabelInterpreter',     'tex');
set(groot,'defaultLegendInterpreter',            'tex');
set(groot,'defaultColorbarTickLabelInterpreter', 'tex');

%% ── SETUP ────────────────────────────────────────────────────────────────

% Sonuçlar her zaman Results/<LOC>/Analysis/ altına gider
if nargin >= 3 && ~isempty(results_base)
    res_dir = fullfile(results_base, 'Results', upper(loc_name), 'Analysis');
elseif exist('RESULTS_BASE','var')
    res_dir = fullfile(RESULTS_BASE, 'Results', upper(loc_name), 'Analysis');
else
    res_dir = fullfile(fileparts(mfilename('fullpath')), 'Results', upper(loc_name), 'Analysis');
end
if ~isfolder(res_dir), mkdir(res_dir); end

% ─── VERİ KAYNAĞI SEÇİMİ ─────────────────────────────────────────────────
DATA_SOURCE = 'prepared';

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  IRRADIANCE PROFILE ANALYSIS — %s                          ║\n', upper(loc_name));
fprintf('║  Veri Kaynağı: %-44s║\n', DATA_SOURCE);
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% ── LOAD DATA ────────────────────────────────────────────────────────────
if strcmp(DATA_SOURCE, 'prepared')
    % ── Hazır .mat dosyasından yükle (sisteme giren gerçek veri) ─────────
    mat_filename = sprintf('prepared_data_HOURLY_%s.mat', upper(loc_name));
    script_dir = fileparts(mfilename('fullpath'));
    search_mat = {mat_filename, fullfile('..', mat_filename), fullfile(script_dir, mat_filename)};
    
    mat_path = '';
    for k = 1:numel(search_mat)
        if isfile(search_mat{k}), mat_path = search_mat{k}; break; end
    end
    
    if isempty(mat_path)
        fprintf('  ✗ Hazırlanmış veri bulunamadı!\n');
        fprintf('  Lütfen önce hazırlık scriptini çalıştırın:\n');
        fprintf('    >> prepareDataForAnalysis_Hourly(''%s'')\n\n', loc_name);
        error('Veri dosyası yoktur: %s', mat_filename);
    end
    
    fprintf('  ✓ Yükleniyor: %s\n', mat_path);
    load(mat_path, 'PreparedData');
    solar_data = PreparedData.solar_data;
    Geo        = PreparedData.Geo;
    fprintf('  ✓ %d kayıt yüklendi (sütunlar: %s)\n\n', ...
        height(solar_data), strjoin(solar_data.Properties.VariableNames, ', '));
    
    % T/WS verisi LUT'tan
    T_amb_data = PreparedData.T2m_lut;   % [12×24]
    WS_data    = PreparedData.WS_lut;    % [12×24]
    has_T_lut  = true;
    
    % Sütun adları zaten standart: GHI, Beam, DHI, Sun_Elevation, Sun_Azimuth, Month
    has_ghi = ismember('GHI', solar_data.Properties.VariableNames);
    
else
    % ── Ham CSV'den yükle (eski yol) ─────────────────────────────────────
    has_T_lut = false;
    T_amb_data = [];
    WS_data    = [];
    has_ghi    = false;
    
    % CSV dosyasını ara
    search_paths = { pwd, fullfile(pwd,'..'), fullfile(pwd,'..','Locations') };
    csv_patterns = { sprintf('%s_Hourly.csv',upper(loc_name)), sprintf('%s_Data.csv',upper(loc_name)) };
    csv_filepath = '';
    for pi = 1:numel(csv_patterns)
        for pp = 1:numel(search_paths)
            tp = fullfile(search_paths{pp}, csv_patterns{pi});
            if isfile(tp), csv_filepath = tp; break; end
        end
        if ~isempty(csv_filepath), break; end
    end
    
    if isempty(csv_filepath)
        error('Ham CSV bulunamadı: %s veya %s', csv_patterns{1}, csv_patterns{2});
    end
    
    fprintf('Loading: %s\n', csv_filepath);
    solar_data = readtable(csv_filepath, 'VariableNamingRule', 'preserve');
    fprintf('  ✓ %d records loaded\n', height(solar_data));
    
    try, Geo = getGeoConfig(loc_name); catch
        Geo.Name = loc_name; Geo.Lat = 41.05; Geo.Lon = 29.01; Geo.TZ = 3;
    end
end

if strcmp(DATA_SOURCE, 'raw')
% Display available columns
fprintf('  Available columns:\n');
col_names = solar_data.Properties.VariableNames;
for c = 1:length(col_names)
    fprintf('    • %s\n', col_names{c});
end

% Detect data type
is_hourly = ismember('Hour', col_names);
has_month = ismember('Month', col_names);
has_date = ismember('Date', col_names) || ismember('DateTime', col_names) || ...
           ismember('Datetime', col_names) || ismember('date', col_names);

if is_hourly
    fprintf('  ✓ Format: HOURLY (has Hour column)\n\n');
else
    fprintf('  ✓ Format: SECOND-LEVEL or aggregated\n\n');
end

% If no Month column, try to add it
if ~has_month && has_date
    fprintf('  Extracting Month from Date column...\n');
    date_col = '';
    for i = 1:length(col_names)
        if contains(lower(col_names{i}), 'date')
            date_col = col_names{i};
            break;
        end
    end
    if ~isempty(date_col)
        dates = solar_data.(date_col);
        if iscell(dates)
            solar_data.Month = month(datetime(dates));
        else
            solar_data.Month = month(dates);
        end
        has_month = true;
        fprintf('  ✓ Month column created\n\n');
    end
end

% If still no month, create from row index
if ~has_month
    fprintf('  Creating Month column from row index (assuming hourly data)...\n');
    n_records = height(solar_data);
    n_hours_per_year = 365.25 * 24;
    hour_of_year = mod(0:(n_records-1), n_hours_per_year)';
    day_of_year = floor(hour_of_year / 24) + 1;
    month_boundaries = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365];
    solar_data.Month = zeros(n_records, 1);
    for m = 1:12
        mask = day_of_year > month_boundaries(m) & day_of_year <= month_boundaries(m+1);
        solar_data.Month(mask) = m;
    end
    has_month = true;
    fprintf('  ✓ Month column created from row index\n\n');
end

if ~has_month
    error('Cannot determine Month from data. File format not recognized.');
end

%% ── LOAD TEMPERATURE DATA ────────────────────────────────────────────────
avg_csv = sprintf('%s_MonthlyAvg.csv', upper(loc_name));
avg_csv_path = '';
for p = 1:length(search_paths)
    test_path = fullfile(search_paths{p}, avg_csv);
    if isfile(test_path)
        avg_csv_path = test_path;
        break;
    end
end
if isempty(avg_csv_path)
    for p = 1:length(search_paths)
        test_path = fullfile(search_paths{p}, 'YTU_MonthlyAvg.csv');
        if isfile(test_path)
            avg_csv_path = test_path;
            break;
        end
    end
end
T_amb_data = [];
if ~isempty(avg_csv_path)
    fprintf('Loading: %s\n', avg_csv_path);
    T_amb_data = readtable(avg_csv_path, 'VariableNamingRule', 'preserve');
    fprintf('  ✓ %d temperature records\n\n', height(T_amb_data));
else
    fprintf('⚠️  Temperature data not found (optional)\n\n');
end
end  % end if raw

%% ── PARAMETERS ───────────────────────────────────────────────────────────
season_names = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
month_lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
representative_days = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];
nDays = 12;

if ~exist('Geo','var')
    try, Geo = getGeoConfig(loc_name);
    catch, Geo.Name = loc_name; Geo.Lat = 41.05; Geo.Lon = 29.01; Geo.TZ = 3;
    end
end

fprintf('Location: %s (%.2f°N, %.2f°E) UTC%+d\n\n', Geo.Name, Geo.Lat, Geo.Lon, Geo.TZ);

%% ── COMPUTE AVERAGE PROFILES (HOUR-BY-HOUR) ──────────────────────────────
fprintf('Computing hourly averages for each month...\n');

GHI_hourly_avg  = zeros(12, 24);
Beam_hourly_avg = zeros(12, 24);
DHI_hourly_avg  = zeros(12, 24);
sunrise_hour    = zeros(12, 1);
sunset_hour     = zeros(12, 1);

col_names = solar_data.Properties.VariableNames;
has_ghi   = ismember('GHI',    col_names);
has_gbi   = ismember('Gb(i)',  col_names);
has_gdi   = ismember('Gd(i)',  col_names);
has_beam  = ismember('Beam',   col_names);
has_dhi   = ismember('DHI',    col_names);

if strcmp(DATA_SOURCE, 'prepared')
    %% PREPARED DATA: 1-saniye çözünürlük, Month + GHI + Beam + DHI + Sun_Elevation mevcut
    fprintf('Prepared data: 12 ay × 86400s → saatlik ortalama alınıyor...\n');
    has_sun_el = ismember('Sun_Elevation', col_names);
    
    for d = 1:nDays
        mask_m = (solar_data.Month == d);
        month_data = solar_data(mask_m, :);
        N = height(month_data);
        if N == 0, continue; end
        
        % Time_in_Seconds kolonundan saat belirle (0-86399 → saat 0-23)
        if ismember('Time_in_Seconds', col_names)
            h_idx = floor(month_data.Time_in_Seconds / 3600);
        else
            h_idx = mod((0:N-1)', 86400) / 3600;
            h_idx = floor(h_idx);
        end
        
        for h = 0:23
            mask_h = (h_idx == h);
            if ~any(mask_h), continue; end
            
            if has_ghi
                GHI_hourly_avg(d, h+1)  = mean(month_data.GHI(mask_h),  'omitnan');
            end
            if has_beam
                Beam_hourly_avg(d, h+1) = mean(month_data.Beam(mask_h), 'omitnan');
            end
            if has_dhi
                DHI_hourly_avg(d, h+1)  = mean(month_data.DHI(mask_h),  'omitnan');
            end
        end
        
        daytime_idx = find(GHI_hourly_avg(d, :) > 10);
        if ~isempty(daytime_idx)
            sunrise_hour(d) = daytime_idx(1)   - 1;
            sunset_hour(d)  = daytime_idx(end) - 1;
        end
    end
    
    % T2m ve WS: LUT'tan (12×24) — zaten saatlik ortalama
    % has_T_lut = true, T_amb_data = PreparedData.T2m_lut
    fprintf('  ✓ Saatlik profiller hazır\n\n');

elseif ismember('Hour', col_names)
    %% RAW HOURLY DATA FORMAT
    fprintf('Data is already hourly. Aggregating by month and hour...\n');
    
    for d = 1:nDays
        month_data = solar_data(solar_data.Month == d, :);
        
        if height(month_data) == 0
            continue;
        end
        
        % Assume data has Hour column (0-23) or we need to create it
        if ismember('Hour', col_names)
            hours = month_data.Hour;
        else
            % Create hour from time column
            if ismember('time', col_names)
                time_vals = month_data.time;
                % Assume time is in decimal hours (0-24)
                hours = mod(time_vals, 24);
            else
                hours = zeros(height(month_data), 1);
            end
        end
        
        % Aggregate by hour
        for h = 0:23
            mask = hours == h;
            if sum(mask) > 0
                if has_gbi
                    GHI_hourly_avg(d, h+1) = mean(month_data.("Gb(i)")(mask), 'omitnan');
                elseif has_ghi
                    GHI_hourly_avg(d, h+1) = mean(month_data.GHI(mask), 'omitnan');
                end
                
                if has_gdi
                    DHI_hourly_avg(d, h+1) = mean(month_data.("Gd(i)")(mask), 'omitnan');
                end
            end
        end
        
        % Find sunrise/sunset
        daytime_idx = find(GHI_hourly_avg(d, :) > 10);
        if ~isempty(daytime_idx)
            sunrise_hour(d) = daytime_idx(1) - 1;
            sunset_hour(d) = daytime_idx(end) - 1;
        end
    end
    
else
    %% SECOND-LEVEL DATA FORMAT (need to aggregate to hourly)
    fprintf('Data is second-level. Aggregating to hourly...\n');
    
    % Convert time column to numeric if needed
    time_col = [];
    if ismember('time', col_names)
        time_data = solar_data.time;
        if iscell(time_data) || isstring(time_data)
            % Try to convert string times to numeric
            try
                fprintf('  Converting time strings to numeric...\n');
                time_col = cellfun(@str2double, cellstr(time_data));
            catch
                fprintf('  Could not convert time column. Using row index instead.\n');
                time_col = (0:(height(solar_data)-1))';
            end
        elseif isnumeric(time_data)
            time_col = time_data;
        end
    else
        % Use row index as time proxy
        time_col = (0:(height(solar_data)-1))';
    end
    
    for d = 1:nDays
        month_data = solar_data(solar_data.Month == d, :);
        time_data_month = time_col(solar_data.Month == d);
        N = height(month_data);
        
        if N == 0, continue; end
        
        hour_buckets = zeros(24, 1);
        ghi_sum = zeros(24, 1);
        dhi_sum = zeros(24, 1);
        
        for i = 1:N
            time_val = time_data_month(i);
            
            % Estimate hour from value (assuming decimal hour 0-24 or row index)
            if time_val < 100
                % Likely decimal hour format
                hour_idx = floor(mod(time_val, 24));
            else
                % Likely row index or seconds - use modulo
                hour_idx = mod(i-1, 24);
            end
            
            hour_buckets(hour_idx+1) = hour_buckets(hour_idx+1) + 1;
            
            if has_gbi
                gbi_val = max(0, month_data.("Gb(i)")(i));
            else
                gbi_val = 0;
            end
            if has_gdi
                gdi_val = max(0, month_data.("Gd(i)")(i));
                dhi_sum(hour_idx+1) = dhi_sum(hour_idx+1) + gdi_val;
            else
                gdi_val = 0;
            end
            if has_gbi || has_gdi
                ghi_sum(hour_idx+1) = ghi_sum(hour_idx+1) + gbi_val + gdi_val;
            elseif has_ghi
                ghi_sum(hour_idx+1) = ghi_sum(hour_idx+1) + month_data.GHI(i);
            end
        end
        
        for h = 1:24
            if hour_buckets(h) > 0
                GHI_hourly_avg(d, h) = ghi_sum(h) / hour_buckets(h);
                DHI_hourly_avg(d, h) = dhi_sum(h) / hour_buckets(h);
            end
        end
        
        daytime_idx = find(GHI_hourly_avg(d, :) > 10);
        if ~isempty(daytime_idx)
            sunrise_hour(d) = daytime_idx(1) - 1;
            sunset_hour(d) = daytime_idx(end) - 1;
        end
    end
end  % end if prepared / elseif hourly / else second-level

fprintf('  ✓ Hourly profiles computed\n\n');

%% ── FIGURE 1: MONTHLY AVERAGE vs REPRESENTATIVE DAY ──────────────────────
fprintf('Creating Figure 1: GHI Profiles...\n');

fig1 = figure('Color','w','NumberTitle','off','Visible','off');
fig1.Position = [50 50 1600 900];

% Select 3 representative months
months_to_plot = [1, 6, 10];  % Jan, June, Oct
colors_avg = {[0.2 0.4 0.9], [1.0 0.65 0.0], [0.5 0.85 0.3]};
colors_rep = {[0.2 0.8 0.9], [1.0 0.4 0.0], [0.7 1.0 0.2]};

% Plot 3 subplots
for subplot_idx = 1:3
    d = months_to_plot(subplot_idx);
    ax = subplot(1,3,subplot_idx);
    set(ax,'FontName','Times New Roman','FontSize',10,'Box','on','LineWidth',1.2);
    grid(ax, 'on');
    ax.GridAlpha = 0.3;
    hold(ax,'on');
    
    hours = 0:23;
    
    % Daily average profile
    plot(ax, hours, GHI_hourly_avg(d, :), 'o-', ...
        'Color', colors_avg{subplot_idx}, 'LineWidth', 2.5, 'MarkerSize', 5, ...
        'DisplayName', sprintf('Avg Daily %s (all %d days)', season_names{d}, month_lengths(d)));
    
    % For second-level / raw data, also show rep-day comparison
    if ~exist('is_hourly','var') || ~is_hourly
        % Representative day comparison (only for second-level / prepared data)
        month_data = solar_data(solar_data.Month == d, :);
        if has_gbi
            rep_ghi = month_data.("Gb(i)");
        elseif has_ghi
            rep_ghi = month_data.GHI;
        else
            rep_ghi = GHI_hourly_avg(d, :)';
        end
        
        % Downsample to hourly
        rep_ghi_hourly = zeros(24, 1);
        for h = 1:24
            idx = (h-1)*3600 + 1 : min(h*3600, length(rep_ghi));
            if ~isempty(idx)
                rep_ghi_hourly(h) = mean(rep_ghi(idx), 'omitnan');
            end
        end
        
        plot(ax, hours, rep_ghi_hourly, 's--', ...
            'Color', colors_rep{subplot_idx}, 'LineWidth', 2.0, 'MarkerSize', 5, ...
            'DisplayName', sprintf('Day %d (%s)', representative_days(d), ...
                datestr(datetime(2020,d,1)+representative_days(d)-1, 'mmm-dd')));
    end
    
    ylabel(ax, 'GHI [W/m²]', 'FontWeight', 'bold', 'FontSize', 11);
    xlabel(ax, 'Hour of Day [h]', 'FontWeight', 'bold', 'FontSize', 11);
    title(ax, sprintf('%s — Julian Day %d', season_names{d}, representative_days(d)), ...
        'FontSize', 12, 'FontWeight', 'bold');
    legend(ax, 'Location', 'northwest', 'FontSize', 9);
    ylim(ax, [0 1100]);
    xlim(ax, [0 24]);
end

sgtitle(sprintf('Daily GHI Profiles — %s (CompareYield Representative Days)', Geo.Name), ...
    'FontSize', 14, 'FontWeight', 'bold');
exportgraphics(fig1, fullfile(res_dir, 'Fig01_GHI_Profiles_3Months.png'), 'Resolution', 300);
close(fig1);
fprintf('  ✓ Fig01_GHI_Profiles_3Months.png\n\n');

%% ── FIGURE 2: ALL 12 MONTHS COMPARISON ────────────────────────────────────
fprintf('Creating Figure 2: Annual GHI Variation...\n');

fig2 = figure('Color','w','NumberTitle','off','Visible','off');
fig2.Position = [50 50 1400 700];
ax2 = axes(fig2);
set(ax2,'FontName','Times New Roman','FontSize',11,'Box','on','LineWidth',1.2);
grid(ax2, 'on');
ax2.GridAlpha = 0.3;
hold(ax2,'on');

% Plot all 12 months with different colors (colormap)
cmap = lines(12);
for d = 1:nDays
    plot(ax2, 0:23, GHI_hourly_avg(d, :), 'o-', ...
        'Color', cmap(d, :), 'LineWidth', 2.0, 'MarkerSize', 4, ...
        'DisplayName', season_names{d});
end

ylabel(ax2, 'Average GHI [W/m²]', 'FontWeight', 'bold', 'FontSize', 12);
xlabel(ax2, 'Hour of Day [h]', 'FontWeight', 'bold', 'FontSize', 12);
title(ax2, sprintf('Annual Daily Irradiance Profiles — %s', Geo.Name), ...
    'FontSize', 13, 'FontWeight', 'bold');
legend(ax2, 'Location', 'northwest', 'FontSize', 9, 'NumColumns', 2);
ylim(ax2, [0 1000]);
xlim(ax2, [0 24]);
exportgraphics(fig2, fullfile(res_dir, 'Fig02_GHI_All12Months.png'), 'Resolution', 300);
close(fig2);
fprintf('  ✓ Fig02_GHI_All12Months.png\n\n');

%% ── FIGURE 3: TEMPERATURE & WIND PROFILES ────────────────────────────────
if ~isempty(T_amb_data)
    fprintf('Creating Figure 3: Temperature & Wind...\n');
    
    fig3 = figure('Color','w','NumberTitle','off','Visible','off');
    fig3.Position = [50 50 1400 600];
    hours_axis = 0:23;
    
    % Subplot 1: Temperature
    ax3a = subplot(1,2,1);
    set(ax3a,'FontName','Times New Roman','FontSize',10,'Box','on','LineWidth',1.2);
    grid(ax3a, 'on'); ax3a.GridAlpha = 0.3;
    hold(ax3a,'on');
    
    cmap_temp = lines(12);
    for d = 1:nDays
        if has_T_lut
            % T_amb_data is [12×24] matrix
            plot(ax3a, hours_axis, T_amb_data(d, :), 'o-', ...
                'Color', cmap_temp(d,:), 'LineWidth', 1.8, 'MarkerSize', 4, ...
                'DisplayName', season_names{d});
        elseif istable(T_amb_data)
            rows_m = T_amb_data(T_amb_data.Month == d, :);
            [~, si] = sort(rows_m.Hour); rows_m = rows_m(si, :);
            if ~isempty(rows_m)
                plot(ax3a, rows_m.Hour, rows_m.T2m, 'o-', ...
                    'Color', cmap_temp(d,:), 'LineWidth', 1.8, 'MarkerSize', 4, ...
                    'DisplayName', season_names{d});
            end
        end
    end
    
    ylabel(ax3a, 'T_{amb} [°C]', 'FontWeight', 'bold', 'FontSize', 11);
    xlabel(ax3a, 'Hour of Day [h]', 'FontWeight', 'bold', 'FontSize', 11);
    title(ax3a, 'Hourly Air Temperature (Monthly)', 'FontSize', 12, 'FontWeight', 'bold');
    legend(ax3a, 'Location', 'best', 'FontSize', 8, 'NumColumns', 2);
    grid(ax3a, 'on'); ax3a.GridAlpha = 0.3;
    
    % Subplot 2: Wind Speed
    ax3b = subplot(1,2,2);
    set(ax3b,'FontName','Times New Roman','FontSize',10,'Box','on','LineWidth',1.2);
    grid(ax3b, 'on'); ax3b.GridAlpha = 0.3;
    hold(ax3b,'on');
    
    has_ws = has_T_lut || (istable(T_amb_data) && ismember('WS10m', T_amb_data.Properties.VariableNames));
    
    if has_ws
        for d = 1:nDays
            if has_T_lut
                plot(ax3b, hours_axis, WS_data(d, :), 'o-', ...
                    'Color', cmap_temp(d,:), 'LineWidth', 1.8, 'MarkerSize', 4, ...
                    'DisplayName', season_names{d});
            elseif istable(T_amb_data)
                rows_m = T_amb_data(T_amb_data.Month == d, :);
                [~, si] = sort(rows_m.Hour); rows_m = rows_m(si, :);
                if ~isempty(rows_m)
                    plot(ax3b, rows_m.Hour, rows_m.WS10m, 's-', ...
                        'Color', cmap_temp(d,:), 'LineWidth', 1.8, 'MarkerSize', 4, ...
                        'DisplayName', season_names{d});
                end
            end
        end
        ylabel(ax3b, 'WS_{10m} [m/s]', 'FontWeight', 'bold', 'FontSize', 11);
    else
        text(ax3b, 0.5, 0.5, 'WS10m data not available', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'FontSize', 11);
    end
    
    xlabel(ax3b, 'Hour of Day [h]', 'FontWeight', 'bold', 'FontSize', 11);
    title(ax3b, 'Hourly Wind Speed (Monthly)', 'FontSize', 12, 'FontWeight', 'bold');
    legend(ax3b, 'Location', 'best', 'FontSize', 8, 'NumColumns', 2);
    grid(ax3b, 'on');
    ax3b.GridAlpha = 0.3;
    
    sgtitle(sprintf('Temperature & Wind Patterns — %s', Geo.Name), ...
        'FontSize', 13, 'FontWeight', 'bold');
    exportgraphics(fig3, fullfile(res_dir, 'Fig03_Temperature_Wind.png'), 'Resolution', 300);
    close(fig3);
    fprintf('  ✓ Fig03_Temperature_Wind.png\n\n');
end

%% ── FIGURE 4: ENERGY CONTENT (DAILY INTEGRAL) ────────────────────────────
fprintf('Creating Figure 4: Daily Energy Content...\n');

daily_energy = zeros(12, 1);  % [Wh/day]
daily_peak = zeros(12, 1);
daily_sun_hours = zeros(12, 1);

for d = 1:nDays
    % Fill NaN values with 0 for integration (missing data points treated as no irradiance)
    ghi_clean = fillmissing(GHI_hourly_avg(d, :), 'constant', 0);
    
    % Integrate hourly profile
    daily_energy(d) = trapz(0:23, ghi_clean);  % Wh/m² per day
    daily_peak(d) = max(ghi_clean);
    
    % Effective sun hours (GHI > 10 W/m²)
    daytime_idx = ghi_clean > 10;
    daily_sun_hours(d) = sum(daytime_idx);
end

fig4 = figure('Color','w','NumberTitle','off','Visible','off');
fig4.Position = [50 50 1400 600];

% Subplot 1: Daily Energy
ax4a = subplot(1,2,1);
set(ax4a,'FontName','Times New Roman','FontSize',10,'Box','on','LineWidth',1.2);
hold(ax4a,'on');
cmap_energy = lines(12);
bar(ax4a, 1:12, daily_energy, 0.7, 'FaceColor', 'flat', 'EdgeColor', 'none');
for d = 1:12
    ax4a.Children(1).CData(d, :) = cmap_energy(d, :);
end
ylabel(ax4a, 'Daily Energy [Wh/m²]', 'FontWeight', 'bold', 'FontSize', 11);
xlabel(ax4a, 'Month', 'FontWeight', 'bold', 'FontSize', 11);
title(ax4a, 'Daily GHI Integral (Energy Content)', 'FontSize', 12, 'FontWeight', 'bold');
set(ax4a, 'XTick', 1:12, 'XTickLabel', season_names);
grid(ax4a, 'on');
ax4a.GridAlpha = 0.3;

% Add value labels
for d = 1:12
    text(ax4a, d, daily_energy(d) + max(daily_energy)*0.02, ...
        sprintf('%.0f', daily_energy(d)), 'HorizontalAlignment', 'center', ...
        'FontSize', 9, 'FontWeight', 'bold');
end

% Subplot 2: Peak vs Sun Hours
ax4b = subplot(1,2,2);
set(ax4b,'FontName','Times New Roman','FontSize',10,'Box','on','LineWidth',1.2);
yyaxis(ax4b,'left');
plot(ax4b, 1:12, daily_peak, 'o-', 'Color', [0.2 0.4 0.9], ...
    'LineWidth', 2.5, 'MarkerSize', 7, 'DisplayName', 'Peak GHI');
ylabel(ax4b, 'Peak GHI [W/m²]', 'FontWeight', 'bold', 'FontSize', 11, 'Color', [0.2 0.4 0.9]);
ax4b.YAxis(1).Color = [0.2 0.4 0.9];

yyaxis(ax4b,'right');
plot(ax4b, 1:12, daily_sun_hours, 's-', 'Color', [0.9 0.4 0.2], ...
    'LineWidth', 2.5, 'MarkerSize', 7, 'DisplayName', 'Daylight Hours');
ylabel(ax4b, 'Daylight Hours [h]', 'FontWeight', 'bold', 'FontSize', 11, 'Color', [0.9 0.4 0.2]);
ax4b.YAxis(2).Color = [0.9 0.4 0.2];

xlabel(ax4b, 'Month', 'FontWeight', 'bold', 'FontSize', 11);
title(ax4b, 'Peak Irradiance & Daylight Duration', 'FontSize', 12, 'FontWeight', 'bold');
set(ax4b, 'XTick', 1:12, 'XTickLabel', season_names);
grid(ax4b, 'on');
ax4b.GridAlpha = 0.3;

sgtitle(sprintf('Energy Content Analysis — %s', Geo.Name), ...
    'FontSize', 13, 'FontWeight', 'bold');
exportgraphics(fig4, fullfile(res_dir, 'Fig04_Daily_Energy.png'), 'Resolution', 300);
close(fig4);
fprintf('  ✓ Fig04_Daily_Energy.png\n\n');

%% ── SAVE SUMMARY TABLE ────────────────────────────────────────────────────
fprintf('Creating summary table...\n');

summary_table = table( ...
    season_names', ...
    daily_energy, ...
    daily_peak, ...
    repmat(Geo.Lat, 12, 1), ...
    'VariableNames', {'Month', 'Daily_Energy_Wh_m2', 'Peak_GHI_W_m2', 'Latitude_deg'});

writetable(summary_table, fullfile(res_dir, 'IrradianceProfileSummary.csv'));
fprintf('  ✓ IrradianceProfileSummary.csv\n\n');

%% ── SUMMARY STATISTICS ───────────────────────────────────────────────────
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  IRRADIANCE ANALYSIS SUMMARY — %s\n', Geo.Name);
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  Location    : %.2f°N, %.2f°E\n', Geo.Lat, Geo.Lon);
fprintf('  Data points : %d records (%.1f days)\n', height(solar_data), height(solar_data)/86400);
fprintf('\n  ANNUAL STATISTICS:\n');
fprintf('  %-8s | %10s | %10s | %10s\n', 'Month', 'Energy(Wh)', 'Peak(W)', 'Hours');
fprintf('  %s\n', repmat('-',1,45));
for d = 1:12
    fprintf('  %-8s | %10.0f | %10.0f | %10.1f\n', ...
        season_names{d}, daily_energy(d), daily_peak(d), daily_sun_hours(d));
end
fprintf('  %s\n', repmat('-',1,45));
fprintf('  Annual    | %10.0f | %10.0f | %10.1f\n', ...
    mean(daily_energy)*365, mean(daily_peak), mean(daily_sun_hours)*365);
fprintf('═══════════════════════════════════════════════════════════════\n\n');

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  ANALYSIS COMPLETE                                           ║\n');
fprintf('║  Grafik ve tablo kaydedildi:                                 ║\n');
fprintf('║    %s\n', res_dir);
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% ── BİTİŞ ────────────────────────────────────────────────────────────────
fprintf('  Oluşturulan dosyalar:\n');
out_files = dir(fullfile(res_dir, '*'));
for kk = 1:numel(out_files)
    if ~out_files(kk).isdir
        fprintf('    ✓ %s\n', out_files(kk).name);
    end
end
fprintf('\n');
approved = true;  % Onay RunAll.m tarafından toplu olarak alınır

end  % function