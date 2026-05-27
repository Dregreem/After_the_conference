%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  DataFormatSelector.m                                                ║
%% ║  Veri Türü Açılayıcısı ve Seçici                                      ║
%% ║                                                                       ║
%% ║  Kullanım: Uygun .mat dosyasını yükle ve veri türünü algıla           ║
%% ║                                                                       ║
%% ║  Fonksiyonlar:                                                        ║
%% ║    1. loadPreparedData(location) — Otomatik yükleme                   ║
%% ║    2. validateDataFormat(PreparedData) — Format kontrolü              ║
%% ║    3. getDataInfo(PreparedData) — Bilgi tablosu                       ║
%% ║                                                                       ║
%% ╚══════════════════════════════════════════════════════════════════════╝

%% ─────────────────────────────────────────────────────────────────────────
%  FONKSİYON 1: Otomatik Yükleme
%% ─────────────────────────────────────────────────────────────────────────

function PreparedData = loadPreparedData(location)
    % Hazırlanmış veri dosyasını otomatik yükle
    % Önce HOURLY, sonra DAILY arar
    %
    % INPUT:  location → 'ISTANBUL', 'ANKARA', etc.
    % OUTPUT: PreparedData struct
    
    fprintf('Veri yükleniyor: %s\n', upper(location));
    
    % İlk olarak HOURLY dene
    file_hourly = sprintf('prepared_data_HOURLY_%s.mat', upper(location));
    if isfile(file_hourly)
        fprintf('  ✓ Yüklendi: %s (HOURLY)\n', file_hourly);
        load(file_hourly, 'PreparedData');
        return;
    end
    
    % Sonra DAILY dene
    file_daily = sprintf('prepared_data_DAILY_%s.mat', upper(location));
    if isfile(file_daily)
        fprintf('  ✓ Yüklendi: %s (DAILY)\n', file_daily);
        load(file_daily, 'PreparedData');
        return;
    end
    
    % Eski format dene (geriye uyumluluk)
    file_old = sprintf('prepared_data_%s.mat', upper(location));
    if isfile(file_old)
        fprintf('  ⚠ Eski format: %s\n', file_old);
        load(file_old, 'PreparedData');
        return;
    end
    
    error('  ✗ Dosya bulunamadı: %s\n     Aradığım: %s, %s, %s', ...
        location, file_hourly, file_daily, file_old);
end

%% ─────────────────────────────────────────────────────────────────────────
%  FONKSİYON 2: Format Kontrolü
%% ─────────────────────────────────────────────────────────────────────────

function is_valid = validateDataFormat(PreparedData)
    % Yüklenen verilerin gerekli alanları var mı kontrol et
    
    is_valid = true;
    required_fields = {'location', 'Geo', 'solar_data', 'T2m_lut', ...
                       'WS_lut', 'data_type'};
    
    for f = 1:length(required_fields)
        field = required_fields{f};
        if ~isfield(PreparedData, field)
            fprintf('  ✗ Alan eksik: %s\n', field);
            is_valid = false;
        end
    end
    
    if is_valid
        fprintf('  ✓ Format geçerli\n');
    end
end

%% ─────────────────────────────────────────────────────────────────────────
%  FONKSİYON 3: Bilgi Tablosu
%% ─────────────────────────────────────────────────────────────────────────

function info = getDataInfo(PreparedData)
    % PreparedData hakkında bilgi tablosu
    
    info = struct();
    info.location = PreparedData.location;
    info.latitude = PreparedData.Geo.Lat;
    info.longitude = PreparedData.Geo.Lon;
    info.timezone = PreparedData.Geo.TZ;
    
    info.data_type = PreparedData.data_type;
    info.n_records = PreparedData.n_records;
    
    if isfield(PreparedData, 'n_days')
        info.n_days = PreparedData.n_days;
    else
        info.n_days = round(PreparedData.n_records / 86400);
    end
    
    info.has_temp_data = PreparedData.has_temp_data;
    info.T2m_lut_size = size(PreparedData.T2m_lut);
    info.WS_lut_size = size(PreparedData.WS_lut);
    
    info.timestamp = string(PreparedData.timestamp);
    
    if isfield(PreparedData, 'interpolation_method')
        info.interpolation = PreparedData.interpolation_method;
    else
        info.interpolation = 'N/A';
    end
end

%% ─────────────────────────────────────────────────────────────────────────
%  FONKSİYON 4: Rapor Yazdır
%% ─────────────────────────────────────────────────────────────────────────

function printDataReport(PreparedData)
    % Hazırlanmış veri hakkında detaylı rapor
    
    fprintf('\n╔════════════════════════════════════════════════════════════════╗\n');
    fprintf('║  VERİ RAPORU                                                   ║\n');
    fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');
    
    info = getDataInfo(PreparedData);
    
    fprintf('  KONUM:\n');
    fprintf('    Adı        : %s\n', info.location);
    fprintf('    Koordinat  : %.2f°N, %.2f°E (UTC%+d)\n', ...
        info.latitude, info.longitude, info.timezone);
    
    fprintf('\n  VERİ YAPISI:\n');
    fprintf('    Türü       : %s\n', info.data_type);
    fprintf('    Kayıtlar   : %d\n', info.n_records);
    fprintf('    Gün        : ~%d\n', info.n_days);
    fprintf('    Zaman Eti. : %s\n', info.timestamp);
    
    fprintf('\n  SICAKLIK/RÜZGAR:\n');
    fprintf('    Durumu     : %s\n', iif(info.has_temp_data, 'MEVCUT', 'VARSAYILAN'));
    fprintf('    T2m LUT    : %s (ay × saat)\n', mat2str(info.T2m_lut_size));
    fprintf('    WS LUT     : %s (ay × saat)\n', mat2str(info.WS_lut_size));
    fprintf('    İnterpolasyon: %s\n', info.interpolation);
    
    fprintf('\n  IRRADIANCE:\n');
    fprintf('    Kayıt Sayı : %d\n', height(PreparedData.solar_data));
    fprintf('    Kolonlar   : %s\n', strjoin(PreparedData.solar_data.Properties.VariableNames, ', '));
    
    fprintf('\n');
end

%% ─────────────────────────────────────────────────────────────────────────
%  YARDIMCI FONKSİYON
%% ─────────────────────────────────────────────────────────────────────────

function y = iif(condition, true_val, false_val)
    if condition
        y = true_val;
    else
        y = false_val;
    end
end
