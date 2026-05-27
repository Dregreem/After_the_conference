function [TargetPan, TargetTilt, FSM_State, DebugInfo] = fuzzyController(LDR_V, S_body, CurrentPan, CurrentTilt, FSM_State, Params, dt, is_flip)
% FUZZYCONTROLLER - Mamdani Fuzzy Logic Controller for Dual-Axis Solar Tracker
% Replaces PI velocity controller with a 7-MF Mamdani FLC.
%
% ARCHITECTURE:
%   - 2 Inputs:  Angular Error (e) and Error Rate (de/dt)
%   - 1 Output:  Velocity Command (deg/s)
%   - 7 MFs each: NB, NM, NS, ZE, PS, PM, PB
%   - 49 rules (7x7 diagonal-inverse matrix)
%   - Centroid defuzzification
%
% INTERFACE: Identical to fsmController.m for drop-in replacement.
%
% INPUTS:
%   LDR_V       - [V_Right, V_Left, V_Up, V_Down] voltages
%   S_body      - Sun vector in body frame (3x1)
%   CurrentPan  - Current pan angle (deg)
%   CurrentTilt - Current tilt angle (deg)
%   FSM_State   - State machine struct (mode, integrals, prev errors)
%   Params      - Controller parameters struct
%   dt          - Time step (s)
%   is_flip     - Boolean, true if gimbal is in flipped configuration
%
% OUTPUTS:
%   TargetPan   - Target pan angle (deg)
%   TargetTilt  - Target tilt angle (deg)
%   FSM_State   - Updated state struct
%   DebugInfo   - Debug telemetry struct
%
% THEORY (Thesis Justification):
%   The ±60° universe of discourse for Angular Error is intentionally wider
%   than the tangent-law sensor's effective ±30° range because:
%     1. During initialization/acquisition the tracker may start far from
%        the sun, producing transient errors up to 30-45°.
%     2. During flip transitions, error can briefly spike beyond the
%        sensor's linear region.
%     3. The NB/PB trapezoidal MFs saturate beyond ±45°, commanding
%        maximum velocity — any error > 30° maps to the same aggressive
%        response. The extra headroom costs nothing computationally.
%     4. MF density is concentrated near zero (ZE: ±0.5°) where tracking
%        precision matters most, so the wide range does not dilute accuracy.
%
% Author: Antigravity AI (for Kerem Bayer's thesis)
% Date: 2026-02-18

    %% PARAMETER EXTRACTION
    if nargin < 6 || isempty(Params), Params = struct(); end
    if nargin < 8 || isempty(is_flip), is_flip = false; end

    % Shared parameters (same as PI baseline)
    night_threshold  = getFieldOrDefault(Params, 'night_threshold', 0.3);
    search_speed     = getFieldOrDefault(Params, 'search_speed', 3.0);
    zenith_pan_lock  = getFieldOrDefault(Params, 'zenith_pan_lock', false);
    pan_limit        = getFieldOrDefault(Params, 'pan_limit', 180);

    % FLC-specific parameters
    rate_filter_alpha = getFieldOrDefault(Params, 'rate_filter_alpha', 0.3);
    output_gain       = getFieldOrDefault(Params, 'output_gain', 1.0);
    defuzz_resolution = getFieldOrDefault(Params, 'defuzz_resolution', 101);

    %% STATE INITIALIZATION
    if isempty(FSM_State)
        FSM_State = struct('mode', 'TRACKING', 'I_pan', 0, 'I_tilt', 0, ...
                           'e_pan_prev', 0, 'e_tilt_prev', 0, ...
                           'de_pan_filtered', 0, 'de_tilt_filtered', 0, ...
                           'search_phase', 0);
    end

    current_mode   = getFieldOrDefault(FSM_State, 'mode', 'TRACKING');
    search_phase   = getFieldOrDefault(FSM_State, 'search_phase', 0);
    e_pan_prev     = getFieldOrDefault(FSM_State, 'e_pan_prev', 0);
    e_tilt_prev    = getFieldOrDefault(FSM_State, 'e_tilt_prev', 0);
    de_pan_filt    = getFieldOrDefault(FSM_State, 'de_pan_filtered', 0);
    de_tilt_filt   = getFieldOrDefault(FSM_State, 'de_tilt_filtered', 0);

    %% ============================================================
    %% SENSOR-BASED ERROR CALCULATION (Tangent Law)
    %% ============================================================
    % Identical to fsmController.m for fair benchmarking

    epsilon = 0.001;

    if ~isempty(LDR_V) && length(LDR_V) >= 4
        V_R = LDR_V(1); V_L = LDR_V(2);
        V_U = LDR_V(3); V_D = LDR_V(4);
        V_total = sum(LDR_V);
    else
        V_R = 0; V_L = 0; V_U = 0; V_D = 0;
        V_total = 0;
    end

    sum_pan  = V_L + V_R + epsilon;
    sum_tilt = V_U + V_D + epsilon;

    e_pan_normalized  = (V_L - V_R) / sum_pan;
    e_tilt_normalized = (V_U - V_D) / sum_tilt;

    e_pan_deg_raw  = atand(e_pan_normalized  ./ tan(deg2rad(60)));
    e_tilt_deg_raw = atand(e_tilt_normalized ./ tan(deg2rad(60)));

    if is_flip
        e_pan_deg = -e_pan_deg_raw;
    else
        e_pan_deg = e_pan_deg_raw;
    end
    e_tilt_deg = e_tilt_deg_raw;

    %% ============================================================
    %% FSM STATE MACHINE (IDLE / SEARCH / TRACKING)
    %% ============================================================
    % Identical to fsmController.m for consistent behavior

    is_dark = (V_total < night_threshold);

    if is_dark
        current_mode = 'IDLE';
        e_pan_deg = 0;
        e_tilt_deg = 0;
        de_pan_filt = 0;
        de_tilt_filt = 0;

    elseif strcmp(current_mode, 'IDLE') && ~is_dark
        current_mode = 'SEARCH';
        search_phase = 0;

    elseif strcmp(current_mode, 'SEARCH')
        search_phase = search_phase + dt;
        spiral_radius = 0.1 * search_phase;
        search_pan  = spiral_radius * cos(search_phase * 2 * pi);
        search_tilt = spiral_radius * sin(search_phase * 2 * pi);

        if (abs(e_pan_deg) < 1.0 && abs(e_tilt_deg) < 1.0)
            current_mode = 'TRACKING';
            search_phase = 0;
        else
            e_pan_deg  = search_pan;
            e_tilt_deg = search_tilt;
        end

    else
        current_mode = 'TRACKING';
    end

    %% ============================================================
    %% ZENITH SINGULARITY PROTECTION (Input Gain Scaling)
    %% ============================================================
    % Instead of complicating the rule base, we scale the FLC input.
    % This forces the FLC into the "fine tracking" center of the rule map.

    ZENITH_START  = 75;
    ZENITH_CUTOFF = 88;

    zenith_factor = 1.0;
    if zenith_pan_lock && CurrentTilt > ZENITH_CUTOFF
        e_pan_deg  = 0;
        de_pan_filt = 0;
        zenith_factor = 0.0;
    elseif zenith_pan_lock && CurrentTilt > ZENITH_START
        zenith_factor = (90 - CurrentTilt) / (90 - ZENITH_START);
        e_pan_deg  = e_pan_deg * zenith_factor;
        de_pan_filt = de_pan_filt * zenith_factor;
    end

    HORIZON_CUTOFF = -5;
    if e_tilt_deg < HORIZON_CUTOFF
        e_tilt_deg  = 0;
        de_tilt_filt = 0;
    end

    %% ============================================================
    %% ERROR RATE COMPUTATION (Filtered Derivative)
    %% ============================================================
    % EMA-filtered derivative to suppress LDR noise at 100Hz sampling.
    % de_filtered = alpha * de_prev + (1-alpha) * (e - e_prev) / dt

    if dt > 0
        de_pan_raw  = (e_pan_deg  - e_pan_prev)  / dt;
        de_tilt_raw = (e_tilt_deg - e_tilt_prev) / dt;
    else
        de_pan_raw  = 0;
        de_tilt_raw = 0;
    end

    de_pan_filt  = rate_filter_alpha * de_pan_filt  + (1 - rate_filter_alpha) * de_pan_raw;
    de_tilt_filt = rate_filter_alpha * de_tilt_filt + (1 - rate_filter_alpha) * de_tilt_raw;

    %% ============================================================
    %% MAMDANI FUZZY INFERENCE ENGINE
    %% ============================================================

    % --- Evaluate FLC for Pan axis ---
    Vel_Pan = mamdaniFLC(e_pan_deg, de_pan_filt, defuzz_resolution);
    Vel_Pan = Vel_Pan * output_gain;

    % --- Evaluate FLC for Tilt axis ---
    Vel_Tilt = mamdaniFLC(e_tilt_deg, de_tilt_filt, defuzz_resolution);
    Vel_Tilt = Vel_Tilt * output_gain;

    %% POSITION UPDATE
    TargetPan  = CurrentPan  + Vel_Pan  * dt;
    TargetTilt = CurrentTilt + Vel_Tilt * dt;

    % Apply mechanical limits
    TargetPan  = max(-pan_limit, min(pan_limit, TargetPan));
    TargetTilt = max(-90, min(90, TargetTilt));

    %% STATE UPDATE
    FSM_State.mode             = current_mode;
    FSM_State.I_pan            = 0;  % FLC has no integrator (anti-windup by design)
    FSM_State.I_tilt           = 0;
    FSM_State.e_pan_prev       = e_pan_deg;
    FSM_State.e_tilt_prev      = e_tilt_deg;
    FSM_State.de_pan_filtered  = de_pan_filt;
    FSM_State.de_tilt_filtered = de_tilt_filt;
    FSM_State.search_phase     = search_phase;

    %% DEBUG OUTPUT
    DebugInfo.mode          = current_mode;
    DebugInfo.e_pan_deg     = e_pan_deg;
    DebugInfo.e_tilt_deg    = e_tilt_deg;
    DebugInfo.de_pan_filt   = de_pan_filt;
    DebugInfo.de_tilt_filt  = de_tilt_filt;
    DebugInfo.vel_pan       = Vel_Pan;
    DebugInfo.vel_tilt      = Vel_Tilt;
    DebugInfo.target_pan    = TargetPan;
    DebugInfo.target_tilt   = TargetTilt;
    DebugInfo.is_locked     = (abs(e_pan_deg) < 0.5 && abs(e_tilt_deg) < 0.5);
    DebugInfo.is_flip       = is_flip;
    DebugInfo.V_total       = V_total;
    DebugInfo.is_dark       = is_dark;
    DebugInfo.zenith_factor = zenith_factor;
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
    % Concentrates resolution near zero for tracking precision
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

    % Evaluate all MFs for error
    mu_err = zeros(1, 7);
    for k = 1:7
        params = err_mf.(mf_names{k});
        if length(params) == 4
            mu_err(k) = evalTrapmf(error_deg, params);
        else
            mu_err(k) = evalTrimf(error_deg, params);
        end
    end

    % Evaluate all MFs for error rate
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
    % Rules(i,j) = output MF index when Error=i, Rate=j
    % Indices: 1=NB, 2=NM, 3=NS, 4=ZE, 5=PS, 6=PM, 7=PB
    %
    % Diagonal-inverse logic:
    %   Same sign (error & rate) → push hard (moving away from target)
    %   Opposite sign → brake (approaching target, prevent overshoot)

    Rules = [
    %   Rate: NB  NM  NS  ZE  PS  PM  PB     ← Error Rate
             1,  1,  1,  1,  2,  3,  4;  % NB  ← Error
             1,  1,  2,  2,  3,  4,  5;  % NM
             1,  2,  3,  3,  4,  5,  6;  % NS
             1,  2,  3,  4,  5,  6,  7;  % ZE
             2,  3,  4,  5,  5,  6,  7;  % PS
             3,  4,  5,  6,  6,  7,  7;  % PM
             4,  5,  6,  7,  7,  7,  7;  % PB
    ];

    %% 4. INFERENCE (Min-Max Mamdani)
    % For each rule, compute firing strength = min(mu_err(i), mu_rate(j))
    % Then aggregate: for each output MF, take max of all rules pointing to it.

    agg_strength = zeros(1, 7);  % Max firing strength per output MF

    for i = 1:7
        for j = 1:7
            firing = min(mu_err(i), mu_rate(j));
            out_idx = Rules(i, j);
            agg_strength(out_idx) = max(agg_strength(out_idx), firing);
        end
    end

    %% 5. DEFUZZIFICATION (Centroid / Center of Gravity)
    % Discretize output universe and compute weighted centroid

    out_range = linspace(-20, 20, N_points);
    aggregated = zeros(1, N_points);

    for k = 1:7
        if agg_strength(k) < 1e-8
            continue;  % Skip inactive MFs
        end
        params = out_mf.(mf_names{k});
        for p = 1:N_points
            if length(params) == 4
                mu_p = evalTrapmf(out_range(p), params);
            else
                mu_p = evalTrimf(out_range(p), params);
            end
            % Clip MF at firing strength (Mamdani implication)
            clipped = min(mu_p, agg_strength(k));
            % Max aggregation
            aggregated(p) = max(aggregated(p), clipped);
        end
    end

    % Centroid calculation
    total_area = sum(aggregated);
    if total_area > 1e-8
        vel_out = sum(out_range .* aggregated) / total_area;
    else
        vel_out = 0;  % No rules fired → stay still
    end
end

%% ================================================================
%% MEMBERSHIP FUNCTION EVALUATORS
%% ================================================================

function mu = evalTrimf(x, params)
% EVALTRIMF - Evaluate triangular membership function
%   params = [a, b, c] where a < b < c
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
% EVALTRAPMF - Evaluate trapezoidal membership function
%   params = [a, b, c, d] where a < b <= c < d
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
