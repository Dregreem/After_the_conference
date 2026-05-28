function value = getFieldOrDefault(s, field, default)
% GETFIELDORDEFAULT - Safe struct field access with default fallback
%
% PARAMETER OWNERSHIP: Utility function (no owned parameters)
%
% Inputs:
%   s           - Input struct
%   field       - Field name (string)
%   default     - Default value if field not present
%
% Outputs:
%   value       - Either s.(field) or default
%
% Usage:
%   tau = getFieldOrDefault(Config, 'tau_motor', 0.1);
%   K_p = getFieldOrDefault(Params, 'Kp', 3.0);
%
% Notes:
%   - Enables safe parameter access without breaking on missing fields
%   - Eliminates redundant if-isfield checks throughout codebase
%
% Author: Solar Tracker Simulation
% Version: 2.0 (moved to Utils as single source of truth)

    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end
