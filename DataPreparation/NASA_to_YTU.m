function NASA_to_YTU(nasa_csv_path, output_csv_path, options)
% NASA_TO_YTU  NASA POWER CSV formatındaki saatlik veriyi YTU (PVGIS) CSV
%              formatına dönüştürür.
%
% KULLANIM:
%   NASA_to_YTU('YTU_NASA_Hourly.csv', 'output_YTU.csv')
%   NASA_to_YTU('YTU_NASA_Hourly.csv', 'output_YTU.csv', options)
%
% GİRDİ FORMATI (NASA POWER CSV):
%   - Başlık bloğu: -BEGIN HEADER- ... -END HEADER- (14 satır)
%   - Kolon sırası: YEAR, MO, DY, HR,
%                   ALLSKY_SFC_SW_DWN, T2M, WS10M, ALLSKY_SFC_SW_DIFF, SZA
%   - Eksik veri değeri: -999
%
% ÇIKTI FORMATI (YTU / PVGIS-benzeri CSV):
%   Satır 1  : Latitude
%   Satır 2  : Longitude
%   Satır 3  : Elevation
%   Satır 4  : Radiation database
%   Satır 5-8: Boş / eğim / azimut
%   Satır 9  : time,Gb(i),Gd(i),Gr(i),H_sun,T2m,WS10m,Int
%   Satır 10+: 20240101:0010, GHI, Gd, 0.0, 0.0, T2m, WS10m, 0.0
%
% KOLON EŞLEŞTİRME:
%   ALLSKY_SFC_SW_DWN  -> Gb(i)   GHI (küresel yatay ışınım)
%   ALLSKY_SFC_SW_DIFF -> Gd(i)   Difüz ışınım
%   T2M                -> T2m     2m sıcaklık
%   WS10M              -> WS10m   10m rüzgar hızı
%   Gr(i), H_sun, Int  -> 0.0     (NASA verisi yok)
%
% SEÇENEKLER (options struct, isteğe bağlı):
%   options.elevation       - Rakım (m),             varsayılan: header'dan okunur
%   options.slope           - Panel eğim açısı (°),   varsayılan: 0
%   options.azimuth         - Azimut açısı (°),       varsayılan: 0
%   options.radiation_db    - Veritabanı adı,          varsayılan: 'NASA-POWER'
%   options.time_offset_min - Zaman damgası dk ofseti, varsayılan: 10
%   options.header_lines    - NASA header satır sayısı, varsayılan: 14

% -------------------------------------------------------------------------
% Varsayılan seçenekler
% -------------------------------------------------------------------------
if nargin < 3, options = struct(); end
if ~isfield(options, 'elevation'),       options.elevation       = NaN;          end
if ~isfield(options, 'slope'),           options.slope           = 0;            end
if ~isfield(options, 'azimuth'),         options.azimuth         = 0;            end
if ~isfield(options, 'radiation_db'),    options.radiation_db    = 'NASA-POWER'; end
if ~isfield(options, 'time_offset_min'), options.time_offset_min = 10;           end
if ~isfield(options, 'header_lines'),    options.header_lines    = 13;           end

% -------------------------------------------------------------------------
% 1. NASA Header'ından koordinat ve rakım bilgisini oku
% -------------------------------------------------------------------------
fprintf('[1/4] NASA header okunuyor...\n');

fid_in = fopen(nasa_csv_path, 'r');
if fid_in == -1
    error('Dosya açılamadı: %s', nasa_csv_path);
end

lat  = NaN;
lon  = NaN;
elev = options.elevation;

for i = 1:options.header_lines
    line = fgetl(fid_in);
    if ~ischar(line), break; end

    % "Location: Latitude 41.0514 Longitude 29.0106"
    if contains(line, 'Latitude') && contains(line, 'Longitude')
        tok = regexp(line, 'Latitude\s+([-\d.]+)\s+Longitude\s+([-\d.]+)', 'tokens');
        if ~isempty(tok)
            lat = str2double(tok{1}{1});
            lon = str2double(tok{1}{2});
        end
    end

    % "Elevation from MERRA-2: Average ... = 59.56 meters"
    if contains(line, 'Elevation') && contains(line, 'meters') && isnan(elev)
        tok = regexp(line, '=\s*([\d.]+)\s*meters', 'tokens');
        if ~isempty(tok)
            elev = round(str2double(tok{1}{1}));
        end
    end
end
fclose(fid_in);

if isnan(lat) || isnan(lon)
    warning('Koordinat header''dan okunamadı, 0,0 kullanılıyor.');
    lat = 0; lon = 0;
end
if isnan(elev), elev = 0; end

fprintf('   Enlem  : %.4f\n', lat);
fprintf('   Boylam : %.4f\n', lon);
fprintf('   Rakım  : %d m\n', elev);

