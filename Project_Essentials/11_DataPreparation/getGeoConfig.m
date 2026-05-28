function Geo = getGeoConfig(loc_name)
%% GETGEOCONFIG  Konum adına göre coğrafi yapılandırma döndürür.
%
%  KULLANIM:
%    Geo = getGeoConfig('ISTANBUL')
%    Geo = getGeoConfig('YTU_FROM_NASA')
%
%  ÇIKTI (struct):
%    Geo.Name  — görünen ad
%    Geo.Lat   — enlem (decimal derece)
%    Geo.Lon   — boylam (decimal derece)
%    Geo.TZ    — UTC offset (saat)
%    Geo.Alt   — rakım (metre)
%
%  YENİ KONUM EKLEMEK:
%    Aşağıdaki switch bloğuna yeni bir case ekleyin.

switch upper(strtrim(loc_name))

    % ── YTU / NASA dönüştürülmüş veri ──────────────────────────────────
    case {'YTU_FROM_NASA', 'YTU_NASA', 'NASA_YTU'}
        Geo.Name = 'Istanbul (YTU - NASA)';
        Geo.Lat  = 41.051;
        Geo.Lon  = 29.011;
        Geo.TZ   = 3;
        Geo.Alt  = 60;

    % ── YTU orijinal (PVGIS) ────────────────────────────────────────────
    case {'YTU', 'YTU_HOURLY', 'YTU_PVGIS'}
        Geo.Name = 'Istanbul (YTU - PVGIS)';
        Geo.Lat  = 41.050;
        Geo.Lon  = 29.010;
        Geo.TZ   = 3;
        Geo.Alt  = 79;

    % ── İstanbul ────────────────────────────────────────────────────────
    case {'ISTANBUL', 'IST'}
        Geo.Name = 'Istanbul';
        Geo.Lat  = 41.013;
        Geo.Lon  = 28.955;
        Geo.TZ   = 3;
        Geo.Alt  = 40;

    % ── Ankara ──────────────────────────────────────────────────────────
    case {'ANKARA', 'ANK'}
        Geo.Name = 'Ankara';
        Geo.Lat  = 39.925;
        Geo.Lon  = 32.837;
        Geo.TZ   = 3;
        Geo.Alt  = 938;

    % ── Antalya ─────────────────────────────────────────────────────────
    case {'ANTALYA', 'ANT'}
        Geo.Name = 'Antalya';
        Geo.Lat  = 36.897;
        Geo.Lon  = 30.713;
        Geo.TZ   = 3;
        Geo.Alt  = 50;

    % ── İzmir ───────────────────────────────────────────────────────────
    case {'IZMIR', 'IZM'}
        Geo.Name = 'Izmir';
        Geo.Lat  = 38.418;
        Geo.Lon  = 27.129;
        Geo.TZ   = 3;
        Geo.Alt  = 30;

    % ── Konya ───────────────────────────────────────────────────────────
    case 'KONYA'
        Geo.Name = 'Konya';
        Geo.Lat  = 37.874;
        Geo.Lon  = 32.493;
        Geo.TZ   = 3;
        Geo.Alt  = 1016;

    % ── Bilinmeyen konum: CSV metadata'dan oku veya hata ver ─────────────
    otherwise
        % CSV dosyasından koordinat okumayı dene
        csv_candidates = {
            sprintf('%s_Hourly.csv', upper(loc_name)),
            sprintf('%s_hourly.csv', loc_name)
        };
        for k = 1:numel(csv_candidates)
            if isfile(csv_candidates{k})
                Geo = readGeoFromCSV(csv_candidates{k});
                Geo.Name = loc_name;
                fprintf('  ℹ Koordinatlar CSV''den okundu: %s\n', csv_candidates{k});
                return;
            end
        end
        error(['getGeoConfig: Bilinmeyen konum adı: ''%s''\n' ...
               'Lütfen getGeoConfig.m içine yeni bir case ekleyin.'], loc_name);
end
end

%% ── Yardımcı: CSV dosyasından koordinat oku ────────────────────────────
function Geo = readGeoFromCSV(csv_path)
    Geo.Lat  = NaN;
    Geo.Lon  = NaN;
    Geo.TZ   = 3;      % Türkiye varsayılanı
    Geo.Alt  = 0;
    Geo.Name = csv_path;

    fid = fopen(csv_path, 'r');
    if fid == -1, return; end

    for k = 1:10
        line = fgetl(fid);
        if ~ischar(line), break; end
        if contains(lower(line), 'latitude')
            tok = regexp(line, '([-\d.]+)\s*$', 'tokens');
            if ~isempty(tok), Geo.Lat = str2double(tok{1}{1}); end
        end
        if contains(lower(line), 'longitude')
            tok = regexp(line, '([-\d.]+)\s*$', 'tokens');
            if ~isempty(tok), Geo.Lon = str2double(tok{1}{1}); end
        end
        if contains(lower(line), 'elevation')
            tok = regexp(line, '([\d.]+)', 'tokens');
            if ~isempty(tok), Geo.Alt = round(str2double(tok{1}{1})); end
        end
    end
    fclose(fid);
end
