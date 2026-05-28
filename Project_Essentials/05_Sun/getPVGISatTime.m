function [G_interp, el_interp] = getPVGISatTime(sim_time_sec, PVData)
% ═══════════════════════════════════════════════════════════════════
% GETPVGISATTIME — Interpolate PVGIS irradiance at simulation time
%
% PURPOSE:
%   Provides real-time solar irradiance and elevation angle via linear
%   interpolation of hourly PVGIS records.
%
% INPUTS:
%   sim_time_sec - elapsed simulation time [seconds] (0 = midnight)
%   PVData       - struct from loadPVGIS or filterPVGISbyDate
%
% OUTPUTS:
%   G_interp     - global horizontal irradiance [W/m²]
%   el_interp    - sun elevation angle [degrees]
%
% PHYSICS:
%   Linear interpolation between hourly samples. Returns 0 for times
%   outside PVGIS data range (night/missing data).
%
% ASSUMPTIONS:
%   - PVData.t_seconds is sorted and monotonically increasing
%   - sim_time_sec is within [0, 86400] for single-day analysis
%   - Irradiance < 0 clamped to 0 (night/invalid)
%
% REFERENCES:
%   - MATLAB interp1 documentation
%   - PVGIS methodology: Hammer et al. (2003)
%
% Author  : Kerem Bayer (Master's Thesis, 2024)
% Created : 2026-02-21
% ═══════════════════════════════════════════════════════════════════

    % Convert simulation time to seconds elapsed
    % PVGIS data spans full year: t_seconds goes 0 to ~31M seconds
    
    % Handle edge cases (extrapolate as 0)
    if sim_time_sec < PVData.t_seconds(1) || sim_time_sec > PVData.t_seconds(end)
        G_interp = 0;
        el_interp = 0;
        return;
    end
    
    % Interpolate irradiance (linear, extrapolate as 0)
    G_interp = interp1(PVData.t_seconds, PVData.G, sim_time_sec, 'linear', 0);
    
    % Interpolate elevation (linear, extrapolate as 0)
    el_interp = interp1(PVData.t_seconds, PVData.elevation, sim_time_sec, 'linear', 0);
    
    % Clamp to physically reasonable values
    G_interp = max(0, G_interp);
    el_interp = max(0, el_interp);
end
