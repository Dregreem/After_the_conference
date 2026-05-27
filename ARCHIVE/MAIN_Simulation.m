% MAIN_Simulation_OPTIMIZED.m
% VERSION: OPTIMIZED - All tracking improvements applied
% IMPROVEMENTS:
%   1. Adjustable test scenarios (REALISTIC, VEHICLE_FAST, EXTREME)
%   2. Command smoothing reduced (0.95 vs 0.15 - 13× faster response)
%   3. Unified servo configuration (no contradictions)
%   4. Servo throttling removed (always full speed available)
%   5. Simplified control flow (easier to understand)
%   6. Expected: 5-10× better tracking performance

clear; clc; close all;

%% ============================================================
%% TEST SCENARIO SELECTION
%% ============================================================

SCENARIO = 'FLIP_BOUNDARY';  % Options: REALISTIC, VEHICLE_SLOW, VEHICLE_FAST, EXTREME, ZENITH_STATIC, FLIP_BOUNDARY

switch SCENARIO
    case 'REALISTIC'
        spiral_speed = 0.01;    % Real sun motion (~0.25 deg/min) - REDUCED from 0.004
        spiral_widen = 0.002;   % Very slow descent
        duration_sec = 300;     % 5 minutes (short realistic scenario)
        fprintf('=== SCENARIO: REALISTIC SUN TRACKING ===\n');
    
    case 'ZENITH_STATIC'
        % ✅ NEW TEST: Gimbal lock protection at zenith
        spiral_speed = 0.0;     % No motion
        spiral_widen = 0.0;
        duration_sec = 60;      % 60 seconds
        % Initialize near zenith
        fprintf('=== SCENARIO: ZENITH STATIC TEST ===\n');
        fprintf('Testing gimbal lock protection at θ_tilt ≈ 2° (near zenith)\n');
        fprintf('Expected: Pan motor should not chatter or hunt\n');
        
    case 'FLIP_BOUNDARY'
        % ✅ NEW TEST: Flip transition smoothness
        spiral_speed = 0.1;     % Slow azimuth sweep
        spiral_widen = 0.0;     % No elevation change
        duration_sec = 180;     % 3 minutes (allows full azimuth path)
        fprintf('=== SCENARIO: FLIP BOUNDARY TEST ===\n');
        fprintf('Testing smooth transition at gimbal flip boundaries (Az ±90°)\n');
        fprintf('Expected: Continuous smooth motion, no large jumps\n');
        
    case 'VEHICLE_SLOW'
        spiral_speed = 0.05;    % 12× faster than sun (slow vehicle)
        spiral_widen = 0.01;
        duration_sec = 600;     % 10 minutes
        fprintf('=== SCENARIO: VEHICLE SLOW MOTION ===\n');
        
        
    case 'VEHICLE_FAST'
        spiral_speed = 0.2;     % 50× faster than sun (fast vehicle)
        spiral_widen = 0.05;
        duration_sec = 300;     % 5 minutes
        fprintf('=== SCENARIO: VEHICLE FAST MOTION ===\n');
        
    case 'EXTREME'
        spiral_speed = 5.0;     
        spiral_widen = 0.1;
        duration_sec = 1000;     
        fprintf('=== SCENARIO: EXTREME STRESS TEST ===\n');
        
    otherwise
        error('Unknown scenario: %s', SCENARIO);
end

fprintf('Sun angular speed: %.3f deg/s\n', spiral_speed);
fprintf('Descent rate: %.3f deg/s\n', spiral_widen);
fprintf('Duration: %.1f min\n\n', duration_sec/60);

%% ============================================================
%% CONFIGURATION
%% ============================================================

TEST_MODE = true;       % True: Spiral test, False: Real astronomy
AnimationDelay = 0.01;
DrawSkip = 5;

% Timing
dt_physics = 0.01;
dt_control = 0.01;
control_decimation = 1;

fprintf('Physics dt: %.3f s\n', dt_physics);
fprintf('Control dt: %.3f s\n\n', dt_control);

%% ============================================================
%% PHYSICAL CONSTANTS & ASSUMPTIONS
%% ============================================================

% Sun motion (test scenario)
SUN_PREDICTION_HORIZON = 5.0;  % seconds
SUN_ANGULAR_VEL_TEST = 0.6;    % deg/s (for EXTREME scenario)

% Servo specifications (MG996R)
SERVO_INTERNAL_Kv = 10.0;      % deg/s per degree error (approx)
SERVO_UPDATE_RATE = 1000;      % Hz (internal MCU)

% Voltage references
SUPPLY_VOLTAGE = 6.0;          % Volts (6V servo supply, for power calculation)

CONTROL_MODE = 'fsm';   % Using FSM controller

%% ============================================================
%% PI CONTROLLER PARAMETERS (OPTIMIZED - Velocity Form)
%% ============================================================
% NOTE: System implements PI velocity control (not PID).
% The servo's internal proportional feedback provides implicit damping.
%
% ⚠️  REMOVED: K_sens parameter was declared but never used in control law
%             (dead variable). Servo uses K_servo instead for feedback.
%             K_sens = 33.1 was referenced in old position-based controller
%             but getCurrently unused. Cleanup: removed to avoid confusion.

% Active PI gains (velocity control - used in fsmController)
PID_Params.Kp_vel = 0.25;    % Proportional gain (velocity per error)
PID_Params.Ki_vel = 0.04;    % Integral gain (eliminates steady-state bias)
PID_Params.max_tracking_velocity = 15.0;  % deg/s (INCREASED from 12.0)
PID_Params.max_integral = 10;

% Command smoothing (OPTIMIZED - was 0.15, now 0.95)
PID_Params.smooth_alpha = 0.95;  % Minimal lag (0.05s vs 0.67s)

% Other parameters
PID_Params.deadzone = 0.05;
PID_Params.max_output = 30;
PID_Params.velocity_damping = 0.10;
PID_Params.pan_limit = 180;
PID_Params.tilt_limit = 90;

% FSM parameters (TUNED for zenith and general tracking)
PID_Params.night_threshold = 0.3;
PID_Params.sun_lost_threshold = 0.5;
PID_Params.sun_found_threshold = 1.0;
PID_Params.lock_threshold = 0.5;  % INCREASED from 0.2 (less strict at zenith)
PID_Params.search_speed = 3.0;    % INCREASED from 2.0
PID_Params.zenith_pan_lock = true;   % ✅ VALIDATED (A/B Test 2/16/2026): ENABLE for stable zenith tracking
% Rationale: Test results show zenith protection ON provides smoother control at zenith singularity

