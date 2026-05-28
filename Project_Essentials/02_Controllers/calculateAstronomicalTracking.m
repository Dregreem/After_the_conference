function [ideal_pan, ideal_tilt] = calculateAstronomicalTracking(phi, alpha)
%
% CALCULATEASTRONOMICALTRACKING - Convert sun azimuth/elevation to gimbal angles
%
% Pure feedforward transformation from spherical (azimuth, elevation) coordinates
% to gimbal pan/tilt angles. No sensor feedback, no control.
%
% INPUT:
%   phi   - Sun azimuth (degrees, 0°=North, 90°=East, 180°=South, 270°=West)
%   alpha - Sun elevation above horizon (degrees, 0°=horizon, 90°=zenith)
%
% OUTPUT:
%   ideal_pan  - Pan gimbal angle (degrees, ±180)
%   ideal_tilt - Tilt gimbal angle (degrees, ±90)
%
% MATH:
%   Simple mapping (no gimbal singularity handling):
%   pan = phi
%   tilt = 90 - alpha
%
% NOTE:
%   This is the OPEN-LOOP fallback (astronomical only, no sensor feedback).
%   Your main system (FSM) uses LDR sensor feedback and is preferred.
%

    % Direct coordinate transformation
    ideal_pan = phi;
    ideal_tilt = 90 - alpha;  % Convert elevation to tilt angle
    
    % Wrap pan to [-180, 180]
    if ideal_pan > 180
        ideal_pan = ideal_pan - 360;
    elseif ideal_pan < -180
        ideal_pan = ideal_pan + 360;
    end
    
end
