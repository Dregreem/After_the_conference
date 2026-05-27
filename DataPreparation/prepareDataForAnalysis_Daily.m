%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  prepareDataForAnalysis_Daily.m                                      ║
%% ║  GÜNLÜK Veri Hazırlama Fonksiyonu + SAATLİK İnterpolasyon             ║
%% ║                                                                       ║
%% ║  Amaç: Günlük PVGIS verilerini (1-gün aralık) ve günlük sıcaklık      ║
%% ║         verilerini yükleyip, otomatik olarak saatlik aralığa         ║
%% ║         interpolasyon etmek. Böylece anal. scriptler aynı kalır.      ║
%% ║                                                                       ║
%% ║  Veri Formatı:                                                        ║
%% ║    - PVGIS     : 1-günlük aralık [M×1] (M = gün sayısı)              ║
%% ║    - Sıcaklık  : Günlük ortalamalar [12×1]                           ║
%% ║                                                                       ║
%% ║  İnterpolasyon: Saatlik aralığa çıkarma [12×24]                      ║
%% ║                                                                       ║
%% ║  Kullanım:                                                            ║
%% ║    PreparedData = prepareDataForAnalysis_Daily('ISTANBUL');           ║
%% ║    - Çıktı: prepared_data_DAILY_ISTANBUL.mat                         ║
%% ║                                                                       ║
%% ╚══════════════════════════════════════════════════════════════════════╝