fprintf('=== PI CONTROLLER CONFIGURATION ===\n');
fprintf('Kp (velocity) = %.4f deg/s per deg error\n', PID_Params.Kp_vel);
fprintf('Ki (velocity) = %.6f integral action\n', PID_Params.Ki_vel);
fprintf('(Note: Derivative term provided by servo internal feedback)\n');

% ✅ CORRECTED: Proper time constant calculation for exponential moving average
% tau = -dt / ln(1 - alpha)  [exponential moving average time constant]
lag_tau = -dt_control / log(1 - PID_Params.smooth_alpha + 1e-8);
fprintf('Command smoothing alpha: %.2f (time constant: %.4fs)\n', ...
    PID_Params.smooth_alpha, lag_tau);
fprintf('Max tracking velocity: %.1f deg/s\n\n', PID_Params.max_tracking_velocity);

%% ============================================================
%% SERVO CONFIGURATION (UNIFIED)
%% ============================================================

ServoProps.MaxSpeed = 40;    % deg/s
ServoProps.Accel    = 50;    % deg/s²
ServoProps.Jerk     = 200;   % deg/s³

fprintf('=== SERVO CONFIGURATION ===\n');
fprintf('Max Speed: %.1f deg/s\n', ServoProps.MaxSpeed);
fprintf('Accel:     %.1f deg/s²\n', ServoProps.Accel);
fprintf('Jerk:      %.1f deg/s³\n\n', ServoProps.Jerk);

%% ============================================================
%% FLIP LOGIC CONFIGURATION
%% ============================================================

USE_FLIP_LOGIC = true;
FLIP_OVERRIDE_FACTOR = 0.5;
FlipLimits.Pan = 90;
FlipLimits.Tilt = 90;

flip_state = struct('is_flipped', false, 'flip_count', 0, ...
                    'last_flip_time', -inf, 'consecutive_unreachable', 0);

FlipLog = struct('times', [], 'is_flipped', [], 'azimuth_sun', [], ...
                 'elevation_sun', [], 'is_reachable', [], ...
                 'target_pan_fsm', [], 'target_tilt_fsm', [], ...
                 'target_pan_final', [], 'target_tilt_final', []);

fprintf('=== FLIP LOGIC ENABLED ===\n');
fprintf('Coverage: 360° × 90° (full hemisphere)\n\n');

%% ============================================================
%% SYSTEM INITIALIZATION
%% ============================================================

% Location and time
lat = 41.0082; lon = 28.9784; tz = 3;
SimDate = datetime(2024, 6, 21, 5, 0, 0);
SunDistance = 1.0; R_dome = 4;

% Visual settings
SensorApexAngle = 120; SensorScale = 1;
PanServoDim = [0.040, 0.020, 0.040];
TiltServoDim = [0.040, 0.020, 0.040];

fprintf('=== SYSTEM INITIALIZATION ===\n');
addpath(genpath(pwd));
handles = initSolarWorld(R_dome);
ax = gca; set(ax, 'OuterPosition', [0, 0, 0.75, 1]);
SensorParams.ApexAngle = SensorApexAngle;
SensorParams.Scale = SensorScale;
Mech = initSystemMechanics(ax, PanServoDim, TiltServoDim, SensorParams);

% Initial servo configuration - System starts at ZENITH
StatePan  = struct('Angle', 0, 'Velocity', 0, 'Current', 0);  % Pan: start at 0° (azimuth reference)
StateTilt = struct('Angle', 0, 'Velocity', 0, 'Current', 0);  % Tilt: START AT ZENITH (Motor_Tilt=0 → Elevation=90°)

% ✅ SCENARIO-SPECIFIC INITIALIZATION
if strcmp(SCENARIO, 'ZENITH_STATIC')
    % Position servo very close to zenith for gimbal lock testing
    StatePan.Angle = 45.0;   % Arbitrary azimuth (45°)
    StateTilt.Angle = 2.0;   % Near zenith: 2° from zenith
    fprintf('Initialized at Pan=45°, Tilt=2° (near zenith) for lock testing\n');
elseif strcmp(SCENARIO, 'FLIP_BOUNDARY')
    % Start away from flip boundary
    StatePan.Angle = 10.0;
    StateTilt.Angle = 45.0;
    fprintf('Initialized at Pan=10°, Tilt=45° for flip transition testing\n');
end

FSM_State = struct('mode', 'TRACKING', 'I_pan', 0, 'I_tilt', 0, ...
    'e_pan_prev', 0, 'e_tilt_prev', 0);

% Command smoothing state
CommandSmoothing = struct('target_pan_smoothed', 0, ...
                          'target_tilt_smoothed', 0);

InfoBox = annotation('textbox', [0.76, 0.2, 0.23, 0.7], ...
                     'String', 'Initializing...', ...
                     'EdgeColor', 'k', 'BackgroundColor', [0.95 0.95 0.95], ...
                     'FaceAlpha', 0.8, 'FontSize', 10, 'FontName', 'Consolas');

%% ============================================================
%% SIMULATION LOOP
%% ============================================================

time_vector = 0 : dt_physics : duration_sec;
num_steps = length(time_vector);

% Preallocate logs
Log.Time = time_vector;
Log.TargetPan = zeros(num_steps, 1); Log.ActualPan = zeros(num_steps, 1);
Log.TargetTilt = zeros(num_steps, 1); Log.ActualTilt = zeros(num_steps, 1);
Log.ServoVelPan = zeros(num_steps, 1); Log.ServoVelTilt = zeros(num_steps, 1);  % SERVO MOTOR VELOCITIES
Log.I_Pan = zeros(num_steps, 1); Log.I_Tilt = zeros(num_steps, 1); Log.IsFlip = zeros(num_steps, 1);
Log.LDR_Voltage = zeros(num_steps, 4); Log.FSM_Mode = cell(num_steps, 1);
Log.V_Total = zeros(num_steps, 1);
Log.E_norm_Pan = zeros(num_steps, 1); Log.E_norm_Tilt = zeros(num_steps, 1);
Log.E_deg_Pan = zeros(num_steps, 1); Log.E_deg_Tilt = zeros(num_steps, 1);
Log.Incidence = zeros(num_steps, 1); Log.IsLocked = zeros(num_steps, 1);
Log.PID_P_Pan = zeros(num_steps, 1); Log.PID_I_Pan = zeros(num_steps, 1); Log.PID_D_Pan = zeros(num_steps, 1);
Log.PID_P_Tilt = zeros(num_steps, 1); Log.PID_I_Tilt = zeros(num_steps, 1); Log.PID_D_Tilt = zeros(num_steps, 1);

