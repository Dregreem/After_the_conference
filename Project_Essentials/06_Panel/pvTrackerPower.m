function [P_tracker, props] = pvTrackerPower(G_now, theta_inc, varargin)
% PVTRACKERPOWER - Calculate power output of solar tracking panel
%
% PARAMETER OWNERSHIP: This function owns its own solar panel model parameters
%
% Inputs:
%   G_now          - Current solar irradiance [W/m²]
%   theta_inc      - Incidence angle (angle between sun and panel normal) [degrees]
%   panel_config   - (Optional) Panel configuration struct with fields:
%                   .A   - Panel area [m²]
%                   .eta - Panel efficiency [0-1]
%                   If not provided, uses internal defaults
%
% Outputs:
%   P_tracker      - Power output of tracking panel [W]
%
% Notes:
%   - Assumes ideal two-axis solar tracker (always perpendicular to sun)
%   - Incidence angle θ_inc should be ≤ 90° for tracking to be effective
%   - Power = G × Area × Efficiency × cos(θ_inc)
%
% Author: Solar Tracker Simulation
% Version: 2.0 (distributed parameters)

    % ══════════════════════════════════════════════════════════════════════
    % OWNED PARAMETERS: Solar tracking specifications
    % ══════════════════════════════════════════════════════════════════════
    % Default panel_config if not provided
    if isempty(varargin)
        panel_config = struct('A', 1.0, 'eta', 0.20);  % 1.0 m², 20% efficiency
    else
        panel_config = varargin{1};
    end
    
    % These parameters define the ideal tracking panel characteristics
    max_incidence_angle_deg = 90;  % Maximum angle to track (clamped)
    
    % ══════════════════════════════════════════════════════════════════════
    % POWER CALCULATION FOR TRACKING PANEL
    % ══════════════════════════════════════════════════════════════════════
    % Expose owned parameters via props struct
    props = struct();
    props.Area = panel_config.A;
    props.Efficiency = panel_config.eta;
    props.MaxIncidenceAngle = max_incidence_angle_deg;
    
    % Incidence angle is already in degrees (from checkAlignment output)
    theta_inc_deg = theta_inc;
    
    % Calculate cosine of incidence angle (for power calculation)
    % FIX (BUG-2): Use cosd() since theta_inc is in DEGREES, not radians
    cos_theta_inc = max(0, cosd(theta_inc));  % Clamped to [0,1]
    
    if theta_inc_deg > max_incidence_angle_deg
        % Tracking beyond safe limits → reduced tracking efficiency
        % In practice, tracker may not be able to follow, or sun may be out of range
        P_tracker = 0;
    else
        % Power = Irradiance × Area × Efficiency × cos(incidence angle)
        % For ideal tracker: θ_inc is very small, so cos(θ_inc) ≈ 1
        P_tracker = G_now * panel_config.A * panel_config.eta * cos_theta_inc;
    end
end