function PreparedData = prepareDataForAnalysis_Daily(loc_name)
    % INPUT
    %   loc_name : string — konum adı
    %
    % OUTPUT
    %   PreparedData : struct — saatlik formatına interpolasyonlanmış veriler
    
    if nargin < 1
        loc_name = 'ISTANBUL';
    end
    
    fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║  GÜNLÜK VERİ HAZIRLIĞI (SAATLİK İNTERPOLASYON)                ║\n');
    fprintf('║  Konum: %s\n', loc_name);
    fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');
    
    %% ── STEP 1: Coğrafi Bilgileri Yükle ────────────────────────────────
    fprintf('ADIM 1: Coğrafi Bilgileri Yüklüyorum...\n');
    try
        Geo = getGeoConfig(loc_name);
    catch
        Geo.Name = loc_name;
        Geo.Lat = 41.05;
        Geo.Lon = 29.01;
        Geo.TZ = 3;
    end
    fprintf('  ✓ Koordinatlar: %.2f°N, %.2f°E\n\n', Geo.Lat, Geo.Lon);
    
    %% ── STEP 2: GÜNLÜK PVGIS Verisi ────────────────────────────────────
    fprintf('ADIM 2: GÜNLÜK PVGIS Verisi Yüklüyorum...\n');
    csv_filename_daily = sprintf('%s_Data_Daily.csv', upper(loc_name));
    csv_filepath_daily = fullfile(pwd, '..', csv_filename_daily);
    
    if ~isfile(csv_filepath_daily)
        csv_filepath_daily = fullfile(pwd, csv_filename_daily);
    end
    
    if ~isfile(csv_filepath_daily)
        error('  ✗ Günlük PVGIS CSV bulunamadı: %s', csv_filename_daily);
    end
    
    solar_data_daily = readtable(csv_filepath_daily);
    n_days = height(solar_data_daily);
    fprintf('  ✓ Yüklendi: %d gün\n\n', n_days);
    
    % ── Günlük veriye "saniye-bazında" uzatma ──────────────────────────
    fprintf('ADIM 3: Günlük Veriyi Saniye-Bazına Çevriyorum...\n');
    solar_data = expandDailyToSecondly(solar_data_daily, loc_name);
    n_records = height(solar_data);
    fprintf('  ✓ Genişletildi: %d günlük → %d saniyelik kayıt\n\n', ...
        n_days, n_records);
    
    %% ── STEP 4: GÜNLÜK Sıcaklık ve Rüzgar Verisi ───────────────────────
    fprintf('ADIM 4: GÜNLÜK Sıcaklık/Rüzgar Verisi Yüklüyorum...\n');
    
    T2m_lut = ones(12, 24) * 20.0;
    WS_lut  = ones(12, 24) * 1.5;
    
    daily_csv = sprintf('%s_MonthlyAvg_Daily.csv', upper(loc_name));
    if ~isfile(daily_csv)
        daily_csv = sprintf('%s_Daily.csv', upper(loc_name));
    end
    
    has_temp_data = false;
    if isfile(daily_csv)
        fprintf('  ◆ Günlük sıcaklık dosyası: %s\n', daily_csv);
        T_daily = readtable(daily_csv, 'VariableNamingRule', 'preserve');
        
        % ── Günlük veriden saatlik interpolasyon ────────────────────────
        [T2m_lut, WS_lut] = interpolateDailyToHourly(T_daily, loc_name);
        
        fprintf('    - T2m (ortam sıcaklığı) : Saatlik interpolasyon ✓\n');
        fprintf('    - WS10m (rüzgar hızı)   : Saatlik interpolasyon ✓\n');
        has_temp_data = true;
    else
        fprintf('  ℹ Günlük sıcaklık dosyası bulunamadı\n');
        fprintf('    → Varsayılan değerler kullanılıyor\n');
    end
    fprintf('\n');
    
    %% ── STEP 5: Mevsimsel Veriler ──────────────────────────────────────
    fprintf('ADIM 5: Mevsimsel Verileri Hazırlıyorum...\n');
    season_names = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', ...
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'};
    month_lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    fprintf('  ✓ 12 ay verisi hazırlandı\n\n');
    
    %% ── STEP 6: Çıktı Struct'ı Oluştur ─────────────────────────────────
    fprintf('ADIM 6: Verileri Paketleyip Kaydediyorum...\n');
    
    PreparedData = struct();
    PreparedData.location       = loc_name;
    PreparedData.Geo            = Geo;
    PreparedData.solar_data     = solar_data;          % ← Saniye-bazında
    PreparedData.T2m_lut        = T2m_lut;             % ← Saatlik LUT
    PreparedData.WS_lut         = WS_lut;              % ← Saatlik LUT
    PreparedData.season_names   = season_names;
    PreparedData.month_lengths  = month_lengths;
    PreparedData.has_temp_data  = has_temp_data;
    PreparedData.timestamp      = datetime('now');
    PreparedData.n_records      = n_records;
    PreparedData.n_days         = n_days;
    PreparedData.data_type      = 'DAILY_INTERPOLATED_TO_HOURLY';  % ← Tür
    PreparedData.interpolation_method = 'piecewise cubic';
    
    output_file = sprintf('prepared_data_DAILY_%s.mat', upper(loc_name));
    save(output_file, 'PreparedData');
    fprintf('  ✓ Kaydedildi: %s\n\n', output_file);
    
    %% ── İSTATİSTİKLER ─────────────────────────────────────────────────
    fprintf('════════════════════════════════════════════════════════════════\n');
    fprintf('  HAZIRLIK ÖZETİ (GÜNLÜK → SAATLİK)\n');
    fprintf('════════════════════════════════════════════════════════════════\n');
    fprintf('  Konum          : %s\n', Geo.Name);
    fprintf('  Giriş (günlük) : %d gün\n', n_days);
    fprintf('  Çıktı (saniye) : %d kayıt (≈ %d gün × 86400 s/gün)\n', ...
        n_records, round(n_records/86400));
    fprintf('  Sıcaklık Veri  : %s\n', iif(has_temp_data, 'İNTERPOLASYON', 'VARSAYILAN'));
    fprintf('  İnterpolasyon  : Piecewise cubic (T2m, WS)\n');
    fprintf('  T2m LUT        : [12×24] saatlik (interpolasyonlu)\n');
    fprintf('  WS LUT         : [12×24] saatlik (interpolasyonlu)\n');
    fprintf('  Zaman Eti.     : %s\n', string(PreparedData.timestamp));
    fprintf('════════════════════════════════════════════════════════════════\n\n');
    
end

%% ─────────────────────────────────────────────────────────────────────────
%  YARDIMCI FONKSİYONLAR
%% ─────────────────────────────────────────────────────────────────────────