% NEW METRICS (Option 3)
Log.Power_Pan = zeros(num_steps, 1);
Log.Power_Tilt = zeros(num_steps, 1);
Log.Power_Total = zeros(num_steps, 1);
Log.LockCounter = zeros(num_steps, 1);
Log.LDR_DynamicRange = zeros(num_steps, 1);
Log.SunPred_Az = zeros(num_steps, 1);
Log.SunPred_El = zeros(num_steps, 1);

fprintf('\n=== SIMULATION START ===\n');

for i = 1:num_steps
    % Safety check
    if ~isvalid(handles.h_Sun) || ~isvalid(Mech.h_Pan)
        fprintf('Simulation stopped (Window closed).\n');
        break;
    end
    
    current_time = SimDate + seconds(time_vector(i));
    sim_time_elapsed = time_vector(i);
    
    %% SUN POSITION (SPIRAL GENERATOR)
    if TEST_MODE
        % TEST MODE: Use controlled spiral trajectory
        angle_phi = spiral_speed * sim_time_elapsed;
        angle_alpha = 90 - (spiral_widen * sim_time_elapsed);
        
        if angle_alpha < 0, angle_alpha = 0; end
        
        az = deg2rad(angle_phi);
        el = deg2rad(angle_alpha);
        
        S_vec = [cos(el)*cos(az); cos(el)*sin(az); sin(el)];
        alpha = angle_alpha;
        phi = angle_phi;
    else
        % REAL MODE: Use astronomical sun calculation
        [S_vec, alpha, phi] = getSunVector(lat, lon, current_time, tz);
    end
    
    %% CONTROL UPDATE
    if mod(i-1, control_decimation) == 0
        theta_pan_curr = StatePan.Angle;
        theta_tilt_curr = StateTilt.Angle;
        
        % Co-rotation: Pan around Z-axis (counter-clockwise), then Tilt around rotated Y-axis
        cp = cosd(theta_pan_curr); sp = sind(theta_pan_curr);
        ct = cosd(theta_tilt_curr); st = sind(theta_tilt_curr);
        
        % Pan rotation around Z-axis (standard counter-clockwise)
        Sx_rz = cp*S_vec(1) - sp*S_vec(2);  % [cos -sin; sin cos] matrix
        Sy_rz = sp*S_vec(1) + cp*S_vec(2);  % applied to [Sx, Sy]
        Sz_rz = S_vec(3);
        
        % Tilt rotation around Y-axis (in Pan-rotated frame)
        % Increases Tilt = tilts toward horizon (Sz decreases)
        S_body_pre = [ct*Sx_rz - st*Sz_rz; Sy_rz; st*Sx_rz + ct*Sz_rz];
        
        % NORMALIZE S_body (CRITICAL FIX)
        S_body_norm = S_body_pre / (norm(S_body_pre) + 1e-8);
        
        % Read LDRs
        [~, LDR_V_ctrl, ~, ~] = readLDRs(S_body_norm, SensorApexAngle);
        
        % Flip logic
        [azimuth_sun, elevation_sun] = cartesian2spherical(S_vec);
        ideal_pan_from_azimuth = azimuth_sun;
        % Tilt command convention in this model: 0 deg = zenith, +90 deg = horizon
        ideal_tilt_from_elevation = max(-90, min(90, 90 - elevation_sun));
        
        if ideal_pan_from_azimuth > 180
            ideal_pan_from_azimuth = ideal_pan_from_azimuth - 360;
        end
        
        if USE_FLIP_LOGIC
            [adjusted_pan_from_sun, adjusted_tilt_from_sun, is_flip, is_reachable] = ...
                applyFlipLogic(ideal_pan_from_azimuth, ideal_tilt_from_elevation, FlipLimits);
        else
            adjusted_pan_from_sun = ideal_pan_from_azimuth;
            adjusted_tilt_from_sun = ideal_tilt_from_elevation;
            is_flip = false;
            is_reachable = true;
        end
        
        % FSM Controller
        [target_pan_fsm, target_tilt_fsm, FSM_State, DebugFSM] = fsmController(...
            LDR_V_ctrl, S_body_pre, theta_pan_curr, theta_tilt_curr, ...
            FSM_State, PID_Params, dt_control, is_flip);
        
        % Blend FSM + flip logic
        if is_reachable && USE_FLIP_LOGIC && FLIP_OVERRIDE_FACTOR > 0
            target_pan = target_pan_fsm + FLIP_OVERRIDE_FACTOR * (adjusted_pan_from_sun - target_pan_fsm);
            target_tilt = target_tilt_fsm + FLIP_OVERRIDE_FACTOR * (adjusted_tilt_from_sun - target_tilt_fsm);
        else
            target_pan = target_pan_fsm;
            target_tilt = target_tilt_fsm;
        end
        
        % ✅ COMMAND SMOOTHING (MOVED INTO SAME CONTROL BLOCK - consolidated)
        alpha = PID_Params.smooth_alpha;
        
        CommandSmoothing.target_pan_smoothed = ...
            (1 - alpha) * CommandSmoothing.target_pan_smoothed + alpha * target_pan;
        
        CommandSmoothing.target_tilt_smoothed = ...
            (1 - alpha) * CommandSmoothing.target_tilt_smoothed + alpha * target_tilt;
    
    % Log flip data
        if USE_FLIP_LOGIC
            FlipLog.times = [FlipLog.times, sim_time_elapsed];
            FlipLog.is_flipped = [FlipLog.is_flipped, is_flip];
            FlipLog.azimuth_sun = [FlipLog.azimuth_sun, azimuth_sun];
            FlipLog.elevation_sun = [FlipLog.elevation_sun, elevation_sun];
            FlipLog.is_reachable = [FlipLog.is_reachable, is_reachable];
            FlipLog.target_pan_final = [FlipLog.target_pan_final, target_pan];
            FlipLog.target_tilt_final = [FlipLog.target_tilt_final, target_tilt];
            
            if is_flip && ~flip_state.is_flipped
                flip_state.is_flipped = true;
                flip_state.flip_count = flip_state.flip_count + 1;
                flip_state.last_flip_time = sim_time_elapsed;
            elseif ~is_flip && flip_state.is_flipped
                flip_state.is_flipped = false;
            end
        end
    end
    
    target_pan_smooth = CommandSmoothing.target_pan_smoothed;
    target_tilt_smooth = CommandSmoothing.target_tilt_smoothed;
    
    %% SERVO PHYSICS (OPTIMIZED - Always full speed)
    ServoProps_Active = ServoProps;  % No throttling!
    
    [StatePan, ~] = stepAdvancedServoPhysics(StatePan, target_pan_smooth, ...
                                                        ServoProps_Active, dt_physics, 'Pan');
    [StateTilt, ~] = stepAdvancedServoPhysics(StateTilt, target_tilt_smooth, ...
                                                         ServoProps_Active, dt_physics, 'Tilt');
    
    theta_pan = StatePan.Angle;
    theta_tilt = StateTilt.Angle;
    
    %% VISUALIZATION
    if mod(i, DrawSkip) == 0
        P_sun = S_vec * SunDistance;
        addpoints(handles.h_PathSun, P_sun(1), P_sun(2), P_sun(3));
        updateSolarWorld(handles, S_vec, SunDistance, current_time, alpha, phi);
        
        M_pan = makehgtform('zrotate', deg2rad(theta_pan));
        try
            set(Mech.h_Pan, 'Matrix', M_pan);
            M_tilt_trans = makehgtform('translate', Mech.PivotOffset);
            M_tilt_rot   = makehgtform('yrotate', deg2rad(theta_tilt));
            set(Mech.h_Tilt, 'Matrix', M_tilt_trans * M_tilt_rot);
            
            R_Total = M_pan(1:3,1:3) * M_tilt_rot(1:3,1:3);
            P_Tracker = (R_Total * [0;0;1]) * SunDistance;
            addpoints(handles.h_PathTracker, P_Tracker(1), P_Tracker(2), P_Tracker(3));
            
            flip_indicator = ternary(is_flip, '🔄 FLIP', '→ NORMAL');
            
            % CALCULATE METRICS FOR DISPLAY (before logging)
            [E_pan_disp, E_tilt_disp, E_deg_pan_disp, E_deg_tilt_disp, ldr_locked_disp] = controlLDR(...
                LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4), S_body_norm);
            [theta_inc_disp, ~] = checkAlignment(S_body_norm);
            
            servo_vel_pan_disp = abs(StatePan.Velocity);
            servo_vel_tilt_disp = abs(StateTilt.Velocity);
            
            % Enhanced display with all critical information
            InfoStr = {
                sprintf('═══════ SCENARIO: %s ═══════', SCENARIO), ...
                '', ...
                sprintf('TIME: %.1f / %.0f s', sim_time_elapsed, duration_sec), ...
                '', ...
                sprintf('☀️  GÜNEŞ POZİSYONU'), ...
                sprintf('    Az: %.1f°  |  El: %.1f°', azimuth_sun, elevation_sun), ...
                '', ...
                sprintf('📡 LDR VOLTAJLARI (GL5528)'), ...
                sprintf('    Right:%.2fV  Left:%.2fV  Up:%.2fV  Down:%.2fV', ...
                        LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4)), ...
                sprintf('    Total: %.2f V', sum(LDR_V_ctrl)), ...
                '', ...
                sprintf('🎯 MOTOR AÇILARI (GERÇEK)'), ...
                sprintf('    Pan:  %.1f°  |  Tilt: %.1f°', theta_pan, theta_tilt), ...
                '', ...
                sprintf('❌ HATALAR'), ...
                sprintf('    Pan:  %+.2f°  |  Tilt: %+.2f°', E_deg_pan_disp, E_deg_tilt_disp), ...
                sprintf('    Inc:  %.3f°  (Target: <0.5°)', theta_inc_disp), ...
                '', ...
                sprintf('⚡ MOTORİUS HİCRETİ'), ...
                sprintf('    I_Pan: %.3f A  |  I_Tilt: %.3f A', StatePan.Current, StateTilt.Current), ...
                sprintf('    V_Pan: %.1f °/s | V_Tilt: %.1f °/s', servo_vel_pan_disp, servo_vel_tilt_disp), ...
                '', ...
                sprintf('🔄 FLIP: %s (Total: %d)', flip_indicator, flip_state.flip_count)
            };
            set(InfoBox, 'String', InfoStr);
            drawnow limitrate;
        catch
            fprintf('Graphics error. Continuing...\n');
            break;
        end
    end
    
    %% LOGGING
    Log.TargetPan(i) = target_pan; Log.ActualPan(i) = theta_pan;
    Log.TargetTilt(i) = target_tilt; Log.ActualTilt(i) = theta_tilt;
    % SERVO MOTOR VELOCITIES (from servo physics, not position delta)
    Log.ServoVelPan(i) = abs(StatePan.Velocity);
    Log.ServoVelTilt(i) = abs(StateTilt.Velocity);
    Log.I_Pan(i) = StatePan.Current;
    Log.I_Tilt(i) = StateTilt.Current;
    Log.IsFlip(i) = is_flip;
    Log.FSM_Mode{i} = DebugFSM.mode;
    Log.V_Total(i) = sum(LDR_V_ctrl);
    Log.LDR_Voltage(i,:) = LDR_V_ctrl;
    
    [E_pan, E_tilt, E_deg_pan, E_deg_tilt, ldr_locked] = controlLDR(...
        LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4), S_body_norm);
    Log.E_deg_Pan(i) = E_deg_pan;
    Log.E_deg_Tilt(i) = E_deg_tilt;
    Log.E_norm_Pan(i) = E_pan;
    Log.E_norm_Tilt(i) = E_tilt;
    Log.IsLocked(i) = ldr_locked;
    [theta_inc, ~] = checkAlignment(S_body_norm);
    Log.Incidence(i) = theta_inc;
    
    % PI Control Terms Logging (Note: D term is implicitly in servo feedback)
    Log.PID_P_Pan(i) = PID_Params.Kp_vel * E_deg_pan;   % Proportional (velocity) term
    Log.PID_P_Tilt(i) = PID_Params.Kp_vel * E_deg_tilt; % Proportional (velocity) term
    Log.PID_I_Pan(i) = FSM_State.I_pan;
    Log.PID_I_Tilt(i) = FSM_State.I_tilt;
    Log.PID_D_Pan(i) = 0;   % Explicit D term not used in outer loop
    Log.PID_D_Tilt(i) = 0;  % Explicit D term not used in outer loop
    
    % ✅ SERVO IMPLICIT D TERM LOGGING
    % Servo internal velocity = Kv * (target - actual) ≈ derivative action
    % Log both the actual velocity (implicit D behavior) and equivalent D gain contribution
    Log.Servo_Velocity_Pan(i) = StatePan.Velocity;     % This IS the implicit D!
    Log.Servo_Velocity_Tilt(i) = StateTilt.Velocity;   % This IS the implicit D!
    
    % Equivalent D gain contribution (servo: v = Kv*(θ_target - θ_actual))
    servo_error_pan = target_pan_smooth - theta_pan;
    servo_error_tilt = target_tilt_smooth - theta_tilt;
    Log.Servo_EquivD_Pan(i) = SERVO_INTERNAL_Kv * servo_error_pan;
    Log.Servo_EquivD_Tilt(i) = SERVO_INTERNAL_Kv * servo_error_tilt;
    
    % NEW METRICS LOGGING (Option 3)
    Log.Power_Pan(i) = StatePan.Current * SUPPLY_VOLTAGE;
    Log.Power_Tilt(i) = StateTilt.Current * SUPPLY_VOLTAGE;
    Log.Power_Total(i) = Log.Power_Pan(i) + Log.Power_Tilt(i);
    
    % Lock counter (for calculating lock percentage later)
    if theta_inc < PID_Params.lock_threshold
        Log.LockCounter(i) = 1;
    else
        Log.LockCounter(i) = 0;
    end
    
    % LDR dynamic range (instantaneous)
    Log.LDR_DynamicRange(i) = max(LDR_V_ctrl) - min(LDR_V_ctrl);
    
    % Predicted sun position in next 5s (using SUN_PREDICTION_HORIZON and SUN_ANGULAR_VEL_TEST)
    future_t = sim_time_elapsed + SUN_PREDICTION_HORIZON;
    future_az = mod(azimuth_sun + (future_t - sim_time_elapsed) * SUN_ANGULAR_VEL_TEST, 360);
    future_el = elevation_sun - 0.01 * SUN_PREDICTION_HORIZON;  % Elevation decreases ~0.01°/s
    Log.SunPred_Az(i) = future_az;
    Log.SunPred_El(i) = future_el;
