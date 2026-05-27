function [adjusted_pan, adjusted_tilt, is_flip, is_reachable] = applyFlipLogic(ideal_pan, ideal_tilt, limits)
% APPLYFLIPLOGIC - Apply gimbal flip logic to servo angles
%
% PARAMETER OWNERSHIP: Servo geometry utility owns servo mechanical limits
%
% Inputs:
%   ideal_pan      - Ideal pan angle [degrees, -180 to +180]
%   ideal_tilt     - Ideal tilt angle [degrees, -90 to +90]
%   limits (optional) - Limits struct with fields:
%                   .Pan   - Pan angle limit [degrees] (default: 100)
%                   .Tilt  - Tilt angle limit [degrees] (default: 90)
%
% Outputs:
%   adjusted_pan   - Final pan command [degrees]
%   adjusted_tilt  - Final tilt command [degrees]
%   is_flip        - Boolean, true if flip applied
%   is_reachable   - Boolean, true if target is reachable
%
% Logic:
%   1. Check if ideal angle is within limits → use as-is
%   2. Check if flipped angle (pan+180°, tilt*-1) is within limits → use flip
%   3. Otherwise clamp to limits (unreachable)
%
% Author: Solar Tracker Simulation
% Version: 2.0 (moved to Utils for reuse)

    % OWNED PARAMETERS: Servo mechanical limits
    if nargin < 3 || isempty(limits)
        defaults = getApplyFlipLogicDefaults();
        limits = struct('Pan', defaults.pan_limit, 'Tilt', defaults.tilt_limit);
    end
    
    pan_lim = limits.Pan; 
    tilt_lim = limits.Tilt;
    
    % Try direct angle first
    if (abs(ideal_pan) <= pan_lim) && (abs(ideal_tilt) <= tilt_lim)
        adjusted_pan = ideal_pan; adjusted_tilt = ideal_tilt;
        is_flip = false; is_reachable = true; 
        return;
    end
    
    % Try flipped angle (gimbal flip for wraparound)
    flip_pan = ideal_pan + 180;
    if flip_pan > 180, flip_pan = flip_pan - 360; end
    flip_tilt = -ideal_tilt;
    
    if (abs(flip_pan) <= pan_lim) && (flip_tilt >= -90) && (flip_tilt <= 90)
        adjusted_pan = flip_pan; adjusted_tilt = flip_tilt;
        is_flip = true; is_reachable = true; 
        return;
    end

    % Clamp to limits (unreachable)
    adjusted_pan = max(-pan_lim, min(pan_lim, ideal_pan));
    adjusted_tilt = max(-tilt_lim, min(tilt_lim, ideal_tilt));
    is_flip = false; is_reachable = false;
end

% ════════════════════════════════════════════════════════════════════════════
% HELPER: Get default parameters owned by this module
% ════════════════════════════════════════════════════════════════════════════
function defaults = getApplyFlipLogicDefaults()
    % Returns all default parameters owned by applyFlipLogic
    defaults = struct();
    defaults.pan_limit = 90;          % Pan angle limit [°]
    defaults.tilt_limit = 90;          % Tilt angle limit [°]
    defaults.blend_factor = 0.5;       % Flip logic blend factor [0-1]
end
