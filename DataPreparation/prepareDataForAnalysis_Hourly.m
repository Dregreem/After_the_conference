%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  prepareDataForAnalysis_Hourly.m  (güncellenmiş)                     ║
%% ║  SAATLİK Veri Hazırlama Fonksiyonu                                    ║
%% ║                                                                       ║
%% ║  Değişiklikler:                                                       ║
%% ║    • T2m / WS10m artık doğrudan YTU CSV'den okunuyor                 ║
%% ║      (ayrı *_MonthlyAvg.csv gerekmez)                                ║
%% ║    • getGeoConfig koordinatları CSV'den otomatik çekiyor             ║
%% ║    • Daha açıklayıcı hata mesajları                                  ║
%% ║                                                                       ║
%% ║  Kullanım:                                                            ║
%% ║    PreparedData = prepareDataForAnalysis_Hourly('YTU_FROM_NASA');     ║
%% ║    PreparedData = prepareDataForAnalysis_Hourly('YTU');               ║
%% ║    → Çıktı: prepared_data_HOURLY_<LOC>.mat                           ║
%% ╚══════════════════════════════════════════════════════════════════════╝

function PreparedData = prepareDataForAnalysis_Hourly(loc_name)

    if nargin < 1
        loc_name = 'YTU_FROM_NASA';
    end

    fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║  SAATLİK VERİ HAZIRLIĞI                                       ║\n');
    fprintf('║  Konum: %-52s║\n', loc_name);
    fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

    %% ── ADIM 1: Coğrafi Bilgi ──────────────────────────────────────────
    fprintf('ADIM 1: Coğrafi bilgi...\n');
    try
        Geo = getGeoConfig(loc_name);
        if ~isfield(Geo, 'Alt'), Geo.Alt = 0; end  % eski getGeoConfig uyumluluğu
        fprintf('  ✓ %s | %.3f°N %.3f°E | UTC+%d | %dm\n\n', ...
            Geo.Name, Geo.Lat, Geo.Lon, Geo.TZ, Geo.Alt);
    catch ME
        fprintf('  ⚠ getGeoConfig hatası: %s\n', ME.message);
        fprintf('  → Varsayılan İstanbul koordinatları kullanılıyor\n\n');
        Geo.Name = loc_name;  Geo.Lat = 41.05;
        Geo.Lon  = 29.01;     Geo.TZ  = 3;    Geo.Alt = 60;
    end

    %% ── ADIM 2: YTU CSV Dosyasını Bul ve Oku ──────────────────────────
    fprintf('ADIM 2: YTU/PVGIS CSV okunuyor...\n');
    csv_filename = sprintf('%s_Hourly.csv', upper(loc_name));

    search_paths = {
        csv_filename,
        fullfile(pwd, csv_filename),
        fullfile(pwd, '..', csv_filename),
        fullfile('DataPreparation', csv_filename),
        fullfile(pwd, '..', 'DataPreparation', csv_filename)
    };

    csv_filepath = '';
    for p = 1:numel(search_paths)
        if isfile(search_paths{p})
            csv_filepath = search_paths{p};
            break;
        end
    end

    if isempty(csv_filepath)
        error(['CSV dosyası bulunamadı: %s\n' ...
               'Aranan yollar:\n  %s\n\n' ...
               'İpucu: NASA_to_YTU() ile önce dönüşüm yapın.'], ...
               csv_filename, strjoin(search_paths, '\n  '));
    end
    fprintf('  ✓ Bulundu: %s\n', csv_filepath);

    %% ── ADIM 2a: CSV başlığından koordinat güncelle ─────────────────────
    Geo = updateGeoFromCSV(Geo, csv_filepath);

    %% ── ADIM 2b: Veri satırlarını oku ───────────────────────────────────
    % YTU formatı: 8 satır metadata + 1 başlık satırı → veri
    raw = readtable(csv_filepath, ...
        'NumHeaderLines', 8, ...
        'ReadVariableNames', true, ...
        'VariableNamingRule', 'preserve');

    % 'time' kolonunun var olduğunu kontrol et
    if ~ismember('time', raw.Properties.VariableNames)
        error(['CSV formatı beklenmiyor. ''time'' kolonu bulunamadı.\n' ...
               'Mevcut kolonlar: %s'], ...
               strjoin(raw.Properties.VariableNames, ', '));
    end

    n_records_raw = height(raw);
    fprintf('  ✓ %d saatlik kayıt okundu\n', n_records_raw);
    fprintf('  ✓ Kolonlar: %s\n\n', strjoin(raw.Properties.VariableNames, ', '));

    %% ── ADIM 3: Ay ve Saat bilgisini zaman damgasından çıkar ───────────
    fprintf('ADIM 3: Zaman damgaları ayrıştırılıyor...\n');
    % Format: YYYYMMDD:HHMM  örn. 20240101:0010
    time_str = raw.('time');
    time_char = char(time_str);  % cell/string/char hepsini destekler

    n_raw = height(raw);
    month_raw = zeros(n_raw, 1);
    hour_raw  = zeros(n_raw, 1);

    for ii = 1:n_raw
        row    = time_char(ii, :);
        mo_val = str2double(row(5:6));
        hr_val = str2double(row(10:11));
        month_raw(ii) = max(1,  min(12, round(mo_val)));
        hour_raw(ii)  = max(0,  min(23, round(hr_val)));
    end

    raw.Month = month_raw;
    raw.Hour  = hour_raw;
    fprintf('  ✓ Ay aralığı: %d–%d | Saat aralığı: %d–%d\n\n', ...
        min(month_raw), max(month_raw), min(hour_raw), max(hour_raw));

    %% ── ADIM 4: T2m / WS10m LUT — DOĞRUDAN CSV'DEN ────────────────────
    fprintf('ADIM 4: T2m / WS10m aylık saatlik ortalamalar hesaplanıyor...\n');

    T2m_lut = ones(12, 24) * 20.0;   % varsayılan
    WS_lut  = ones(12, 24) * 1.5;

    has_T2m  = ismember('T2m',   raw.Properties.VariableNames);
    has_WS   = ismember('WS10m', raw.Properties.VariableNames);

    if has_T2m || has_WS
        for m = 1:12
            for h = 0:23
                mask = (raw.Month == m) & (raw.Hour == h);
                if ~any(mask), continue; end
                if has_T2m
                    T2m_lut(m, h+1) = mean(raw.T2m(mask), 'omitnan');
                end
                if has_WS
                    WS_lut(m, h+1) = max(0.5, mean(raw.WS10m(mask), 'omitnan'));
                end
            end
        end
        fprintf('  ✓ T2m LUT [12×24] — kaynak: CSV T2m kolonu\n');
        fprintf('  ✓ WS  LUT [12×24] — kaynak: CSV WS10m kolonu\n');
        fprintf('  ✓ Yıllık ort. T2m  : %.1f°C\n', mean(T2m_lut(:)));
        fprintf('  ✓ Yıllık ort. WS10m: %.2f m/s\n\n', mean(WS_lut(:)));
        has_temp_data = true;
    else
        fprintf('  ⚠ CSV''de T2m / WS10m kolonu bulunamadı\n');
        fprintf('  → Varsayılan değerler: T2m=20°C, WS=1.5 m/s\n\n');
        has_temp_data = false;
    end

    %% ── ADIM 5: İrradiance kolonlarını standartlaştır ──────────────────
    fprintf('ADIM 5: İrradiance verisi standartlaştırılıyor...\n');

    % Kolon eşleştirme (YTU formatı → iç format)
    col_map = {'Gb(i)', 'Gbi'; 'Gd(i)', 'Gdi'};
    for k = 1:size(col_map, 1)
        src = col_map{k,1};
        dst = col_map{k,2};
        if ismember(src, raw.Properties.VariableNames) && ~ismember(dst, raw.Properties.VariableNames)
            raw.(dst) = raw.(src);
        end
    end

    % GHI = Gb(i) + Gd(i)  eğer ayrı varsa
    if ~ismember('GHI', raw.Properties.VariableNames)
        gbi = zeros(height(raw),1);
        gdi = zeros(height(raw),1);
        if ismember('Gbi', raw.Properties.VariableNames), gbi = raw.Gbi; end
        if ismember('Gdi', raw.Properties.VariableNames), gdi = raw.Gdi; end
        raw.GHI = max(0, gbi + gdi);
    end

    fprintf('  ✓ GHI — min:%.1f, mak:%.1f, ort:%.1f W/m²\n\n', ...
        min(raw.GHI), max(raw.GHI), mean(raw.GHI));

    %% ── ADIM 6: Saniye bazına genişlet (12 × 86400) ─────────────────────
    fprintf('ADIM 6: Saatlik veri 1-saniyelik temsilci güne genişletiliyor...\n');

    n_total = 86400 * 12;

    Month_arr  = zeros(n_total, 1, 'single');
    GHI_arr    = zeros(n_total, 1, 'single');
    Beam_arr   = zeros(n_total, 1, 'single');
    DHI_arr    = zeros(n_total, 1, 'single');
    SunEl_arr  = zeros(n_total, 1, 'single');
    SunAz_arr  = zeros(n_total, 1, 'single');
    TimeS_arr  = zeros(n_total, 1, 'single');

    lat_r   = deg2rad(Geo.Lat);
    lon_deg = Geo.Lon;
    tz      = Geo.TZ;

    rep_days = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344];

    has_gbi  = ismember('Gbi',  raw.Properties.VariableNames);
    has_gdi  = ismember('Gdi',  raw.Properties.VariableNames);
    has_hsun = ismember('H_sun', raw.Properties.VariableNames);

    for m = 1:12
        month_rows = raw(raw.Month == m, :);
        n_hours    = height(month_rows);

        % Astronomik parametreler (temsili gün)
        n_jul = rep_days(m);
        B_ang = 2*pi*(n_jul - 1)/365;
        EoT   = 229.18 * (0.000075 + 0.001868*cos(B_ang) - 0.032077*sin(B_ang) ...
                        - 0.014615*cos(2*B_ang) - 0.04089*sin(2*B_ang));
        decl  = deg2rad(23.45 * sin(deg2rad(360*(284+n_jul)/365)));

        for h = 1:24
            h_idx = h:24:n_hours;

            % Aylık ortalama irradiance (bu saat için tüm günler)
            if has_gbi
                gbi_avg = mean(max(0, month_rows.Gbi(h_idx)));
            else
                gbi_avg = 0;
            end
            if has_gdi
                gdi_avg = mean(max(0, month_rows.Gdi(h_idx)));
            else
                gdi_avg = 0;
            end
            ghi_avg = mean(max(0, month_rows.GHI(h_idx)));

            % Güneş yüksekliği
            if has_hsun && any(month_rows.H_sun(h_idx) > 0)
                el_deg = mean(month_rows.H_sun(h_idx));
            else
                lst_corr = (h - 0.5) + EoT/60 + lon_deg/15 - tz;
                ha_mid   = deg2rad(15*(lst_corr - 12));
                sin_el   = sin(lat_r)*sin(decl) + cos(lat_r)*cos(decl)*cos(ha_mid);
                el_deg   = rad2deg(asin(max(-1, min(1, sin_el))));
            end

            % Azimut
            lst_mid  = (h - 0.5) + EoT/60 + lon_deg/15 - tz;
            ha_mid   = deg2rad(15*(lst_mid - 12));
            sin_el_r = sin(deg2rad(el_deg));
            cos_el_r = cos(deg2rad(el_deg));
            if abs(cos_el_r) < 1e-6
                az_deg = 180;
            else
                cos_az = (sin(decl) - sin_el_r*sin(lat_r)) / (cos_el_r*cos(lat_r));
                cos_az = max(-1, min(1, cos_az));
                az_deg = rad2deg(acos(cos_az));
                if sin(ha_mid) > 0, az_deg = 360 - az_deg; end
            end

            % Array'e yaz
            seg_s = (m-1)*86400 + (h-1)*3600 + 1;
            seg_e = seg_s + 3599;
            t_vec = single((h-1)*3600 : (h-1)*3600+3599)';

            Month_arr(seg_s:seg_e) = m;
            GHI_arr(seg_s:seg_e)   = ghi_avg;
            Beam_arr(seg_s:seg_e)  = gbi_avg;
            DHI_arr(seg_s:seg_e)   = gdi_avg;
            SunEl_arr(seg_s:seg_e) = el_deg;
            SunAz_arr(seg_s:seg_e) = az_deg;
            TimeS_arr(seg_s:seg_e) = t_vec;
        end

        fprintf('  Ay %2d/12 tamamlandı\n', m);
    end

    solar_data = table(Month_arr, GHI_arr, Beam_arr, DHI_arr, ...
        SunEl_arr, SunAz_arr, TimeS_arr, ...
        'VariableNames', {'Month','GHI','Beam','DHI', ...
                          'Sun_Elevation','Sun_Azimuth','Time_in_Seconds'});

    fprintf('  ✓ Genişletildi: %d saat → %d saniyelik kayıt\n\n', ...
        n_records_raw, height(solar_data));

    %% ── ADIM 7: Paketleme ve Kaydetme ──────────────────────────────────
    fprintf('ADIM 7: Kaydediliyor...\n');

    PreparedData = struct();
    PreparedData.location      = loc_name;
    PreparedData.Geo           = Geo;
    PreparedData.solar_data    = solar_data;
    PreparedData.T2m_lut       = T2m_lut;
    PreparedData.WS_lut        = WS_lut;
    PreparedData.season_names  = {'Jan','Feb','Mar','Apr','May','Jun', ...
                                   'Jul','Aug','Sep','Oct','Nov','Dec'};
    PreparedData.month_lengths = [31,28,31,30,31,30,31,31,30,31,30,31];
    PreparedData.has_temp_data = has_temp_data;
    PreparedData.timestamp     = datetime('now');
    PreparedData.n_records     = height(solar_data);
    PreparedData.data_type     = 'HOURLY_AVERAGED';
    PreparedData.source_csv    = csv_filepath;

    output_file = sprintf('prepared_data_HOURLY_%s.mat', upper(loc_name));
    save(output_file, 'PreparedData', '-v7.3');
    fprintf('  ✓ Kaydedildi: %s\n\n', output_file);

    %% ── ÖZET ────────────────────────────────────────────────────────────
    fprintf('════════════════════════════════════════════════════════════════\n');
    fprintf('  HAZIRLIK ÖZETİ — %s\n', loc_name);
    fprintf('════════════════════════════════════════════════════════════════\n');
    fprintf('  Kaynak CSV    : %s\n',  csv_filepath);
    fprintf('  Konum         : %s (%.3f°N, %.3f°E)\n', Geo.Name, Geo.Lat, Geo.Lon);
    fprintf('  Ham kayıt     : %d saat\n', n_records_raw);
    fprintf('  Çıktı kayıt   : %d saniye (12 × 86400)\n', height(solar_data));
    fprintf('  T2m kaynağı   : %s\n', iif(has_temp_data, 'CSV (gerçek veri)', 'Varsayılan 20°C'));
    fprintf('  WS10m kaynağı : %s\n', iif(has_temp_data, 'CSV (gerçek veri)', 'Varsayılan 1.5 m/s'));
    fprintf('  Ort. T2m      : %.1f°C\n', mean(T2m_lut(:)));
    fprintf('  Ort. WS10m    : %.2f m/s\n', mean(WS_lut(:)));
    fprintf('  Çıktı dosyası : %s\n', output_file);
    fprintf('════════════════════════════════════════════════════════════════\n\n');

end

%% ── Yardımcı: CSV başlığından Geo güncelle ──────────────────────────────
function Geo = updateGeoFromCSV(Geo, csv_path)
    fid = fopen(csv_path, 'r');
    if fid == -1, return; end
    for k = 1:8
        line = fgetl(fid);
        if ~ischar(line), break; end
        if contains(lower(line), 'latitude')
            tok = regexp(line, '([-\d.]+)\s*$', 'tokens');
            if ~isempty(tok), Geo.Lat = str2double(tok{1}{1}); end
        elseif contains(lower(line), 'longitude')
            tok = regexp(line, '([-\d.]+)\s*$', 'tokens');
            if ~isempty(tok), Geo.Lon = str2double(tok{1}{1}); end
        elseif contains(lower(line), 'elevation')
            tok = regexp(line, '([\d.]+)', 'tokens');
            if ~isempty(tok), Geo.Alt = round(str2double(tok{1}{1})); end
        end
    end
    fclose(fid);
end

%% ── Yardımcı: if-else seçici ────────────────────────────────────────────
function y = iif(cond, a, b)
    if cond, y = a; else, y = b; end
end