end

fprintf('Simulation Complete.\n');

%% PERFORMANCE SUMMARY

fprintf('\n========================================\n');
fprintf('   PERFORMANCE SUMMARY\n');
fprintf('========================================\n');

tracking_error_mean = mean(Log.Incidence);
tracking_error_max = max(Log.Incidence);

if length(Log.Incidence) > 100
    tracking_error_final = mean(Log.Incidence(end-100:end));
else
    tracking_error_final = mean(Log.Incidence);
end

lock_time = sum(Log.IsLocked) * dt_physics;
lock_percentage = (lock_time / duration_sec) * 100;

fprintf('\n--- TRACKING ACCURACY ---\n');
fprintf('Mean tracking error:  %.3f deg\n', tracking_error_mean);
fprintf('Max tracking error:   %.3f deg\n', tracking_error_max);
fprintf('Final error (last 100 steps): %.3f deg\n', tracking_error_final);

if tracking_error_final < 5.0
    fprintf('✅ TARGET ACHIEVED: < 5 deg (5%% of 90° range)\n');
else
    fprintf('⚠️  Target not met. Expected < 5 deg\n');
end

fprintf('\n--- SERVO PERFORMANCE ---\n');
% Use logged servo velocities directly (more accurate than position delta)
max_vel_pan = max(Log.ServoVelPan);
max_vel_tilt = max(Log.ServoVelTilt);
fprintf('Max Pan velocity:     %.1f deg/s\n', max_vel_pan);
fprintf('Max Tilt velocity:    %.1f deg/s\n', max_vel_tilt);
fprintf('Servo speed limit:    %.1f deg/s\n', ServoProps.MaxSpeed);

