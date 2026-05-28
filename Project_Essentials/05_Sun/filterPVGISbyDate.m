function [PVData_filtered, DayStats] = filterPVGISbyDate(PVData_full, mode, reference_date)
% ═══════════════════════════════════════════════════════════════════
% FILTERPVGISBYDATE — Extract and analyze PVGIS data for a specific day
%
% PURPOSE:
%   Filters full-year PVGIS dataset to single calendar day and computes
%   academic-grade daily solar metrics via trapezoidal integration.
%
% INPUTS:
%   PVData_full    - struct from loadPVGIS (all 8760 hourly records)
%   mode           - string, 'SOLSTICE' (June 21) or 'DAILY' (specific date)
%   reference_date - datetime scalar (required if mode='DAILY')
%
% OUTPUTS:
%   PVData_filtered - struct with single day, t_seconds reset to 0 at midnight
%   DayStats       - struct with daily metrics:
%     .date              - datetime of analyzed day [datetime]
%     .peak_irradiance   - max(G) on that day [W/m²]
%     .daylight_hours    - duration where G > 1 [hours]
%     .daily_insolation  - ∫G·dt via trapz [Wh/m²]
%     .mode              - 'SOLSTICE' or 'DAILY' [string]
%     .description       - human-readable analysis label [string]
%
% PHYSICS:
%   Daily insolation: H = ∫₀^T G(t) dt [Wh/m² or kWh/m²]
%   Computed via trapezoidal rule for academic rigor:
%     H = trapz(t_hours, G_values) where t_hours ∈ [0, 24] hours
%
% ASSUMPTIONS:
%   - Summer solstice (June 21) per EN ISO 9060, IEC 61853
%   - PVGIS data is hourly (one record per hour)
%   - Elevation angle > 1 W/m² defines daylight period
%
% REFERENCES:
%   - EN ISO 9060 (Solar Energy Resource Assessment)
%   - IEC 61853 (Performance Testing of Solar Energy Systems)
%   - PVGIS C3S database: https://pvgis.cm.dsf.unimi.it/
%
% Author  : Kerem Bayer (Master's Thesis, 2024)
% Created : 2026-02-21
% ═══════════════════════════════════════════════════════════════════

    % ═══════════════════════════════════════════════════════════════════════
    % 1. DETERMINE TARGET DATE
    % ═══════════════════════════════════════════════════════════════════════
    
    if nargin < 2 || isempty(mode)
        mode = 'SOLSTICE';
    end
    
    if nargin < 3
        reference_date = [];
    end
    
    % Validate mode
    mode = upper(mode);
    if ~ismember(mode, {'SOLSTICE', 'DAILY'})
        error('filterpVGISbyDate:InvalidMode', 'Mode must be ''SOLSTICE'' or ''DAILY''');
    end
    
    % Determine target calendar date
    if strcmp(mode, 'SOLSTICE')
        % Summer solstice: June 21 (canonical reference per ISO 9060 / IEC 61853)
        year_ref = year(PVData_full.time(1));
        target_date = datetime(year_ref, 6, 21);
        analysis_desc = 'Summer Solstice (21 Jun) — ISO 9060 Reference';
    else
        % Specific day analysis
        if isempty(reference_date)
            error('filterPVGISbyDate:MissingDate', ...
                'reference_date is required when mode=''DAILY''');
        end
        target_date = dateshift(reference_date, 'start', 'day');
        analysis_desc = sprintf('%s — Daily Analysis', datestr(target_date, 'dd-mmm-yyyy'));
    end
    
    % ═══════════════════════════════════════════════════════════════════════
    % 2. FILTER DATA BY DATE
    % ═══════════════════════════════════════════════════════════════════════
    
    % Extract dates from full dataset (midnight of each timestamp)
    % Remove timezone to avoid comparison issues
    dates_in_data = dateshift(PVData_full.time, 'start', 'day');
    dates_in_data.TimeZone = '';
    
    % Ensure target_date has no timezone for comparison
    if ismember(class(target_date), {'datetime'})
        target_date.TimeZone = '';
    end
    
    % Logical mask: rows matching target date
    mask = (dates_in_data == target_date);
    
    if ~any(mask)
        error('filterPVGISbyDate:DateNotFound', ...
            'Target date %s not found in PVGIS dataset', datestr(target_date, 'yyyy-mm-dd'));
    end
    
    % ═══════════════════════════════════════════════════════════════════════
    % 3. CREATE FILTERED STRUCT & RESET t_seconds
    % ═══════════════════════════════════════════════════════════════════════
    
    PVData_filtered = struct();
    PVData_filtered.time      = PVData_full.time(mask);
    PVData_filtered.G         = PVData_full.G(mask);
    PVData_filtered.elevation = PVData_full.elevation(mask);

    % ── Propagate PVGIS 5.3 component fields (if present) ─────────────────
    if isfield(PVData_full, 'Gb')
        PVData_filtered.Gb    = PVData_full.Gb(mask);
        PVData_filtered.Gd    = PVData_full.Gd(mask);
        PVData_filtered.Gr    = PVData_full.Gr(mask);
        PVData_filtered.H_sun = PVData_full.H_sun(mask);
        PVData_filtered.T2m   = PVData_full.T2m(mask);   % Ambient temp [°C] — for Evans (1981)
        PVData_filtered.WS10m = PVData_full.WS10m(mask);
    end
    
    % CRITICAL: Reset t_seconds to start at 0 (midnight of analysis day)
    % This ensures getPVGISatTime interpolation works correctly for the filtered day
    PVData_filtered.t_seconds = seconds(PVData_filtered.time - PVData_filtered.time(1));
    
    % ═══════════════════════════════════════════════════════════════════════
    % 4. COMPUTE DAILY STATISTICS (Academic Rigor)
    % ═══════════════════════════════════════════════════════════════════════
    
    % Peak irradiance (W/m²)
    DayStats.peak_irradiance = max(PVData_filtered.G);
    
    % Daylight duration (hours where G > 1 W/m²)
    daylight_mask = PVData_filtered.G > 1;  % >1 to avoid twilight noise
    hours_with_light = sum(daylight_mask);
    % PVGIS data is hourly (1 record/hour), so hours = count of records
    DayStats.daylight_hours = hours_with_light;  % hours
    
    % Daily insolation via TRAPEZOIDAL INTEGRATION (academic standard)
    % H = ∫G(t)dt [Wh/m²]
    % Convert hourly timestamp to decimal hours for integration
    t_hours = (0:(length(PVData_filtered.G)-1))';  % hours since midnight
    G_values = PVData_filtered.G;
    
    % Trapezoidal rule: ∫f·dt ≈ sum of trapezoids
    daily_insolation = trapz(t_hours, G_values);  % Wh/m² (G is W/m², hours is hours)
    DayStats.daily_insolation = daily_insolation;
    
    % Reference date and mode
    DayStats.date = target_date;
    DayStats.mode = mode;
    DayStats.description = analysis_desc;
    
    % ═══════════════════════════════════════════════════════════════════════
    % 5. VALIDATION (Sanity checks for data integrity)
    % ═══════════════════════════════════════════════════════════════════════
    
    if isnan(DayStats.peak_irradiance) || DayStats.peak_irradiance < 0
        warning('filterPVGISbyDate:InvalidIrradiance', ...
            'Peak irradiance is invalid (%.1f W/m²)', DayStats.peak_irradiance);
    end
    
    % ═══════════════════════════════════════════════════════════════════════
    % 6. REPORTING
    % ═══════════════════════════════════════════════════════════════════════
    
    % fprintf('✓ PVGIS filtered: %s\n', analysis_desc);
    % fprintf('  Date: %s | G_peak: %.1f W/m² | Daylight: %.2f h | H_daily: %.2f Wh/m²\n', ...
    %     datestr(target_date, 'dd-mmm-yyyy'), ...
    %     DayStats.peak_irradiance, ...
    %     DayStats.daylight_hours, ...
    %     DayStats.daily_insolation);
    
end
