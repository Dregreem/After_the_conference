function PVData = loadPVGIS(filename)
% LOADPVGIS — Parses PVGIS 5.3 (SARAH3) Hourly Data CSV
%
% PURPOSE:
%   Robust parser for the official PVGIS 5.3 hourly timeseries export.
%   Skips the 8-line metadata header, reads all irradiance / temperature
%   columns, and strips the trailing legend footer automatically.
%
% CSV STRUCTURE (PVGIS 5.3 hourly export):
%   Lines  1–8 : Metadata  (Latitude, Elevation, database, slope/azimuth …)
%   Line   9   : Column header:  time,Gb(i),Gd(i),Gr(i),H_sun,T2m,WS10m,Int
%   Lines 10+  : Data rows:      20230101:0010,0.0,0.0,0.0,0.0,7.45,0.41,0.0
%   Footer     : Blank lines + column legend text + "PVGIS (c) European Union …"
%
% INPUT:
%   filename  - path to PVGIS 5.3 CSV file (string / char)
%
% OUTPUT struct PVData:
%   .time      - datetime array, local timestamps, no timezone
%   .Gb        - Beam irradiance on inclined plane          [W/m²]
%   .Gd        - Diffuse irradiance on inclined plane       [W/m²]
%   .Gr        - Reflected irradiance on inclined plane     [W/m²]
%   .G         - Total POA irradiance  Gb+Gd+Gr             [W/m²]  ← backward-compat
%   .H_sun     - Sun height above horizon                   [°]
%   .elevation - Alias for H_sun                            [°]     ← backward-compat
%   .T2m       - 2-m air (ambient) temperature              [°C]    ← NEW for thermal model
%   .WS10m     - 10-m total wind speed                      [m/s]
%   .t_seconds - Elapsed seconds from first record          [s]     ← used by getPVGISatTime
%
% REFERENCES:
%   PVGIS 5.3 methodology: Huld et al. (2012), doi:10.1016/j.solener.2012.03.006
%   Ross (1976) cell temperature: T_cell = T_amb + (NOCT-20)/800 × G
%   PVGIS online tool: https://re.jrc.ec.europa.eu/pvg_tools/
%
% Author  : Kerem Bayer (Master's Thesis, 2024)
% Updated : 2026-03-05  — rewritten for PVGIS 5.3 / SARAH3 format
% ═══════════════════════════════════════════════════════════════════

    N_META = 8;   % metadata lines that precede the column-header row

    % ── 1. Open file ──────────────────────────────────────────────────────
    fid = fopen(filename, 'r', 'n', 'UTF-8');
    if fid < 0
        error('loadPVGIS:FileNotFound', 'Cannot open file: %s', filename);
    end

    % Skip N_META metadata lines AND the column-header line (N_META+1 total)
    for k = 1:(N_META + 1)
        fgetl(fid);
    end

    % ── 2. Read data with textscan (handles footer gracefully) ─────────────
    % Columns: time(str)  Gb   Gd   Gr   H_sun  T2m  WS10m  Int
    C = textscan(fid, '%s %f %f %f %f %f %f %f', ...
        'Delimiter',     ',',              ...
        'TreatAsEmpty',  {'NA','NaN'},     ...
        'EmptyValue',    NaN,              ...
        'ReturnOnError', true,             ...
        'CollectOutput', false);
    fclose(fid);

    raw_time  = C{1};   % cell array of datetime strings
    Gb_raw    = C{2};   % Beam on inclined plane   [W/m²]
    Gd_raw    = C{3};   % Diffuse on inclined plane [W/m²]
    Gr_raw    = C{4};   % Reflected                [W/m²]
    Hsun_raw  = C{5};   % Sun height               [°]
    T2m_raw   = C{6};   % 2-m air temperature      [°C]
    WS10m_raw = C{7};   % 10-m wind speed          [m/s]
    % C{8} = Int reconstruction flag — loaded but not exposed

    % ── 3. Parse PVGIS datetime strings  '20230101:0010' → datetime ───────
    dt_raw = datetime(raw_time, 'InputFormat', 'yyyyMMdd:HHmm');

    % ── 4. Strip footer rows (produce NaT because legend lines are not dates)
    valid     = ~isnat(dt_raw);
    dt_raw    = dt_raw(valid);
    Gb_raw    = Gb_raw(valid);
    Gd_raw    = Gd_raw(valid);
    Gr_raw    = Gr_raw(valid);
    Hsun_raw  = Hsun_raw(valid);
    T2m_raw   = T2m_raw(valid);
    WS10m_raw = WS10m_raw(valid);

    assert(~isempty(dt_raw), ...
        '[loadPVGIS] No valid data rows found. Check N_META (%d) matches the file.', N_META);

    % ── 5. Clamp irradiance / elevation to physically valid range ──────────
    Gb_raw   = max(0, Gb_raw);
    Gd_raw   = max(0, Gd_raw);
    Gr_raw   = max(0, Gr_raw);
    Hsun_raw = max(0, Hsun_raw);

    % ── 6. Assemble output struct ──────────────────────────────────────────
    PVData.time      = dt_raw;
    PVData.Gb        = Gb_raw;                        % Beam         [W/m²]
    PVData.Gd        = Gd_raw;                        % Diffuse      [W/m²]
    PVData.Gr        = Gr_raw;                        % Reflected    [W/m²]
    PVData.G         = Gb_raw + Gd_raw + Gr_raw;      % Total POA    [W/m²] — backward compat
    PVData.H_sun     = Hsun_raw;                      % Sun height   [°]
    PVData.elevation = Hsun_raw;                      % Alias        [°]    — backward compat
    PVData.T2m       = T2m_raw;                       % Air temp     [°C]
    PVData.WS10m     = WS10m_raw;                     % Wind speed   [m/s]
    PVData.t_seconds = seconds(dt_raw - dt_raw(1));   % Elapsed sec  [s]    — interp1 key

    % fprintf('✓ PVGIS 5.3 loaded: %d records | %s → %s\n', ...
    %     numel(dt_raw), ...
    %     char(dt_raw(1),  'yyyy-MM-dd HH:mm'), ...
    %     char(dt_raw(end),'yyyy-MM-dd HH:mm'));
end
