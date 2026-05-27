function [TargetPan, TargetTilt, FSM_State, DebugInfo] = fsmController(LDR_V, S_body, CurrentPan, CurrentTilt, FSM_State, Params, dt, is_flip)
% FSMCONTROLLER_OPTIMIZED - Sensor-Based Tracking with Darkness Detection & State Machine
% FIX v2.0: ENABLES ACTUAL LDR SENSORS (Tangent Law), Darkness Logic, FSM Transitions
    
    %% PARAMETER EXTRACTION
    if nargin < 6 || isempty(Params), Params = struct(); end
    if nargin < 8 || isempty(is_flip), is_flip = false; end
    
    Kp = getFieldOrDefault(Params, 'Kp_vel', 0.25);
    Ki = getFieldOrDefault(Params, 'Ki_vel', 0.04);
    vel_limit = getFieldOrDefault(Params, 'max_tracking_velocity', 15.0);
    max_integral = getFieldOrDefault(Params, 'max_integral', 10);
    zenith_pan_lock = getFieldOrDefault(Params, 'zenith_pan_lock', false);
    
    % ✅ FIX #2: Extract darkness threshold from Params
    night_threshold = getFieldOrDefault(Params, 'night_threshold', 0.3);
    search_speed = getFieldOrDefault(Params, 'search_speed', 3.0);
    
    %% STATE INITIALIZATION
    if isempty(FSM_State)
        FSM_State = struct('mode', 'TRACKING', 'I_pan', 0, 'I_tilt', 0, 'search_phase', 0);
    end
    
    I_pan = getFieldOrDefault(FSM_State, 'I_pan', 0);
    I_tilt = getFieldOrDefault(FSM_State, 'I_tilt', 0);
    current_mode = getFieldOrDefault(FSM_State, 'mode', 'TRACKING');
    search_phase = getFieldOrDefault(FSM_State, 'search_phase', 0);
    
    %% ============================================================
    %% ✅ FIX #1: SENSOR-BASED ERROR CALCULATION (Tangent Law)
    %% ============================================================
    % Instead of using S_body truth, use actual LDR voltage readings
    % This implements the differential sensing method from your report
    
    epsilon = 0.001;  % Prevent division by zero
    
    % Extract individual LDR voltages from LDR_V vector
    % Format: [V_Right, V_Left, V_Up, V_Down]
    if ~isempty(LDR_V) && length(LDR_V) >= 4
        V_R = LDR_V(1);
        V_L = LDR_V(2);
        V_U = LDR_V(3);
        V_D = LDR_V(4);
        V_total = sum(LDR_V);
    else
        % Fallback if LDR not available
        V_R = 0; V_L = 0; V_U = 0; V_D = 0;
        V_total = 0;
    end
    
    % Tangent Law: Error proportional to voltage difference ratio
    % This is YOUR differential sensing method from Section 3
    sum_pan = V_L + V_R + epsilon;
    sum_tilt = V_U + V_D + epsilon;
    
    e_pan_normalized = (V_L - V_R) / sum_pan;      % [-1, +1] normalized
    e_tilt_normalized = (V_U - V_D) / sum_tilt;    % [-1, +1] normalized
    
    % Convert to angular error using tangent-law (matches report)
    % Maximum angular error ≈ ±45° when one sensor sees sun, other sees darkness
    % Use arctangent mapping instead of linear scaling for large-error accuracy
    e_pan_deg_raw = atand(e_pan_normalized ./ tan(deg2rad(60)));
    e_tilt_deg_raw = atand(e_tilt_normalized ./ tan(deg2rad(60)));
    
    if is_flip
        e_pan_deg = -e_pan_deg_raw;
    else
        e_pan_deg = e_pan_deg_raw;
    end
    e_tilt_deg = e_tilt_deg_raw;
    
    %% ============================================================
    %% ✅ FIX #2: DARKNESS DETECTION & STATE MACHINE TRANSITIONS
    %% ============================================================
    % Implement the FSM from your report: IDLE → SEARCH → TRACKING → IDLE
    
    % DARKNESS CHECK: If V_total < threshold, night has fallen
    is_dark = (V_total < night_threshold);
    
    % STATE TRANSITIONS
    if is_dark
        % NIGHT MODE: Transition to IDLE and park motors
        current_mode = 'IDLE';
        e_pan_deg = 0;     % Zero out errors to stop motion
        e_tilt_deg = 0;
        I_pan = 0;         % Reset integrators
        I_tilt = 0;
        
    elseif strcmp(current_mode, 'IDLE') && ~is_dark
        % DAWN TRANSITION: Sun reappeared, wake up and search
        current_mode = 'SEARCH';
        search_phase = 0;
        
    elseif strcmp(current_mode, 'SEARCH')
        % SEARCH MODE: Spiral scan to find sun
        % Simple implementation: Slow spiral until sun lock
        search_phase = search_phase + dt;
        spiral_radius = 0.1 * search_phase;  % Gradually widen spiral
        search_pan = spiral_radius * cos(search_phase * 2 * pi);
        search_tilt = spiral_radius * sin(search_phase * 2 * pi);
        
        % Use search pattern until lock
        if (abs(e_pan_deg) < 1.0 && abs(e_tilt_deg) < 1.0)
            % SUN FOUND: Transition to tracking
            current_mode = 'TRACKING';
            search_phase = 0;
        else
            % Still searching: Override error with search pattern
            e_pan_deg = search_pan;
            e_tilt_deg = search_tilt;
        end
        
    else  % TRACKING mode
        % Normal servo tracking (implemented below)
        % Do nothing special here - use the sensor-based errors
        current_mode = 'TRACKING';
    end
    
    %% ============================================================
    %% EDGE CASE HANDLING (Angular Limits & Zenith Protection)
    %% ============================================================
    ZENITH_START = 75;  % REDUCED from 60 (earlier zenith engagement)
    ZENITH_CUTOFF = 88; % INCREASED from 85 (higher angle for gimbal protection)
    
    if zenith_pan_lock && CurrentTilt > ZENITH_CUTOFF
        % GIMBAL LOCK PROTECTION: Freeze pan completely
        e_pan_deg = 0;
        I_pan = 0;
    elseif zenith_pan_lock && CurrentTilt > ZENITH_START
        % ZENITH TRANSITION: Gradually reduce pan influence (smooth transition)
        zenith_factor = (90 - CurrentTilt) / (90 - ZENITH_START);
        e_pan_deg = e_pan_deg * zenith_factor;
        I_pan = I_pan * zenith_factor;
    end
    % If zenith_pan_lock=false: NO PAN LOCKING - allows full pan movement at zenith
    
    HORIZON_CUTOFF = -5;
    if e_tilt_deg < HORIZON_CUTOFF
        e_tilt_deg = 0;
        I_tilt = 0;
    end
    
    %% VELOCITY-BASED PID CONTROL
    I_pan = I_pan + e_pan_deg * dt;
    I_pan = max(-max_integral, min(max_integral, I_pan));
    Vel_Pan_raw = Kp * e_pan_deg + Ki * I_pan;
    Vel_Pan = vel_limit * tanh(Vel_Pan_raw / vel_limit);
    
    I_tilt = I_tilt + e_tilt_deg * dt;
    I_tilt = max(-max_integral, min(max_integral, I_tilt));
    Vel_Tilt_raw = Kp * e_tilt_deg + Ki * I_tilt;
    Vel_Tilt = vel_limit * tanh(Vel_Tilt_raw / vel_limit);
    
    %% POSITION UPDATE
    TargetPan = CurrentPan + Vel_Pan * dt;
    TargetTilt = CurrentTilt + Vel_Tilt * dt;
    % Apply configurable pan/tilt limits (default pan_limit=90 deg)
    pan_limit = getFieldOrDefault(Params, 'pan_limit', 90);
    TargetPan = max(-pan_limit, min(pan_limit, TargetPan));
    TargetTilt = max(-90, min(90, TargetTilt));
    
    %% STATE UPDATE
    FSM_State.mode = current_mode;
    FSM_State.I_pan = I_pan;
    FSM_State.I_tilt = I_tilt;
    FSM_State.e_pan_prev = e_pan_deg;
    FSM_State.e_tilt_prev = e_tilt_deg;
    FSM_State.search_phase = search_phase;  % ✅ Save search progress for continuous spiral
    
    %% DEBUG OUTPUT
    DebugInfo.mode = current_mode;
    DebugInfo.e_pan_deg = e_pan_deg;
    DebugInfo.e_tilt_deg = e_tilt_deg;
    DebugInfo.vel_pan = Vel_Pan;
    DebugInfo.vel_tilt = Vel_Tilt;
    DebugInfo.target_pan = TargetPan;
    DebugInfo.target_tilt = TargetTilt;
    DebugInfo.is_locked = (abs(e_pan_deg) < 0.5 && abs(e_tilt_deg) < 0.5);
    DebugInfo.is_flip = is_flip;
    DebugInfo.V_total = V_total;  % ✅ Log total voltage for darkness analysis
    DebugInfo.is_dark = is_dark;  % ✅ Log darkness state
end

function value = getFieldOrDefault(s, field, default)
    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end