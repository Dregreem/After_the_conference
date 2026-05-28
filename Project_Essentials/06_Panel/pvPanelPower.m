function [P_watts, props] = pvPanelPower(G, az_sun_deg, el_sun_deg, panel_config)
% PVPANELPOWER - Computes instantaneous power for a FIXED south-facing panel
%
% Fixed panel: South-facing, tilted at Istanbul latitude (41°)
%
% Input:
%   G             - irradiance W/m² (from PVGIS)
%   az_sun_deg    - sun azimuth in ENU degrees
%   el_sun_deg    - sun elevation degrees
%   panel_config  - struct with fields: A (m²), eta (0-1)
%
% Output:
%   P_watts - instantaneous power in Watts
%
% Physics: P = A × eta × G × max(0, cos(theta_inc))
% where theta_inc = angle between sun vector and panel normal

    % Sun unit vector in ENU frame
    az = deg2rad(az_sun_deg);
    el = deg2rad(el_sun_deg);
    S_sun = [cos(el)*sin(az); cos(el)*cos(az); sin(el)];
    
    % Fixed panel normal — south-facing, tilted 41° from horizontal
    % South = -Y in ENU, tilted up toward Z
    tilt = deg2rad(41);
    N_fixed = [0; -sin(tilt); cos(tilt)];  % normalized by construction
    
    % Incidence angle via dot product
    cos_theta = dot(S_sun, N_fixed);
    
    % Power (clamp negative cosine to 0)
    P_watts = panel_config.A * panel_config.eta * G * max(0, cos_theta);
    
    % Expose owned parameters via props struct
    props = struct();
    props.Area = panel_config.A;
    props.Efficiency = panel_config.eta;
    props.TiltDeg = 41;
    props.AzimuthDeg = 180;  % South-facing
end