if max_vel_pan < ServoProps.MaxSpeed * 1.1
    fprintf('✅ Servo velocities within limits\n');
else
    fprintf('⚠️  Servo exceeded speed limit!\n');
end

fprintf('\n--- LOCK PERFORMANCE ---\n');
fprintf('Time locked on sun:   %.1f s (%.1f%%)\n', lock_time, lock_percentage);
fprintf('Lock threshold:       %.1f deg\n', PID_Params.lock_threshold);

fprintf('\n--- ENERGY CONSUMPTION ---\n');
if ~isempty(Log.I_Pan)
    % Calculate detailed energy metrics
    power_instant = Log.I_Pan(:) .* 6.0;  % Wh (assuming 6V)
    total_energy = sum(power_instant) * dt_physics / 3600;  % Convert to Wh
    avg_power = total_energy * 3600 / duration_sec;  % W
    max_power = max(power_instant);
    
    % Energy per axis
    % Approximate: split proportional to velocity
    vel_total = Log.ServoVelPan + Log.ServoVelTilt;
    vel_total(vel_total < 0.001) = 1;  % Avoid division by zero
    pan_fraction = sum(Log.ServoVelPan ./ vel_total) / length(vel_total);
    tilt_fraction = 1 - pan_fraction;
    
    energy_pan = total_energy * pan_fraction;
    energy_tilt = total_energy * tilt_fraction;
    
    fprintf('Total Energy Consumed:   %.3f Wh\n', total_energy);
    fprintf('Average Power:           %.2f W\n', avg_power);
    fprintf('Peak Power:              %.2f W\n', max_power);
    fprintf('  - Pan axis:            %.3f Wh (%.1f%%)\n', energy_pan, pan_fraction*100);
    fprintf('  - Tilt axis:           %.3f Wh (%.1f%%)\n', energy_tilt, tilt_fraction*100);
else
    fprintf('Current data not available\n');
end

fprintf('\n--- FLIP LOGIC ANALYSIS ---\n');
if USE_FLIP_LOGIC && flip_state.flip_count > 0
    fprintf('Total flip events:       %d\n', flip_state.flip_count);
    if length(FlipLog.times) > 1
        fprintf('First flip at:           %.3f sec\n', min(FlipLog.times));
        fprintf('Last flip at:            %.3f sec\n', max(FlipLog.times));
    end
elseif USE_FLIP_LOGIC
    fprintf('Total flip events:       0\n');
else
    fprintf('Flip logic disabled\n');
end

