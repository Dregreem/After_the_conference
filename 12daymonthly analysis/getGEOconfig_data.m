function Geo = getGeoConfig_month(loc_name)
% GETGEOCONFIG — Geographic & PVGIS Configuration Dictionary
% 
% PURPOSE:
%   Single source of truth for location-based parameters. Returns geographic
%   coordinates, timezone, and PVGIS data file path for multi-region analysis.
%
% USAGE:
%   Geo = getGeoConfig('ISTANBUL');   % Returns Istanbul configuration
%   Geo = getGeoConfig('HELSINKI');   % Returns Helsinki configuration
%   Geo = getGeoConfig('ASWAN');      % Returns Aswan (Egypt) configuration
%
% OUTPUT:
%   Geo struct with fields:
%     .Name         — Location name [string]
%     .Lat          — Latitude [degrees N, positive]
%     .Lon          — Longitude [degrees E, positive]
%     .TZ           — Timezone offset from UTC [hours, signed]
%     .PVGIS_File   — Path to PVGIS CSV data file [string]
%
% NOTES:
%   - All latitudes/longitudes in decimal degrees (positive = N/E)
%   - Timezones: positive for East of UTC, negative for West
%   - PVGIS files must exist in the working directory or be relative paths
%
% Author   : Kerem Bayer (Master's Thesis, 2024)
% Created  : 2026-03-05
% ═══════════════════════════════════════════════════════════════════════════

    %% ARGUMENT VALIDATION
    if nargin < 1 || isempty(loc_name)
        loc_name = 'ISTANBUL';  % Default location
    end
    
    %% GEOGRAPHIC SWITCH
    switch upper(loc_name)
        
        case 'ISTANBUL'
            % Istanbul, Turkey — Mediterranean Climate
            % Reference: 41.05°N, 29.01°E, UTC+3
            % PVGIS file: SARAH3, slope=0°, azimuth=0°, year 2023
            Geo = struct();
            Geo.Name       = 'Istanbul, TR';
            Geo.Lat        = 41.050;             % [°N]
            Geo.Lon        = 29.010;             % [°E]
            Geo.TZ         = 3;                  % [hours, UTC+3]
            Geo.PVGIS_File = fullfile('DATA', 'Istanbul', 'ISTANBUL_HOURLY_12dates.csv');
        
        case 'KAS'
            % Kaş, Turkey — Mediterranean Coast (Southwest Anatolia)
            % Reference: 36.2°N, 29.64°E, UTC+3
            % PVGIS file: SARAH3, slope=0°, azimuth=0°, year 2023
            Geo = struct();
            Geo.Name       = 'Kaş, TR';
            Geo.Lat        = 36.200;             % [°N]
            Geo.Lon        = 29.640;             % [°E]
            Geo.TZ         = 3;                  % [hours, UTC+3]
            Geo.PVGIS_File = 'KAS_data.csv';
        
        case 'ANKARA'
            % Ankara, Turkey — Central Anatolia
            % Reference: 39.79°N, 32.81°E, UTC+3
            % PVGIS file: SARAH3, slope=0°, azimuth=0°, year 2023
            Geo = struct();
            Geo.Name       = 'Ankara, TR';
            Geo.Lat        = 39.790;             % [°N]
            Geo.Lon        = 32.810;             % [°E]
            Geo.TZ         = 3;                  % [hours, UTC+3]
            Geo.PVGIS_File = fullfile('..', 'Locations', 'Data', 'ANKARA_Data.csv');
        
        case 'HELSINKI'
            % Helsinki, Finland — High-Latitude Continental Climate
            % Reference: 60.17°N, 24.94°E, UTC+2 (standard time)
            Geo = struct();
            Geo.Name       = 'Helsinki, FI';
            Geo.Lat        = 60.17;              % [°N]
            Geo.Lon        = 24.94;              % [°E]
            Geo.TZ         = 2;                  % [hours, UTC+2 standard; UTC+3 summer]
            Geo.PVGIS_File = 'pvgis_helsinki.csv';
        
        case 'ASWAN'
            % Aswan, Egypt — Desert Climate (hottest tracker test case)
            % Reference: 24.09°N, 32.90°E, UTC+2
            Geo = struct();
            Geo.Name       = 'Aswan, EG';
            Geo.Lat        = 24.09;              % [°N]
            Geo.Lon        = 32.90;              % [°E]
            Geo.TZ         = 2;                  % [hours, UTC+2]
            Geo.PVGIS_File = 'pvgis_aswan.csv';
        
        case 'ANTALYA'
            % Antalya, Turkey — Mediterranean Coast (warm, high irradiance)
            Geo = struct();
            Geo.Name       = 'Antalya, TR';
            Geo.Lat        = 36.89;              % [°N]
            Geo.Lon        = 30.71;              % [°E]
            Geo.TZ         = 3;                  % [hours, UTC+3]
            Geo.PVGIS_File = fullfile('..', 'Locations', 'Data', 'ANTALYA_Data.csv');
        
        case 'TRABZON'
            % Trabzon, Turkey — Black Sea Coast (cloudier, moderate irradiance)
            Geo = struct();
            Geo.Name       = 'Trabzon, TR';
            Geo.Lat        = 41.00;              % [°N]
            Geo.Lon        = 39.72;              % [°E]
            Geo.TZ         = 3;                  % [hours, UTC+3]
            Geo.PVGIS_File = 'pvgis_trabzon.csv';
        
        case 'SANLIURFA'
            % Şanlıurfa, Turkey — Southeastern Anatolia (hot, very high irradiance)
            Geo = struct();
            Geo.Name       = 'Şanlıurfa, TR';
            Geo.Lat        = 37.16;              % [°N]
            Geo.Lon        = 38.79;              % [°E]
            Geo.TZ         = 3;                  % [hours, UTC+3]
            Geo.PVGIS_File = 'pvgis_sanliurfa.csv';
        
        case 'SINGAPORE'
            % Singapore — Equatorial Tropical Climate (year-round warm, consistent irradiance)
            Geo = struct();
            Geo.Name       = 'Singapore, SG';
            Geo.Lat        = 1.35;               % [°N]
            Geo.Lon        = 103.82;             % [°E]
            Geo.TZ         = 8;                  % [hours, UTC+8]
            Geo.PVGIS_File = 'pvgis_singapore.csv';
        
        otherwise
            % Unrecognized location — warn and default to Istanbul
            warning('getGeoConfig:UnknownLocation', ...
                sprintf('Location "%s" not found. Defaulting to ISTANBUL.\nAvailable: ISTANBUL, ANTALYA, TRABZON, SANLIURFA, HELSINKI, ASWAN, SINGAPORE', ...
                upper(loc_name)));
            Geo = struct();
            Geo.Name       = 'Istanbul, TR (default)';
            Geo.Lat        = 41.05;
            Geo.Lon        = 29.01;
            Geo.TZ         = 3;
            Geo.PVGIS_File = 'Timeseries_41.051_29.010_SA3_41deg_0deg_2023_2023.csv';
    end

end

%% ═══════════════════════════════════════════════════════════════════════════
%% REFERENCE DATA (Geographic Comment Block)
%% ═══════════════════════════════════════════════════════════════════════════
%
% ISTANBUL, TURKEY (Mediterranean / Subtropical)
% ─────────────────────────────────────────────
%   Latitude:      41.05° N
%   Longitude:     29.01° E
%   Timezone:      UTC+3 (standard time)
%   Climate:       Mediterranean — summer dry, winter wet
%   Annual GHI:    ~1600 kWh/m²/year
%   Peak sun hrs:  ~4.5 hours/day (annual average)
%   Tracker advantage: Moderate (35–45% over fixed)
%   Use case: Proof of concept for mid-latitude solar systems
%
% HELSINKI, FINLAND (High-Latitude Boreal)
% ──────────────────────────────────────────
%   Latitude:      60.17° N
%   Longitude:     24.94° E
%   Timezone:      UTC+2 (standard time), UTC+3 (summer)
%   Climate:       Continental — very seasonal, long winter nights
%   Annual GHI:    ~1000 kWh/m²/year
%   Peak sun hrs:  ~2.8 hours/day (annual average)
%   Tracker advantage: Very High (60–80% over fixed)
%     Rationale: Tracker's seasonal tracking critical when sun altitude is always low
%   Use case: Extreme case demonstrating tracker value in challenging climates
%
% ASWAN, EGYPT (Desert / Tropical)
% ──────────────────────────────────
%   Latitude:      24.09° N
%   Longitude:     32.90° E
%   Timezone:      UTC+2 (standard time)
%   Climate:       Hot desert — consistent high sun, minimal clouds
%   Annual GHI:    ~2400 kWh/m²/year (highest on Earth)
%   Peak sun hrs:  ~6.5 hours/day (annual average)
%   Tracker advantage: Moderate (25–35% over fixed)
%     Rationale: Fixed panels already get high constant irradiance
%   Use case: Stress test (validates tracker under extreme heat, confirming parasitic losses scale correctly)
%
% ═══════════════════════════════════════════════════════════════════════════
