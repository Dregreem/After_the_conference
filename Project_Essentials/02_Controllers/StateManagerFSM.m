function [ErrorSignal, FSM_State, DebugInfo, props] = StateManagerFSM(LDR_V, S_body, CurrentPan, CurrentTilt, FSM_State, Params, dt, is_flip)
% STATEMANAGERFSM - Supervisor Block (Block A)
% Move-and-Sleep FSM with 5 states: IDLE, PARK, SEARCH, HOLD, TRACKING
    
    %% PARAMETER EXTRACTION
    if nargin < 6 || isempty(Params), Params = struct(); end
    if nargin < 8 || isempty(is_flip), is_flip = false; end

   % FSM thresholds (owned by StateManagerFSM)
    % FSM thresholds (owned by StateManagerFSM)
    night_threshold      = getFieldOrDefault(Params, 'night_threshold', 0.3);
    sun_lost_threshold   = getFieldOrDefault(Params, 'sun_lost_threshold', 0.5);   % Added for cloud cover recovery
    sun_found_threshold  = getFieldOrDefault(Params, 'sun_found_threshold', 1.0);  % Added for search completion
    tracking_deadband    = getFieldOrDefault(Params, 'tracking_deadband', 3.0);    % Wake up when the sun drifts 3° away
    lock_threshold       = getFieldOrDefault(Params, 'lock_threshold', 0.5);       % 0s minimum sleep (wake up INSTANTLY if error > 3°)
    batch_interval       = getFieldOrDefault(Params, 'batch_interval', 1.5);     % Must be within 0.5° of the sun to be considered "on target"
    max_burst_time       = getFieldOrDefault(Params, 'max_burst_time', 5.0);      % Must stay on target for exactly 10 seconds before shutting off motors
    search_speed         = getFieldOrDefault(Params, 'search_speed', 3.0);
    zenith_pan_lock      = getFieldOrDefault(Params, 'zenith_pan_lock', false);
    tau_derivative       = getFieldOrDefault(Params, 'tau_derivative', 2.0);       % EMA time constant [s] — dt-invariant
    % Expose owned parameters via props struct
    props = struct();
    props.NightThreshold = night_threshold;
    props.TrackingDeadband = tracking_deadband;
    props.LockThreshold = lock_threshold;
    props.BatchInterval = batch_interval;
    props.MaxBurstTime = max_burst_time;
    props.SearchSpeed = search_speed;
    props.ZenithPanLock = zenith_pan_lock;
    props.TauDerivative = tau_derivative;

    %% STATE INITIALIZATION WITH ensureField
    if isempty(FSM_State)
        FSM_State = struct('mode', 'IDLE', ...
                           'e_pan_prev', 0, 'e_tilt_prev', 0, ...
                           'de_pan_filtered', 0, 'de_tilt_filtered', 0, ...
                           'search_phase', 0, ...
                           'hold_timer', 0, ...
                           'burst_timer', 0, ...
                           'was_night', false, ...
                           'park_target_pan', 0, ...
                           'park_target_tilt', 90);
    end
    
    % Use ensureField to safely initialize new fields on first call or old state
    FSM_State = ensureField(FSM_State, 'hold_timer', 0);
    FSM_State = ensureField(FSM_State, 'burst_timer', 0);
    FSM_State = ensureField(FSM_State, 'was_night', false);
    FSM_State = ensureField(FSM_State, 'park_target_pan', 0);
    FSM_State = ensureField(FSM_State, 'park_target_tilt', 90);

    current_mode   = getFieldOrDefault(FSM_State, 'mode', 'IDLE');
    search_phase   = getFieldOrDefault(FSM_State, 'search_phase', 0);
    e_pan_prev     = getFieldOrDefault(FSM_State, 'e_pan_prev', 0);
    e_tilt_prev    = getFieldOrDefault(FSM_State, 'e_tilt_prev', 0);
    de_pan_filt    = getFieldOrDefault(FSM_State, 'de_pan_filtered', 0);
    de_tilt_filt   = getFieldOrDefault(FSM_State, 'de_tilt_filtered', 0);
    hold_timer     = getFieldOrDefault(FSM_State, 'hold_timer', 0);
    burst_timer    = getFieldOrDefault(FSM_State, 'burst_timer', 0);
    was_night      = getFieldOrDefault(FSM_State, 'was_night', false);

    %% ============================================================
    %% SENSOR-BASED ERROR CALCULATION (Tangent Law)
    %% ============================================================

    epsilon = 0.001;  % Prevent division by zero

    if ~isempty(LDR_V) && length(LDR_V) >= 4
        V_R = LDR_V(1);  V_L = LDR_V(2);
        V_U = LDR_V(3);  V_D = LDR_V(4);
        V_total = sum(LDR_V);
    else
        V_R = 0; V_L = 0; V_U = 0; V_D = 0;
        V_total = 0;
    end

    % Normalized differential (Tangent Law)
    sum_pan  = V_L + V_R + epsilon;
    sum_tilt = V_U + V_D + epsilon;

    e_pan_normalized  = (V_L - V_R) / sum_pan;
    e_tilt_normalized = (V_U - V_D) / sum_tilt;

    % arctangent mapping — matches report Section 3
    e_pan_deg_raw  = atand(e_pan_normalized  * tan(deg2rad(60)));
    e_tilt_deg_raw = atand(e_tilt_normalized * tan(deg2rad(60)));

    % Flip correction
    if is_flip
        e_pan_deg = -e_pan_deg_raw;
    else
        e_pan_deg = e_pan_deg_raw;
    end
    e_tilt_deg = e_tilt_deg_raw;
    
   % Total error magnitude (for FSM transitions)
    % OVERRIDE: Use true geometric incidence to prevent Zenith LDR blindness
    S_body_norm = S_body / (norm(S_body) + 1e-8);
    e_total = acosd(max(-1.0, min(1.0, S_body_norm(3))));

    %% ============================================================
    %% DARKNESS DETECTION & PARK MODE
    %% ============================================================

    is_dark = (V_total < night_threshold);
    
    % Track transition from day to night
    if is_dark && ~was_night
        was_night = true;  % Just entered night
        current_mode = 'IDLE';
        hold_timer = 0;
        burst_timer = 0;
    elseif ~is_dark && was_night
        was_night = false;  % Just entered day
    end

    %% ============================================================
    %% FIVE-STATE FSM: IDLE, SEARCH, HOLD, TRACKING
    %% ============================================================

   %% ============================================================
    %% FIVE-STATE FSM: IDLE, PARK, SEARCH, HOLD, TRACKING
    %% ============================================================

    switch current_mode
        
        case 'IDLE'
            % ──── IDLE: No movement, waiting for day or recovery ────
            e_pan_deg = 0; e_tilt_deg = 0; 
            de_pan_filt = 0; de_tilt_filt = 0;
            
            if ~is_dark
                % Dawn/Recovery: transition to SEARCH
                current_mode = 'SEARCH';
                search_phase = 0;
            else
                current_mode = 'IDLE';
            end
        
        case 'SEARCH'
            % ──── SEARCH: Spiral scan for the sun ────
            search_phase = search_phase + dt;
            MAX_SPIRAL_RADIUS = 20.0;                    % Hard cap [degrees]
            MAX_SEARCH_TIME   = 300.0;                   % Timeout [s] — give up after 5 min
            spiral_radius = min(MAX_SPIRAL_RADIUS, 0.1 * search_phase);
            
            % Override error with search pattern (bounded spiral)
            e_pan_deg  = spiral_radius * cos(search_phase * 2 * pi);
            e_tilt_deg = spiral_radius * sin(search_phase * 2 * pi);

            % Transition logic
            if search_phase > MAX_SEARCH_TIME
                % Search timeout — sun not found after 5 minutes, park and wait
                current_mode = 'IDLE';
                search_phase = 0;
                hold_timer = 0;
                burst_timer = 0;
            elseif V_total > sun_found_threshold  
                % SUN INTENSITY FOUND → enter TRACKING
                current_mode = 'TRACKING';
                search_phase = 0;
                hold_timer = 0;
                burst_timer = 0;
            else
                current_mode = 'SEARCH';
            end

        case 'HOLD'
            % ──── HOLD: Motors de-energized, saving power ────
            e_pan_deg = 0; 
            e_tilt_deg = 0; 
            de_pan_filt = 0; 
            de_tilt_filt = 0;
            
            hold_timer = hold_timer + dt;
            burst_timer = 0; % Ensure burst timer resets while sleeping
            
            % WAKE UP CONDITION: The sun has moved and the error is BIG again.
            if is_dark
                current_mode = 'IDLE';
                hold_timer = 0;
            elseif (e_total > tracking_deadband) && (hold_timer >= batch_interval)
                % Error is big enough AND minimum sleep time is met -> Wake up
                current_mode = 'TRACKING';
                hold_timer = 0;
                burst_timer = 0;
            else
                current_mode = 'HOLD';
            end
        
        case 'TRACKING'
            % ──── TRACKING: Motors actively following the sun ────
            
            % SLEEP CHECK: Are we perfectly on target?
            if e_total < lock_threshold
                % We are on target! Start the 5-second "stuck" timer.
                burst_timer = burst_timer + dt;
            else
                % We are still hunting/moving. Keep timer at 0.
                burst_timer = 0;
            end
            
            % Check transitions
            if V_total < sun_lost_threshold
                current_mode = 'SEARCH';
                search_phase = 0;
                hold_timer = 0;
                burst_timer = 0;
            elseif burst_timer > max_burst_time
                % BURST TIMEOUT — Forced transition to HOLD (energy protection against hunting)
                % This ensures motors stop even if micro-oscillations prevent perfect lock.
                % Reset hold_timer so we force a brief sleep before resuming.
                current_mode = 'HOLD';
                hold_timer = 0;   % Force reset of hold timer
                burst_timer = 0;
            else
                current_mode = 'TRACKING';
            end
        
        otherwise
            % Fallback recovery
            current_mode = 'SEARCH';
            search_phase = 0;
    end

    %% ============================================================
    %% ZENITH / HORIZON SAFETY LIMITS
    %% ============================================================

    ZENITH_START  = 75;
    ZENITH_CUTOFF = 88;

    zenith_factor = 1.0;
    if zenith_pan_lock && CurrentTilt > ZENITH_CUTOFF
        % GIMBAL LOCK PROTECTION: freeze pan
        e_pan_deg   = 0;
        de_pan_filt = 0;
        zenith_factor = 0.0;
    elseif zenith_pan_lock && CurrentTilt > ZENITH_START
        % Smooth transition
        zenith_factor = (90 - CurrentTilt) / (90 - ZENITH_START);
        e_pan_deg   = e_pan_deg * zenith_factor;
        de_pan_filt = de_pan_filt * zenith_factor;
    end

    HORIZON_CUTOFF = -5;
    if e_tilt_deg < HORIZON_CUTOFF
        e_tilt_deg  = 0;
        de_tilt_filt = 0;
    end

    %% ============================================================
    %% ERROR RATE COMPUTATION (EMA-Filtered Derivative)
    %% ============================================================

    if dt > 0
        de_pan_raw  = (e_pan_deg  - e_pan_prev)  / dt;
        de_tilt_raw = (e_tilt_deg - e_tilt_prev) / dt;
    else
        de_pan_raw  = 0;
        de_tilt_raw = 0;
    end

    % EMA filter with dt-invariant time constant
    % tau_derivative = 2.0 s gives alpha ≈ 0.995 at dt=0.01s and alpha ≈ 0.607 at dt=1.0s
    % Both filters (100 Hz and 1 Hz) converge to the same physical filter dynamics
    ema_alpha = exp(-dt / (tau_derivative + 1e-12));
    de_pan_filt  = ema_alpha * de_pan_filt  + (1 - ema_alpha) * de_pan_raw;
    de_tilt_filt = ema_alpha * de_tilt_filt + (1 - ema_alpha) * de_tilt_raw;

    %% ============================================================
    %% OUTPUT: ErrorSignal struct
    %% ============================================================

    ErrorSignal = struct( ...
        'e_pan',  e_pan_deg, ...
        'e_tilt', e_tilt_deg, ...
        'de_pan', de_pan_filt, ...
        'de_tilt', de_tilt_filt, ...
        'mode',   current_mode);

    %% STATE PERSISTENCE
    FSM_State.mode             = current_mode;
    FSM_State.e_pan_prev       = e_pan_deg;
    FSM_State.e_tilt_prev      = e_tilt_deg;
    FSM_State.de_pan_filtered  = de_pan_filt;
    FSM_State.de_tilt_filtered = de_tilt_filt;
    FSM_State.search_phase     = search_phase;
    FSM_State.hold_timer       = hold_timer;
    FSM_State.burst_timer      = burst_timer;
    FSM_State.was_night        = was_night;

    %% DEBUG OUTPUT
    DebugInfo.mode          = current_mode;
    DebugInfo.e_pan_deg     = e_pan_deg;
    DebugInfo.e_tilt_deg    = e_tilt_deg;
    DebugInfo.de_pan_filt   = de_pan_filt;
    DebugInfo.de_tilt_filt  = de_tilt_filt;
    DebugInfo.is_locked     = (e_total < lock_threshold);
    DebugInfo.is_flip       = is_flip;
    DebugInfo.V_total       = V_total;
    DebugInfo.is_dark       = is_dark;
    DebugInfo.zenith_factor = zenith_factor;
    DebugInfo.hold_timer    = hold_timer;
    DebugInfo.burst_timer   = burst_timer;
    DebugInfo.e_total       = e_total;

end

%% ================================================================
%% HELPER FUNCTIONS
%% ================================================================

function value = getFieldOrDefault(s, field, default)
    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end

function s = ensureField(s, field, default)
    % Initialize field to default value if it doesn't exist
    if ~isfield(s, field)
        s.(field) = default;
    end
end