fprintf('\n--- SERVO HEALTH ---\n');
fprintf('Avg Pan velocity:        %.2f deg/s\n', mean(Log.ServoVelPan(Log.ServoVelPan>0)));
fprintf('Avg Tilt velocity:       %.2f deg/s\n', mean(Log.ServoVelTilt(Log.ServoVelTilt>0)));
fprintf('Pan acceleration usage:  %.1f%% of capability\n', (max_vel_pan / ServoProps.MaxSpeed) * 100);
fprintf('Tilt acceleration usage: %.1f%% of capability\n', (max_vel_tilt / ServoProps.MaxSpeed) * 100);

fprintf('\n--- LDR SENSOR HEALTH ---\n');
ldr_min_voltage = min(Log.V_Total);
ldr_max_voltage = max(Log.V_Total);
ldr_avg_voltage = mean(Log.V_Total);
fprintf('Min total voltage:       %.2f V\n', ldr_min_voltage);
fprintf('Max total voltage:       %.2f V\n', ldr_max_voltage);
fprintf('Avg total voltage:       %.2f V\n', ldr_avg_voltage);
fprintf('Dynamic range:           %.2f V (%.1f%%)\n', ldr_max_voltage - ldr_min_voltage, ((ldr_max_voltage - ldr_min_voltage) / ldr_max_voltage) * 100);

fprintf('\n--- NEW METRICS (Option 3: Complete Monitoring) ---\n');

% 1. POWER CONSUMPTION DETAILED
total_energy_wh = sum(Log.Power_Total) * dt_physics / 3600;
avg_power_w = mean(Log.Power_Total(Log.Power_Total > 0.001));
peak_power_w = max(Log.Power_Total);
pan_power_wh = sum(Log.Power_Pan) * dt_physics / 3600;
tilt_power_wh = sum(Log.Power_Tilt) * dt_physics / 3600;
total_pw = pan_power_wh + tilt_power_wh;

fprintf('💡 POWER CONSUMPTION:\n');
fprintf('   Total: %.4f Wh | Avg: %.3f W | Peak: %.3f W\n', total_energy_wh, avg_power_w, peak_power_w);
if total_pw > 0.001
    fprintf('   Pan: %.4f Wh (%.0f%%)  | Tilt: %.4f Wh (%.0f%%)\n', pan_power_wh, pan_power_wh/total_pw*100, tilt_power_wh, tilt_power_wh/total_pw*100);
end

% 2. LOCK TIME PERCENTAGE (Real Lock Counter)
lock_percentage_actual = mean(Log.LockCounter) * 100;
lock_time_actual = sum(Log.LockCounter) * dt_physics;
if sum(Log.LockCounter) > 0
    avg_locked_inc = mean(Log.Incidence(Log.LockCounter > 0.5));
else
    avg_locked_inc = 0;
end
fprintf('🎯 LOCK: %.1f sec (%.1f%%)  | Avg Incidence @ lock: %.3f°\n', lock_time_actual, lock_percentage_actual, avg_locked_inc);

% 3. LDR DYNAMIC RANGE (Signal Quality)
ldr_range_avg = mean(Log.LDR_DynamicRange);
ldr_range_max = max(Log.LDR_DynamicRange);
signal_quality = ternary(ldr_range_avg > 2, '✅ Excellent', '⚠️  Fair');
fprintf('📡 LDR QUALITY: Avg Range %.2f V | Max %.2f V | %s\n', ldr_range_avg, ldr_range_max, signal_quality);

% 4. SUN PREDICTION (Next 5 seconds)
last_idx = min(length(Log.SunPred_Az), num_steps);
if last_idx > 0 && last_idx <= num_steps
    pred_az = Log.SunPred_Az(last_idx);
    pred_el = Log.SunPred_El(last_idx);
    fprintf('☀️  PREDICTION (next 5s): Az %.1f° | El %.1f° | Need Move: %.1f° Az, %.1f° El\n', ...
            pred_az, pred_el, abs(pred_az - azimuth_sun), abs(pred_el - elevation_sun));
end

fprintf('\n========================================\n\n');

%% ============================================================
%% ANALYSIS PLOTS
%% ============================================================

fprintf('=== GENERATING PLOTS ===\n');

figure('Name', 'System Performance', 'Position', [100 50 1200 900]);

