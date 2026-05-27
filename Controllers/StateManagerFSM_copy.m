function [ErrorSignal, FSM_State, DebugInfo, props] = StateManagerFSM_copy(LDR_V, S_body, CurrentPan, CurrentTilt, FSM_State, Params, dt, is_flip)
% STATEMANAGERFSM — Supervisor Block
% Move-and-Sleep FSM: IDLE → SEARCH → TRACKING ⇄ HOLD
%
% KEY FIX: e_total is read from FSM_State.e_total_prev (computed AFTER
% the servo inner-loop in CompareYield_TMY) so the HOLD trigger sees
% the true achieved alignment, not the pre-movement angle.

    %% PARAMETER EXTRACTION
    if nargin < 6 || isempty(Params),  Params  = struct(); end
    if nargin < 8 || isempty(is_flip), is_flip = false;    end

    night_threshold      = getFieldOrDefault(Params, 'night_threshold',     0.10);
    sun_lost_threshold   = getFieldOrDefault(Params, 'sun_lost_threshold',  0.15);
    sun_found_threshold  = getFieldOrDefault(Params, 'sun_found_threshold', 0.30);
    tracking_deadband    = getFieldOrDefault(Params, 'tracking_deadband',   6.0);
    lock_threshold       = getFieldOrDefault(Params, 'lock_threshold',      1.5);
    batch_interval       = getFieldOrDefault(Params, 'batch_interval',    300.0);
    max_burst_time       = getFieldOrDefault(Params, 'max_burst_time',      2.0);
    search_speed         = getFieldOrDefault(Params, 'search_speed',        3.0);  %#ok
    zenith_pan_lock      = getFieldOrDefault(Params, 'zenith_pan_lock',   false);
    tau_derivative       = getFieldOrDefault(Params, 'tau_derivative',      2.0);

    props = struct('NightThreshold',   night_threshold, ...
                   'TrackingDeadband', tracking_deadband, ...
                   'LockThreshold',    lock_threshold, ...
                   'BatchInterval',    batch_interval, ...
                   'MaxBurstTime',     max_burst_time, ...
                   'ZenithPanLock',    zenith_pan_lock, ...
                   'TauDerivative',    tau_derivative);

    %% STATE INITIALISATION
    if isempty(FSM_State)
        FSM_State = struct('mode','IDLE', ...
                           'e_pan_prev',0, 'e_tilt_prev',0, ...
                           'de_pan_filtered',0, 'de_tilt_filtered',0, ...
                           'search_phase',0, 'hold_timer',0, 'burst_timer',0, ...
                           'was_night',false, ...
                           'park_target_pan',0, 'park_target_tilt',90, ...
                           'e_total_prev', 90);
    end

    FSM_State = ensureField(FSM_State, 'hold_timer',      0);
    FSM_State = ensureField(FSM_State, 'burst_timer',     0);
    FSM_State = ensureField(FSM_State, 'was_night',       false);
    FSM_State = ensureField(FSM_State, 'park_target_pan', 0);
    FSM_State = ensureField(FSM_State, 'park_target_tilt',90);
    FSM_State = ensureField(FSM_State, 'e_total_prev',    90);  % large default = not locked

    current_mode = getFieldOrDefault(FSM_State, 'mode',          'IDLE');
    search_phase = getFieldOrDefault(FSM_State, 'search_phase',  0);
    e_pan_prev   = getFieldOrDefault(FSM_State, 'e_pan_prev',    0);
    e_tilt_prev  = getFieldOrDefault(FSM_State, 'e_tilt_prev',   0);
    de_pan_filt  = getFieldOrDefault(FSM_State, 'de_pan_filtered', 0);
    de_tilt_filt = getFieldOrDefault(FSM_State, 'de_tilt_filtered',0);
    hold_timer   = getFieldOrDefault(FSM_State, 'hold_timer',    0);
    burst_timer  = getFieldOrDefault(FSM_State, 'burst_timer',   0);
    was_night    = getFieldOrDefault(FSM_State, 'was_night',     false);

    %% LDR SIGNAL PARSING
    epsilon = 0.001;
    if ~isempty(LDR_V) && length(LDR_V) >= 4
        V_R = LDR_V(1); V_L = LDR_V(2);
        V_U = LDR_V(3); V_D = LDR_V(4);
        V_total = sum(LDR_V);
    else
        V_R = 0; V_L = 0; V_U = 0; V_D = 0; V_total = 0;
    end

    sum_pan  = V_L + V_R + epsilon;
    sum_tilt = V_U + V_D + epsilon;
    e_pan_normalized  = (V_L - V_R) / sum_pan;
    e_tilt_normalized = (V_U - V_D) / sum_tilt;

    e_pan_deg_raw  = atand(e_pan_normalized  * tan(deg2rad(60)));
    e_tilt_deg_raw = atand(e_tilt_normalized * tan(deg2rad(60)));

    if is_flip
        e_pan_deg = -e_pan_deg_raw;
    else
        e_pan_deg = e_pan_deg_raw;
    end
    e_tilt_deg = e_tilt_deg_raw;

    %% TRUE ALIGNMENT — use post-loop value fed back from CompareYield
    % This is the critical fix: e_total reflects achieved position AFTER
    % the servo inner-loop, not before. Enables accurate HOLD triggering.
    e_total = getFieldOrDefault(FSM_State, 'e_total_prev', ...
              acosd(max(-1.0, min(1.0, S_body(3)/(norm(S_body)+1e-8)))));

    %% DARKNESS DETECTION
    is_dark = (V_total < night_threshold);

    if is_dark && ~was_night
        was_night    = true;
        current_mode = 'IDLE';
        hold_timer   = 0;
        burst_timer  = 0;
    elseif ~is_dark && was_night
        was_night = false;
    end

    %% FSM SWITCH
    switch current_mode

        case 'IDLE'
            e_pan_deg = 0; e_tilt_deg = 0;
            de_pan_filt = 0; de_tilt_filt = 0;
            if ~is_dark
                current_mode = 'SEARCH';
                search_phase = 0;
            end

        case 'SEARCH'
            search_phase      = search_phase + dt;
            MAX_SPIRAL_RADIUS = 20.0;
            MAX_SEARCH_TIME   = 300.0;
            spiral_radius     = min(MAX_SPIRAL_RADIUS, 0.1 * search_phase);

            e_pan_deg  = spiral_radius * cos(search_phase * 2 * pi);
            e_tilt_deg = spiral_radius * sin(search_phase * 2 * pi);

            if search_phase > MAX_SEARCH_TIME
                current_mode = 'IDLE';
                search_phase = 0;
                hold_timer   = 0;
                burst_timer  = 0;
            elseif V_total > sun_found_threshold
                current_mode = 'TRACKING';
                search_phase = 0;
                hold_timer   = 0;
                burst_timer  = 0;
            end

        case 'HOLD'
            e_pan_deg   = 0; e_tilt_deg   = 0;
            de_pan_filt = 0; de_tilt_filt = 0;
            hold_timer  = hold_timer + dt;
            burst_timer = 0;

            if is_dark
                current_mode = 'IDLE';
                hold_timer   = 0;
            elseif (e_total > tracking_deadband) && (hold_timer >= batch_interval)
                current_mode = 'TRACKING';
                hold_timer   = 0;
                burst_timer  = 0;
            end
            % else: stay HOLD

        case 'TRACKING'
            % burst_timer accumulates while aligned, resets when misaligned
            if e_total < lock_threshold
                burst_timer = burst_timer + dt;
            else
                burst_timer = 0;
            end

            if V_total < sun_lost_threshold
                current_mode = 'SEARCH';
                search_phase = 0;
                hold_timer   = 0;
                burst_timer  = 0;
            elseif burst_timer >= max_burst_time
                % Aligned long enough → sleep motors
                current_mode = 'HOLD';
                hold_timer   = 0;
                burst_timer  = 0;
            end
            % else: stay TRACKING

        otherwise
            current_mode = 'SEARCH';
            search_phase = 0;
    end

    %% ZENITH / HORIZON SAFETY
    ZENITH_START  = 75;
    ZENITH_CUTOFF = 88;
    zenith_factor = 1.0;

    if zenith_pan_lock && CurrentTilt > ZENITH_CUTOFF
        e_pan_deg   = 0; de_pan_filt = 0; zenith_factor = 0.0;
    elseif zenith_pan_lock && CurrentTilt > ZENITH_START
        zenith_factor = (90 - CurrentTilt) / (90 - ZENITH_START);
        e_pan_deg   = e_pan_deg   * zenith_factor;
        de_pan_filt = de_pan_filt * zenith_factor;
    end

    if e_tilt_deg < -5
        e_tilt_deg  = 0; de_tilt_filt = 0;
    end

    %% DERIVATIVE (EMA-filtered)
    if dt > 0
        de_pan_raw  = (e_pan_deg  - e_pan_prev)  / dt;
        de_tilt_raw = (e_tilt_deg - e_tilt_prev) / dt;
    else
        de_pan_raw = 0; de_tilt_raw = 0;
    end

    ema_alpha    = exp(-dt / (tau_derivative + 1e-12));
    de_pan_filt  = ema_alpha * de_pan_filt  + (1 - ema_alpha) * de_pan_raw;
    de_tilt_filt = ema_alpha * de_tilt_filt + (1 - ema_alpha) * de_tilt_raw;

    %% OUTPUTS
    ErrorSignal = struct('e_pan',  e_pan_deg, ...
                         'e_tilt', e_tilt_deg, ...
                         'de_pan', de_pan_filt, ...
                         'de_tilt',de_tilt_filt, ...
                         'mode',   current_mode);

    FSM_State.mode             = current_mode;
    FSM_State.e_pan_prev       = e_pan_deg;
    FSM_State.e_tilt_prev      = e_tilt_deg;
    FSM_State.de_pan_filtered  = de_pan_filt;
    FSM_State.de_tilt_filtered = de_tilt_filt;
    FSM_State.search_phase     = search_phase;
    FSM_State.hold_timer       = hold_timer;
    FSM_State.burst_timer      = burst_timer;
    FSM_State.was_night        = was_night;
    % NOTE: FSM_State.e_total_prev is written by CompareYield AFTER inner loop

    DebugInfo = struct('mode',         current_mode, ...
                       'e_pan_deg',    e_pan_deg, ...
                       'e_tilt_deg',   e_tilt_deg, ...
                       'de_pan_filt',  de_pan_filt, ...
                       'de_tilt_filt', de_tilt_filt, ...
                       'e_total',      e_total, ...
                       'is_locked',    (e_total < lock_threshold), ...
                       'is_flip',      is_flip, ...
                       'V_total',      V_total, ...
                       'is_dark',      is_dark, ...
                       'zenith_factor',zenith_factor, ...
                       'hold_timer',   hold_timer, ...
                       'burst_timer',  burst_timer);
end

%% HELPERS
function value = getFieldOrDefault(s, field, default)
    if isfield(s, field), value = s.(field); else, value = default; end
end

function s = ensureField(s, field, default)
    if ~isfield(s, field), s.(field) = default; end
end