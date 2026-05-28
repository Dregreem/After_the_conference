function [azimuth, elevation] = cartesian2spherical(S_vec)
% CARTESIAN2SPHERICAL - Convert ENU Cartesian vector to spherical coordinates
%
% PARAMETER OWNERSHIP: Geometry conversion utility (no owned parameters)
%
% Inputs:
%   S_vec   - Solar position vector in ENU frame [x; y; z]
%             where x=East, y=North, z=Up
%
% Outputs:
%   azimuth    - Solar azimuth angle [degrees, 0-360]
%   elevation  - Solar elevation angle [degrees, -90 to +90]
%
% Notes:
%   - Azimuth is measured clockwise from North
%   - Elevation is angle above horizon
%   - FIXED: Correct ENU frame mapping (atan2d(East, North) = atan2d(x, y))
%
% Author: Solar Tracker Simulation
% Version: 2.0 (moved to Utils for reuse)

    % FIXED: ENU frame → Azimuth from North
    % atan2d(East, North) = atan2d(x, y)
    x = S_vec(1); y = S_vec(2); z = S_vec(3);
    norm_vec = norm(S_vec);
    if norm_vec > 0
        x = x / norm_vec; y = y / norm_vec; z = z / norm_vec;
    end
    
    azimuth = atan2d(x, y);  % FIXED: was atan2d(y, x)
    if azimuth < 0, azimuth = azimuth + 360; end
    elevation = asind(z);
end
