function [VelocityCommand, ControlState, DebugInfo, props] = PID_VelocityController(ErrorSignal, ControlState, Params, dt)
% ═══════════════════════════════════════════════════════════════════════════
% PID_VELOCITYCONTROLLER — Velocity-based PID Controller (Block B)
%
% PURPOSE:
%   Implements 3-term PID control for dual-axis solar tracker servos.
%   Accepts pan/tilt error signals from Supervisor and outputs velocity commands.
%   Includes anti-windup integration and derivative filtering for robustness.
%
% INPUTS:
%   ErrorSignal  - struct {e_pan, e_tilt, de_pan, de_tilt, mode} from Supervisor
%   ControlState - struct {I_pan, I_tilt, de_pan_filt, de_tilt_filt} persistent state
%   Params       - struct {max_tracking_velocity} — scenario-based override (optional)
%   dt           - control time step [seconds]
%
% OUTPUTS:
%   VelocityCommand - struct {v_pan, v_tilt} velocity commands [deg/s]
%   ControlState    - updated integrator and filter state
%   DebugInfo       - struct with P, I, D term breakdown for logging
%
% ASSUMPTIONS:
%   - Error signals from Supervisor are already rate-limited (de_pan/de_tilt < 30 deg/s)
%   - Input error range: [-180, 180] degrees for pan, [-90, 90] for tilt
%   - Velocity saturation via hyperbolic tangent (smooth, non-windup)
%
% REFERENCES:
%   - Åström & Hägglund (2006): PID Controllers – Theory and Applications
%   - Baker et al. (2017): Anti-windup techniques for continuous-time plants
%
% Author  : Kerem Bayer (Master's Thesis, 2024)
% Created : 2026-02-21
% Architecture: 3-Block (Supervisor → Controller → Plant Physics)
% ═══════════════════════════════════════════════════════════════════════════

    %% ════════════════════════════════════════════════════════════════════════
    %% PID COEFFICIENTS (Optimized Champions — Locked)
    %% ════════════════════════════════════════════════════════════════════════
    
    % These gains were optimized via genetic algorithm and validated on
    % 100+ simulation scenarios. DO NOT CHANGE without re-tuning.
    Kp = 3.1880;          % Proportional gain (deg/s per deg error)
    Ki = 10.3173;         % Integral gain (deg/s per deg·sec)
    Kd = 0.0;             % Derivative gain (deg/s per deg/s error rate)
    
    %% ════════════════════════════════════════════════════════════════════════
    %% CONTROLLER PARAMETERS
    %% ════════════════════════════════════════════════════════════════════════
    
    if nargin < 3 || isempty(Params), Params = struct(); end
    
    % Scenario-based velocity limit (can be overridden by scenario)
    vel_limit = getFieldOrDefault(Params, 'max_tracking_velocity', 15.0);
    
    % Controller internals (tuned for stability)
    max_integral = 10;      % Anti-windup clamp for integrator (prevents saturation)
    N = 0.3;                % Derivative filter coefficient (first-order low-pass, attenuates noise)

    % Expose owned parameters via props struct
    props = struct();
    props.Kp = Kp;
    props.Ki = Ki;
    props.Kd = Kd;
    props.MaxIntegral = max_integral;
    props.DerivativeFilter = N;
    props.MaxTrackingVelocity = vel_limit;

    %% STATE INITIALIZATION
    if isempty(ControlState)
        ControlState = struct('I_pan', 0, 'I_tilt', 0, ...
                              'de_pan_filt', 0, 'de_tilt_filt', 0);
    end

    I_pan  = getFieldOrDefault(ControlState, 'I_pan', 0);
    I_tilt = getFieldOrDefault(ControlState, 'I_tilt', 0);
    de_pan_filt_prev = getFieldOrDefault(ControlState, 'de_pan_filt', 0);
    de_tilt_filt_prev = getFieldOrDefault(ControlState, 'de_tilt_filt', 0);

    %% EXTRACT ERROR SIGNALS
    e_pan  = ErrorSignal.e_pan;
    e_tilt = ErrorSignal.e_tilt;
    de_pan  = ErrorSignal.de_pan;
    de_tilt = ErrorSignal.de_tilt;

    % If Supervisor says IDLE or HOLD, zero the integrators and output zero velocity
    if strcmp(ErrorSignal.mode, 'IDLE') || strcmp(ErrorSignal.mode, 'HOLD')
        I_pan  = 0;
        I_tilt = 0;
        de_pan_filt_prev = 0;
        de_tilt_filt_prev = 0;
        VelocityCommand = struct('v_pan', 0, 'v_tilt', 0);
        ControlState.I_pan  = 0;
        ControlState.I_tilt = 0;
        ControlState.de_pan_filt = 0;
        ControlState.de_tilt_filt = 0;
        DebugInfo = struct('P_pan', 0, 'I_pan', 0, 'D_pan', 0, ...
                           'P_tilt', 0, 'I_tilt', 0, 'D_tilt', 0, ...
                           'vel_pan', 0, 'vel_tilt', 0);
        % props already populated above
        return;
    end

    %% PAN AXIS — PID CONTROL WITH BACK-CALCULATION ANTI-WINDUP
    
    % Integral with anti-windup clamping (prevent saturation)
    I_pan = I_pan + e_pan * dt;
    I_pan = max(-max_integral, min(max_integral, I_pan));

    % Derivative filter — only compute if Kd is active (avoid wasted cycles & instability)
    if Kd ~= 0
        % First-order low-pass filter for derivative (noise attenuation)
        % Tustin-discretized with time constant tau_d = 1/N
        % This makes the filter dt-consistent across different control rates
        tau_d = 1.0 / N;
        alpha_d = tau_d / (tau_d + dt);
        de_pan_filt_new = alpha_d * de_pan_filt_prev + (1 - alpha_d) * de_pan;
        D_pan = Kd * de_pan_filt_new;
    else
        de_pan_filt_new = de_pan_filt_prev;  % Hold previous value (no filtering)
        D_pan = 0;
    end

    % PID terms (raw, before saturation)
    P_pan = Kp * e_pan;
    I_pan_term = Ki * I_pan;
    Vel_Pan_raw = P_pan + I_pan_term + D_pan;

    % Smooth velocity saturation via tanh
    Vel_Pan_sat = vel_limit * tanh(Vel_Pan_raw / vel_limit);

    % Back-calculation anti-windup: compute saturation error and feedback to integrator
    % This prevents integrator windup by reducing the integral term contribution
    % when the output cannot follow the command
    Kt_pan = 1.0 / Ki;   % Anti-windup tracking gain (standard: 1/Ki)
    windup_error_pan = Vel_Pan_sat - Vel_Pan_raw;
    
    % Update integrator with back-calculated windup compensation
    I_pan = I_pan + Kt_pan * windup_error_pan * dt;
    I_pan = max(-max_integral, min(max_integral, I_pan));
    
    Vel_Pan = Vel_Pan_sat;

    %% TILT AXIS — PID CONTROL WITH BACK-CALCULATION ANTI-WINDUP
    
    I_tilt = I_tilt + e_tilt * dt;
    I_tilt = max(-max_integral, min(max_integral, I_tilt));

    % Derivative filter — only compute if Kd is active
    if Kd ~= 0
        tau_d = 1.0 / N;
        alpha_d = tau_d / (tau_d + dt);
        de_tilt_filt_new = alpha_d * de_tilt_filt_prev + (1 - alpha_d) * de_tilt;
        D_tilt = Kd * de_tilt_filt_new;
    else
        de_tilt_filt_new = de_tilt_filt_prev;
        D_tilt = 0;
    end

    P_tilt = Kp * e_tilt;
    I_tilt_term = Ki * I_tilt;
    Vel_Tilt_raw = P_tilt + I_tilt_term + D_tilt;

    % Smooth velocity saturation via tanh
    Vel_Tilt_sat = vel_limit * tanh(Vel_Tilt_raw / vel_limit);

    % Back-calculation anti-windup
    Kt_tilt = 1.0 / Ki;   % Anti-windup tracking gain
    windup_error_tilt = Vel_Tilt_sat - Vel_Tilt_raw;
    
    % Update integrator with back-calculated windup compensation
    I_tilt = I_tilt + Kt_tilt * windup_error_tilt * dt;
    I_tilt = max(-max_integral, min(max_integral, I_tilt));
    
    Vel_Tilt = Vel_Tilt_sat;

    %% OUTPUT VELOCITY COMMANDS
    VelocityCommand = struct('v_pan', Vel_Pan, 'v_tilt', Vel_Tilt);

    %% STATE PERSISTENCE
    ControlState.I_pan  = I_pan;
    ControlState.I_tilt = I_tilt;
    ControlState.de_pan_filt = de_pan_filt_new;
    ControlState.de_tilt_filt = de_tilt_filt_new;

    %% DEBUG INFORMATION
    DebugInfo = struct( ...
        'P_pan', P_pan, 'I_pan', I_pan_term, 'D_pan', D_pan, ...
        'P_tilt', P_tilt, 'I_tilt', I_tilt_term, 'D_tilt', D_tilt, ...
        'vel_pan', Vel_Pan, 'vel_tilt', Vel_Tilt, ...
        'de_pan_filt', de_pan_filt_new, 'de_tilt_filt', de_tilt_filt_new);

end

%% ═══════════════════════════════════════════════════════════════════════════
%% HELPER FUNCTION
%% ═══════════════════════════════════════════════════════════════════════════

function value = getFieldOrDefault(s, field, default)
    % ─────────────────────────────────────────────────────────────────────
    % GETFIELDORDEFAULT — Safe struct field access with optional default
    % ─────────────────────────────────────────────────────────────────────
    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end
