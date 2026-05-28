function [VelocityCommand, ControlState, DebugInfo, props] = FuzzyLogicController(ErrorSignal, ControlState, dt)
% FUZZYLOGICCONTROLLER - Swappable Controller Block (Block B)
% Mamdani Fuzzy Logic Controller — accepts ErrorSignal, outputs VelocityCommand.
%
% RESPONSIBILITY:
%   ✓ Evaluate 7×7 Mamdani rule matrix on (error, error_rate)
%   ✓ Centroid defuzzification for velocity output
%
%   ✗ NO sensor reading or Tangent Law
%   ✗ NO FSM state machine logic
%   ✗ NO darkness detection or night handling
%   ✗ NO position integration (Plant's job)
%
% INPUTS:
%   ErrorSignal  - struct {e_pan, e_tilt, de_pan, de_tilt, mode}
%                  from StateManagerFSM (Block A)
%   ControlState - struct (unused by FLC, kept for interface compatibility)
%   dt           - Time step (s) — unused by FLC but kept for interface parity
%
% OUTPUTS:
%   VelocityCommand - struct {v_pan, v_tilt} in deg/s
%   ControlState    - Unchanged (FLC is memoryless)
%   DebugInfo       - FLC output breakdown
%
% Author: Antigravity AI (for Kerem Bayer's thesis)
% Date: 2026-02-20
% Architecture: 3-Block (Supervisor → Controller → Plant)

    %% PARAMETER EXTRACTION — HARDCODED DEFAULTS (Controller Internals)
    % These are FLC-specific parameters that stay internal to this controller
    error_range       = [-60, 60];         % Membership function range (degrees)
    rate_range        = [-15, 15];         % Rate membership function range (deg/s)
    output_range      = [-20, 20];         % Output velocity range (deg/s)
    rate_filter_alpha = 0.3;               % First-order low-pass filter for rate
    output_gain       = 1.0;               % Post-defuzzification scaling
    defuzz_resolution = 101;               % Resolution for centroid calculation
    K_e               = 2.0;               % Error scaling factor
    K_de              = 0.1;               % Error rate scaling factor
    K_out             = 5.0;               % Output gain scaling factor

    % Expose owned parameters via props struct
    props = struct();
    props.K_e = K_e;
    props.K_de = K_de;
    props.K_out = K_out;
    props.ErrorRange = error_range;
    props.RateRange = rate_range;
    props.OutputRange = output_range;
    props.RateFilterAlpha = rate_filter_alpha;
    props.OutputGain = output_gain;

    %% STATE INITIALIZATION (FLC is memoryless — no integrators)
    if isempty(ControlState)
        ControlState = struct('placeholder', 0);
    end

    %% EXTRACT ERROR SIGNALS
    e_pan   = ErrorSignal.e_pan;
    e_tilt  = ErrorSignal.e_tilt;
    de_pan  = ErrorSignal.de_pan;
    de_tilt = ErrorSignal.de_tilt;

    % If Supervisor says IDLE, output zero velocity
    if strcmp(ErrorSignal.mode, 'IDLE')
        VelocityCommand = struct('v_pan', 0, 'v_tilt', 0);
        DebugInfo = struct('vel_pan', 0, 'vel_tilt', 0, ...
                           'e_pan_deg', 0, 'e_tilt_deg', 0, ...
                           'de_pan_filt', 0, 'de_tilt_filt', 0, ...
                           'mode', 'IDLE');
        % props already populated above
        return;
    end

    %% MAMDANI FLC — PAN AXIS
    % Apply pre-scaling to inputs, then scale output
    Vel_Pan = K_out * mamdaniFLC(e_pan * K_e, de_pan * K_de, defuzz_resolution);
    Vel_Pan = Vel_Pan * output_gain;

    %% MAMDANI FLC — TILT AXIS
    % Apply pre-scaling to inputs, then scale output
    Vel_Tilt = K_out * mamdaniFLC(e_tilt * K_e, de_tilt * K_de, defuzz_resolution);
    Vel_Tilt = Vel_Tilt * output_gain;

    %% OUTPUT
    VelocityCommand = struct('v_pan', Vel_Pan, 'v_tilt', Vel_Tilt);

    %% DEBUG
    DebugInfo = struct( ...
        'vel_pan',     Vel_Pan, ...
        'vel_tilt',    Vel_Tilt, ...
        'e_pan_deg',   e_pan, ...
        'e_tilt_deg',  e_tilt, ...
        'de_pan_filt', de_pan, ...
        'de_tilt_filt', de_tilt, ...
        'mode',        ErrorSignal.mode);

end

%% ================================================================
%% MAMDANI FLC ENGINE (Self-Contained, No Toolbox Required)
%% ================================================================

function vel_out = mamdaniFLC(error_deg, error_rate, N_points)
% MAMDANIFLC - Single-axis Mamdani fuzzy inference
%
% Inputs:
%   error_deg  - Angular error (degrees), universe [-60, 60]
%   error_rate - Error rate (deg/s),       universe [-15, 15]
%   N_points   - Defuzzification grid resolution (default 101)
%
% Output:
%   vel_out    - Velocity command (deg/s), universe [-20, 20]

    if nargin < 3, N_points = 101; end

    %% 1. MEMBERSHIP FUNCTION PARAMETERS
    % ---- Input 1: Error (deg) ----
    err_mf = struct();
    err_mf.NB = [-60, -45, -20, -10];   % trapmf
    err_mf.NM = [-20, -10, -2];          % trimf
    err_mf.NS = [-5, -1.5, 0];           % trimf
    err_mf.ZE = [-0.5, 0, 0.5];          % trimf (tight!)
    err_mf.PS = [0, 1.5, 5];             % trimf
    err_mf.PM = [2, 10, 20];             % trimf
    err_mf.PB = [10, 20, 45, 60];        % trapmf

    % ---- Input 2: Error Rate (deg/s) ----
    rate_mf = struct();
    rate_mf.NB = [-15, -10, -6, -3];     % trapmf
    rate_mf.NM = [-6, -3, -1];            % trimf
    rate_mf.NS = [-3, -1, 0];             % trimf
    rate_mf.ZE = [-1, 0, 1];              % trimf
    rate_mf.PS = [0, 1, 3];               % trimf
    rate_mf.PM = [1, 3, 6];               % trimf
    rate_mf.PB = [3, 6, 10, 15];          % trapmf

    % ---- Output: Velocity (deg/s) ----
    out_mf = struct();
    out_mf.NB = [-20, -15, -10, -5];     % trapmf
    out_mf.NM = [-10, -5, -2];            % trimf
    out_mf.NS = [-5, -2, 0];              % trimf
    out_mf.ZE = [-1, 0, 1];               % trimf
    out_mf.PS = [0, 2, 5];                % trimf
    out_mf.PM = [2, 5, 10];               % trimf
    out_mf.PB = [5, 10, 15, 20];          % trapmf

    %% 2. FUZZIFY INPUTS
    mf_names = {'NB', 'NM', 'NS', 'ZE', 'PS', 'PM', 'PB'};

    mu_err = zeros(1, 7);
    for k = 1:7
        params = err_mf.(mf_names{k});
        if length(params) == 4
            mu_err(k) = evalTrapmf(error_deg, params);
        else
            mu_err(k) = evalTrimf(error_deg, params);
        end
    end

    mu_rate = zeros(1, 7);
    for k = 1:7
        params = rate_mf.(mf_names{k});
        if length(params) == 4
            mu_rate(k) = evalTrapmf(error_rate, params);
        else
            mu_rate(k) = evalTrimf(error_rate, params);
        end
    end

    %% 3. RULE BASE (7x7 Matrix)
    Rules = [
    %   Rate: NB  NM  NS  ZE  PS  PM  PB     <- Error Rate
             1,  1,  1,  1,  2,  3,  4;  % NB  <- Error
             1,  1,  2,  2,  3,  4,  5;  % NM
             1,  2,  3,  3,  4,  5,  6;  % NS
             1,  2,  3,  4,  5,  6,  7;  % ZE
             2,  3,  4,  5,  5,  6,  7;  % PS
             3,  4,  5,  6,  6,  7,  7;  % PM
             4,  5,  6,  7,  7,  7,  7;  % PB
    ];

    %% 4. INFERENCE (Min-Max Mamdani)
    agg_strength = zeros(1, 7);
    for i = 1:7
        for j = 1:7
            firing = min(mu_err(i), mu_rate(j));
            out_idx = Rules(i, j);
            agg_strength(out_idx) = max(agg_strength(out_idx), firing);
        end
    end

    %% 5. DEFUZZIFICATION (Centroid)
    out_range = linspace(-20, 20, N_points);
    aggregated = zeros(1, N_points);

    for k = 1:7
        if agg_strength(k) < 1e-8
            continue;
        end
        params = out_mf.(mf_names{k});
        for p = 1:N_points
            if length(params) == 4
                mu_p = evalTrapmf(out_range(p), params);
            else
                mu_p = evalTrimf(out_range(p), params);
            end
            clipped = min(mu_p, agg_strength(k));
            aggregated(p) = max(aggregated(p), clipped);
        end
    end

    total_area = sum(aggregated);
    if total_area > 1e-8
        vel_out = sum(out_range .* aggregated) / total_area;
    else
        vel_out = 0;
    end
end

%% ================================================================
%% MEMBERSHIP FUNCTION EVALUATORS
%% ================================================================

function mu = evalTrimf(x, params)
    a = params(1); b = params(2); c = params(3);
    if x <= a || x >= c
        mu = 0;
    elseif x <= b
        mu = (x - a) / (b - a + 1e-10);
    else
        mu = (c - x) / (c - b + 1e-10);
    end
end

function mu = evalTrapmf(x, params)
    a = params(1); b = params(2); c = params(3); d = params(4);
    if x <= a || x >= d
        mu = 0;
    elseif x >= b && x <= c
        mu = 1;
    elseif x < b
        mu = (x - a) / (b - a + 1e-10);
    else
        mu = (d - x) / (d - c + 1e-10);
    end
end

function value = getFieldOrDefault(s, field, default)
    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end
