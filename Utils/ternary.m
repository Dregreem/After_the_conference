function result = ternary(condition, true_val, false_val)
% TERNARY - Conditional value selector (ternary operator replacement)
%
% PARAMETER OWNERSHIP: Utility function (no owned parameters)
%
% Inputs:
%   condition   - Logical condition
%   true_val    - Value to return if condition is true
%   false_val   - Value to return if condition is false
%
% Outputs:
%   result      - Either true_val or false_val
%
% Usage:
%   result = ternary(x > 5, 'big', 'small');
%   result = ternary(is_flip, 180, 0);
%
% Author: Solar Tracker Simulation
% Version: 2.0 (moved to Utils for reuse)

    if condition
        result = true_val;
    else
        result = false_val;
    end
end