% -------------------------------------------------------------------------
% 2. Veriyi oku (header'dan sonraki satırlar)
% -------------------------------------------------------------------------
fprintf('[2/4] Veri okunuyor...\n');

data = readtable(nasa_csv_path, ...
                 'NumHeaderLines', options.header_lines, ...
                 'ReadVariableNames', true);

% Kolon adlarını küçük harfe çevir (eşleştirme için)
col = lower(data.Properties.VariableNames);

idx_year = find(strcmp(col, 'year'),  1);
idx_mo   = find(strcmp(col, 'mo'),    1);
idx_dy   = find(strcmp(col, 'dy'),    1);
idx_hr   = find(strcmp(col, 'hr'),    1);
idx_ghi  = find(contains(col, 'allsky_sfc_sw_dwn'),  1);
idx_t2m  = find(strcmp(col, 't2m'),   1);
idx_ws   = find(strcmp(col, 'ws10m'), 1);
idx_diff = find(contains(col, 'allsky_sfc_sw_diff'), 1);

% Kolon bulunamazsa sıra ile al
if isempty(idx_year), idx_year = 1; end
if isempty(idx_mo),   idx_mo   = 2; end
if isempty(idx_dy),   idx_dy   = 3; end
if isempty(idx_hr),   idx_hr   = 4; end
if isempty(idx_ghi),  idx_ghi  = 5; end
if isempty(idx_t2m),  idx_t2m  = 6; end
if isempty(idx_ws),   idx_ws   = 7; end
if isempty(idx_diff), idx_diff = 8; end

year     = data{:, idx_year};
mo       = data{:, idx_mo};
dy       = data{:, idx_dy};
hr       = data{:, idx_hr};
ghi      = data{:, idx_ghi};
t2m      = data{:, idx_t2m};
ws       = data{:, idx_ws};
diff_rad = data{:, idx_diff};

% -999 → 0  (NASA eksik veri kodu)
ghi(ghi < 0)           = 0;
diff_rad(diff_rad < 0) = 0;

% NaN satırlarını temizle
valid = ~isnan(year) & ~isnan(mo) & ~isnan(dy) & ~isnan(hr) & ~isnan(ghi);
year     = year(valid);
mo       = mo(valid);
dy       = dy(valid);
hr       = hr(valid);
ghi      = ghi(valid);
t2m      = t2m(valid);
ws       = ws(valid);
diff_rad = diff_rad(valid);

n_rows = length(ghi);
fprintf('   Toplam satır: %d\n', n_rows);

% -------------------------------------------------------------------------
% 3. Zaman damgaları oluştur: YYYYMMDD:HHMM
% -------------------------------------------------------------------------
fprintf('[3/4] Zaman damgaları oluşturuluyor...\n');

time_str = cell(n_rows, 1);
for i = 1:n_rows
    time_str{i} = sprintf('%04d%02d%02d:%02d%02d', ...
                          year(i), mo(i), dy(i), hr(i), options.time_offset_min);
end

% -------------------------------------------------------------------------
% 4. YTU formatında CSV yaz
% -------------------------------------------------------------------------
fprintf('[4/4] CSV yazılıyor: %s\n', output_csv_path);

fid_out = fopen(output_csv_path, 'w');
if fid_out == -1
    error('Çıktı dosyası açılamadı: %s', output_csv_path);
end

% --- Metadata başlıkları ---
fprintf(fid_out, 'Latitude (decimal degrees):\t%.3f\n',  lat);
fprintf(fid_out, 'Longitude (decimal degrees):\t%.3f\n', lon);
fprintf(fid_out, 'Elevation (m):\t%d\n',                 elev);
fprintf(fid_out, 'Radiation database:\t%s\n',             options.radiation_db);
fprintf(fid_out, '\n');
fprintf(fid_out, '\n');
fprintf(fid_out, 'Slope: %d deg.\n',   options.slope);
fprintf(fid_out, 'Azimuth: %d deg.\n', options.azimuth);

% --- Kolon başlıkları ---
fprintf(fid_out, 'time,Gb(i),Gd(i),Gr(i),H_sun,T2m,WS10m,Int\n');

% --- Veri satırları ---
for i = 1:n_rows
    fprintf(fid_out, '%s,%.2f,%.2f,0.0,0.0,%.2f,%.2f,0.0\n', ...
            time_str{i}, ghi(i), diff_rad(i), t2m(i), ws(i));
end

fclose(fid_out);

fprintf('\nDönüşüm tamamlandı!\n');
fprintf('Çıktı dosyası : %s\n', output_csv_path);
fprintf('Toplam satır  : %d\n', n_rows);

end % function