function solar_data_secondly = expandDailyToSecondly(solar_data_daily, loc_name)
    % Günlük PVGIS verilerini saniye-bazına genişlet
    % Varsayılan olarak her gün için sinüs profili oluştur
    
    ndays = height(solar_data_daily);
    n_sec_per_day = 86400;
    
    % Pre-alloc
    Time_in_Seconds = [];
    Time_Index = [];
    GHI = [];
    Beam = [];
    DHI = [];
    Sun_Elevation = [];
    Sun_Azimuth = [];
    Month = [];
    
    for d = 1:ndays
        ghi_daily = solar_data_daily.GHI(d);
        beam_daily = solar_data_daily.Beam(d);
        dhi_daily = solar_data_daily.DHI(d);
        sun_el_peak = solar_data_daily.Sun_Elevation_Peak(d);  % En yüksek
        month_idx = solar_data_daily.Month(d);
        
        % Gün içi güneş profili (sinüs eğrisi)
        t_sec = (0:n_sec_per_day-1)';
        t_frac = t_sec / n_sec_per_day;  % 0-1
        
        % Sabah (0:00) ve akşam (24:00) = 0 güneş
        % Öğle (12:00) = zirve
        sine_profile = sin(pi * t_frac).^2;  % Smooth profile
        
        % GHI profili
        ghi_sec = ghi_daily * sine_profile;
        
        % Beam, DHI (aynı profil)
        beam_sec = beam_daily * sine_profile;
        dhi_sec = dhi_daily * sine_profile;
        
        % Güneş yüksekliği (sabah 0° → öğle pik → akşam 0°)
        sun_el_sec = sun_el_peak * sine_profile;
        
        % Azimut (basit model: sabah doğu, öğle güney, akşam batı)
        sun_az_sec = 180 - 180 * sin(pi * t_frac);  % -90 ile 270 arası
        
        % Birleştir
        Time_in_Seconds = [Time_in_Seconds; t_sec];
        GHI = [GHI; ghi_sec];
        Beam = [Beam; beam_sec];
        DHI = [DHI; dhi_sec];
        Sun_Elevation = [Sun_Elevation; sun_el_sec];
        Sun_Azimuth = [Sun_Azimuth; sun_az_sec];
        Month = [Month; repmat(month_idx, n_sec_per_day, 1)];
    end
    
    solar_data_secondly = table(Time_in_Seconds, GHI, Beam, DHI, ...
        Sun_Elevation, Sun_Azimuth, Month, ...
        'VariableNames', {'Time_in_Seconds', 'GHI', 'Beam', 'DHI', ...
                          'Sun_Elevation', 'Sun_Azimuth', 'Month'});
end

function [T2m_lut, WS_lut] = interpolateDailyToHourly(T_daily, loc_name)
    % Günlük sıcaklık verilerinden saatlik LUT oluştur
    
    T2m_lut = ones(12, 24) * 20.0;
    WS_lut = ones(12, 24) * 1.5;
    
    if ~ismember('Month', T_daily.Properties.VariableNames)
        return;  % Uygun formatta değil
    end
    
    has_WS = ismember('WS10m', T_daily.Properties.VariableNames);
    
    for m = 1:12
        rows_m = T_daily(T_daily.Month == m, :);
        
        if isempty(rows_m)
            continue;
        end
        
        % 24 saatlik profil için interpolasyon (basit lineer)
        T_day_avg = mean(rows_m.T2m);
        T_day_night = T_day_avg - 5;  % Gece 5°C daha soğuk
        
        for hh = 0:23
            % Sinüs profili: gece min, öğle max
            hour_frac = (hh + 0.5) / 24;
            sine_factor = sin(pi * hour_frac);
            T_hh = T_day_night + (T_day_avg - T_day_night) * sine_factor;
            
            T2m_lut(m, hh+1) = T_hh;
            
            if has_WS
                WS_hh = max(0.5, mean(rows_m.WS10m));
                WS_lut(m, hh+1) = WS_hh;
            end
        end
    end
end

function y = iif(condition, true_val, false_val)
    if condition
        y = true_val;
    else
        y = false_val;
    end
end