subplot(4,1,1); hold on;
plot(Log.Time/3600, Log.TargetPan, 'b--', 'LineWidth', 1.2, 'DisplayName', 'Target');
plot(Log.Time/3600, Log.ActualPan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Actual');
area(Log.Time/3600, Log.IsFlip * 360, -360, 'FaceColor', 'y', ...
     'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', 'Flip');
title('Pan Axis Tracking', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylim([-200 200]);
ylabel('Angle (deg)');
grid on;

subplot(4,1,2); hold on;
plot(Log.Time/3600, Log.TargetTilt, 'b--', 'LineWidth', 1.2, 'DisplayName', 'Target');
plot(Log.Time/3600, Log.ActualTilt, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Actual');
title('Tilt Axis Tracking', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylabel('Angle (deg)');
grid on;

subplot(4,1,3); hold on;
plot(Log.Time/3600, Log.TargetPan - Log.ActualPan, 'm', 'LineWidth', 1.5, 'DisplayName', 'Pan Error');
plot(Log.Time/3600, Log.TargetTilt - Log.ActualTilt, 'c', 'LineWidth', 1.5, 'DisplayName', 'Tilt Error');
yline(0, 'k--', 'LineWidth', 0.5);
title('Tracking Error', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylabel('Error (deg)');
grid on;

subplot(4,1,4);
plot(Log.Time/3600, Log.Incidence, 'k-', 'LineWidth', 1.5);
yline(1.0, 'r--', 'Target (1.0°)', 'LineWidth', 1.5);
yline(0.5, 'g--', 'Excellent (0.5°)', 'LineWidth', 1.5);
title('Incidence Angle', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (hours)');
ylabel('θ_{inc} (deg)');
grid on;

%% ============================================================
%% FIGURE 2: LDR SENSOR ANALYSIS
%% ============================================================
figure('Name', 'LDR Sensor Analysis', 'Position', [150 30 1200 900]);

subplot(4,1,1); hold on;
plot(Log.Time/3600, Log.LDR_Voltage(:,1), 'r-', 'LineWidth', 1.2, 'DisplayName', 'Right');
plot(Log.Time/3600, Log.LDR_Voltage(:,2), 'b-', 'LineWidth', 1.2, 'DisplayName', 'Left');
plot(Log.Time/3600, Log.LDR_Voltage(:,3), 'g-', 'LineWidth', 1.2, 'DisplayName', 'Up');
plot(Log.Time/3600, Log.LDR_Voltage(:,4), 'm-', 'LineWidth', 1.2, 'DisplayName', 'Down');
title('LDR Voltage Outputs (GL5528 Sensors)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylabel('Voltage (V)');
ylim([0 5.5]);
grid on;

subplot(4,1,2); hold on;
plot(Log.Time/3600, Log.E_norm_Pan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'E_{norm,Pan}');
plot(Log.Time/3600, Log.E_norm_Tilt, 'b-', 'LineWidth', 1.5, 'DisplayName', 'E_{norm,Tilt}');
yline(0, 'k--', 'LineWidth', 0.5);
yline(0.05, 'g:', 'Deadzone', 'LineWidth', 1);
yline(-0.05, 'g:', 'LineWidth', 1);
title('Normalized Error Index: E = (V_L - V_R) / (V_L + V_R)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylabel('E_{norm} [-1, +1]');
ylim([-1.1 1.1]);
grid on;

subplot(4,1,3); hold on;
plot(Log.Time/3600, Log.E_deg_Pan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Pan Error');
plot(Log.Time/3600, Log.E_deg_Tilt, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Tilt Error');
yline(0, 'k--', 'LineWidth', 0.5);
yline(0.5, 'g:', 'Deadzone (0.5°)', 'LineWidth', 1);
yline(-0.5, 'g:', 'LineWidth', 1);
title('Angular Error from LDR', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylabel('Angle (deg)');
grid on;

subplot(4,1,4); hold on;
yyaxis left;
plot(Log.Time/3600, Log.Incidence, 'k-', 'LineWidth', 1.5);
yline(0.5, 'g--', 'Lock Threshold (0.5°)', 'LineWidth', 1.5);
yline(1.0, 'r--', 'Target (1.0°)', 'LineWidth', 1.5);
ylabel('\theta_{inc} (deg)');
ylim([0 max(90, max(Log.Incidence)*1.1)]);

yyaxis right;
area(Log.Time/3600, Log.IsLocked, 'FaceColor', 'g', 'FaceAlpha', 0.3, 'EdgeColor', 'none');
ylabel('Lock Status');
yticks([0 1]);
yticklabels({'Searching', 'LOCKED'});
ylim([-0.1 1.5]);

title('Tracking Accuracy: Incidence Angle with Lock Status', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (hours)');
grid on;

%% ============================================================
%% FIGURE 3: PID CONTROL ANALYSIS
%% ============================================================
if ~strcmp(CONTROL_MODE, 'open_loop')
    figure('Name', 'PID Control Analysis', 'Position', [200 10 1200 900]);
    
    subplot(3,2,1); hold on;
    plot(Log.Time/3600, Log.PID_P_Pan, 'r-', 'LineWidth', 1.5);
    title('P Term (Pan)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('P');
    grid on;
    
    subplot(3,2,2); hold on;
    plot(Log.Time/3600, Log.PID_P_Tilt, 'b-', 'LineWidth', 1.5);
    title('P Term (Tilt)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('P');
    grid on;
    
    subplot(3,2,3); hold on;
    plot(Log.Time/3600, Log.PID_I_Pan, 'r-', 'LineWidth', 1.5);
    yline(PID_Params.max_integral, 'k--', 'Max Integral');
    yline(-PID_Params.max_integral, 'k--');
    title('I Term (Pan) - Check for Windup', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('I');
    grid on;
    
    subplot(3,2,4); hold on;
    plot(Log.Time/3600, Log.PID_I_Tilt, 'b-', 'LineWidth', 1.5);
    yline(PID_Params.max_integral, 'k--', 'Max Integral');
    yline(-PID_Params.max_integral, 'k--');
    title('I Term (Tilt) - Check for Windup', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('I');
    grid on;
    
    subplot(3,2,5); hold on;
    plot(Log.Time/3600, Log.PID_D_Pan, 'r-', 'LineWidth', 1.5);
    title('D Term (Pan)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('D');
    xlabel('Time (hours)');
    grid on;
    
    subplot(3,2,6); hold on;
    plot(Log.Time/3600, Log.PID_D_Tilt, 'b-', 'LineWidth', 1.5);
    title('D Term (Tilt)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('D');
    xlabel('Time (hours)');
    grid on;
    
    sgtitle('PID Control Terms Analysis', 'FontSize', 14, 'FontWeight', 'bold');
end

%% ============================================================
%% FIGURE 4: FSM STATE ANALYSIS
%% ============================================================
if strcmp(CONTROL_MODE, 'fsm')
    figure('Name', 'FSM State Machine Analysis', 'Position', [250 0 1200 600]);
    
    subplot(2,1,1); hold on;
    % Convert FSM modes to numeric for plotting
    mode_numeric = zeros(num_steps, 1);
    for i = 1:num_steps
        if isempty(Log.FSM_Mode{i})
            mode_numeric(i) = 0;
            continue;
        end
        switch Log.FSM_Mode{i}
            case 'IDLE'
                mode_numeric(i) = 0;
            case 'TRACKING'
                mode_numeric(i) = 1;
            case 'SEARCH'
                mode_numeric(i) = 2;
            case 'SAFETY'
                mode_numeric(i) = 3;
            otherwise
                mode_numeric(i) = -1;
        end
    end
    
    area(Log.Time/3600, mode_numeric, 'FaceAlpha', 0.5);
    yticks([0 1 2 3]);
    yticklabels({'IDLE', 'TRACKING', 'SEARCH', 'SAFETY'});
    ylim([-0.5 3.5]);
    title('FSM State Over Time', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Mode');
    grid on;
    
    subplot(2,1,2); hold on;
    plot(Log.Time/3600, Log.V_Total, 'k-', 'LineWidth', 1.5);
    yline(PID_Params.night_threshold, 'b--', sprintf('Night (%.1fV)', PID_Params.night_threshold));
    yline(PID_Params.sun_lost_threshold, 'r--', sprintf('Lost (%.1fV)', PID_Params.sun_lost_threshold));
    yline(PID_Params.sun_found_threshold, 'g--', sprintf('Found (%.1fV)', PID_Params.sun_found_threshold));
    title('Total LDR Voltage (FSM Decision Variable)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('V_{total} (V)');
    xlabel('Time (hours)');
    grid on;
end

%% ============================================================
%% FIGURE 5: ENERGY ANALYSIS
%% ============================================================
figure('Name', 'Energy Analysis', 'Position', [300 50 1200 900]);

% Calculate power and cumulative energy
power_instant = Log.I_Pan(:) .* 6.0;  % Power in W (assuming 6V, I in A)
energy_cumulative = cumsum(power_instant) * dt_physics / 3600;  % Wh

subplot(3,1,1); hold on;
area(Log.Time/3600, power_instant, 'FaceColor', 'b', 'FaceAlpha', 0.3, 'EdgeColor', 'k', 'LineWidth', 1.5);
avg_pwr = mean(power_instant);
yline(avg_pwr, 'r--', sprintf('Average: %.2f W', avg_pwr), 'LineWidth', 2);
title('Instantaneous Power Consumption', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Power (W)');
grid on;

subplot(3,1,2); hold on;
area(Log.Time/3600, energy_cumulative, 'FaceColor', 'b', 'FaceAlpha', 0.3, 'EdgeColor', 'k', 'LineWidth', 1.5);
title('Cumulative Energy Consumption', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Energy (Wh)');
grid on;
annot_text = sprintf('Total: %.4f Wh\nAvg: %.2f W', energy_cumulative(end), mean(power_instant));
text(0.6, 0.3, annot_text, 'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w', 'EdgeColor', 'k');

subplot(3,1,3); hold on;
vel_total = Log.ServoVelPan + Log.ServoVelTilt;
vel_total(vel_total < 0.001) = 1;
pan_fraction = Log.ServoVelPan ./ vel_total;
tilt_fraction = Log.ServoVelTilt ./ vel_total;

power_pan = power_instant .* pan_fraction;
power_tilt = power_instant .* tilt_fraction;

area(Log.Time/3600, power_pan, 'FaceColor', 'r', 'FaceAlpha', 0.6, 'DisplayName', 'Pan');
area(Log.Time/3600, power_tilt, 'FaceColor', 'b', 'FaceAlpha', 0.6, 'DisplayName', 'Tilt');
title('Power Distribution: Pan vs Tilt', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
xlabel('Time (hours)');
ylabel('Power (W)');
grid on;

%% ============================================================
%% FIGURE 6: CLOSED-LOOP MOTOR CONTROL
%% ============================================================
figure('Name', 'Closed-Loop Motor Control', 'Position', [350 100 1200 900]);

subplot(3,1,1); hold on;
yyaxis left;
plot(Log.Time/3600, Log.I_Pan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Servo Current');
ylabel('Current (A)', 'Color', 'r');
ax = gca; ax.YAxis(1).Color = 'r';

yyaxis right;
plot(Log.Time/3600, abs(Log.E_deg_Pan), 'b-', 'LineWidth', 1.5, 'DisplayName', 'Pan Error');
ylabel('Error (deg)', 'Color', 'b');
ax = gca; ax.YAxis(2).Color = 'b';

title('CLOSED-LOOP: Servo Current vs Pan Error (LDR Feedback)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
grid on;
xlabel('Time (hours)');

subplot(3,1,2); hold on;
plot(Log.Time/3600, Log.ServoVelPan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Pan Velocity');
plot(Log.Time/3600, Log.ServoVelTilt, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Tilt Velocity');
yline(ServoProps.MaxSpeed, 'k--', sprintf('Max Speed: %.0f deg/s', ServoProps.MaxSpeed), 'LineWidth', 1.5);
title('Servo Motor Velocities (Actual Physical Speed)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylabel('Velocity (deg/s)');
grid on;

subplot(3,1,3); hold on;
% Convert sun position to azimuth/elevation over time if stored
if ~isempty(FlipLog.times) && length(FlipLog.azimuth_sun) > 1
    plot(FlipLog.times/3600, FlipLog.azimuth_sun, 'y-', 'LineWidth', 1.5, 'DisplayName', 'Sun Azimuth');
    hold on;
    plot(FlipLog.times/3600, FlipLog.elevation_sun, 'c-', 'LineWidth', 1.5, 'DisplayName', 'Sun Elevation');
    plot(FlipLog.times/3600, 90 - FlipLog.target_pan_final, 'r--', 'LineWidth', 1, 'DisplayName', 'Target Pan');
    plot(FlipLog.times/3600, 90 - FlipLog.target_tilt_final, 'b--', 'LineWidth', 1, 'DisplayName', 'Target Tilt');
else
    text(0.5, 0.5, 'Insufficient FlipLog data', 'HorizontalAlignment', 'center', 'Units', 'normalized');
end
title('Sun Position Trajectory', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
ylabel('Angle (deg)');
xlabel('Time (hours)');
grid on;

fprintf('Plots complete!\n\n');

%% ============================================================
%% HELPER FUNCTIONS
%% ============================================================

function [azimuth, elevation] = cartesian2spherical(S_vec)
    x = S_vec(1); y = S_vec(2); z = S_vec(3);
    norm_vec = norm(S_vec);
    if norm_vec > 0
        x = x / norm_vec;
        y = y / norm_vec;
        z = z / norm_vec;
    end
    azimuth = atan2d(y, x);
    if azimuth < 0
        azimuth = azimuth + 360;
    end
    elevation = asind(z);
end

function [adjusted_pan, adjusted_tilt, is_flip, is_reachable] = applyFlipLogic(ideal_pan, ideal_tilt, limits)
    pan_lim = limits.Pan;
    tilt_lim = limits.Tilt;
    
    if (abs(ideal_pan) <= pan_lim) && (abs(ideal_tilt) <= tilt_lim)
        adjusted_pan = ideal_pan;
        adjusted_tilt = ideal_tilt;
        is_flip = false;
        is_reachable = true;
        return;
    end
    
    flip_pan = ideal_pan + 180;
    if flip_pan > 180
        flip_pan = flip_pan - 360;
    end
    flip_tilt = -ideal_tilt;
    
    if (abs(flip_pan) <= pan_lim) && (flip_tilt >= -90) && (flip_tilt <= 90)
        adjusted_pan = flip_pan;
        adjusted_tilt = flip_tilt;
        is_flip = true;
        is_reachable = true;
        return;
    end
    
    adjusted_pan = max(-pan_lim, min(pan_lim, ideal_pan));
    adjusted_tilt = max(-tilt_lim, min(tilt_lim, ideal_tilt));
    is_flip = false;
    is_reachable = false;
end

function result = ternary(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
