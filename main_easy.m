%% ╔════════════════════════════════════════════════════════════════════════╗
%% ║              SOLAR TRACKER - OPTIMIZED MAIN (Refactored)               ║
%% ║                                                                        ║
%% ║  CHANGE ONLY 2 PARAMETERS - Everything else uses organized functions ║
%% ╚════════════════════════════════════════════════════════════════════════╝

clear; clc; close all;

%% ════════════════════════════════════════════════════════════════════════════
%% ░░░░░░░░░░░░░░░░░░░░░░  CONFIGURATION  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
%% ════════════════════════════════════════════════════════════════════════════

SCENARIO = 'EXTREME';           % REALISTIC, VEHICLE_SLOW, VEHICLE_FAST, ZENITH_STATIC, FLIP_BOUNDARY, EXTREME, SOLAR_DAY, SOLAR_FAST
CONTROL_MODE = 'pid';                 % 'pid' (PID velocity), 'fuzzy' (Mamdani FLC), or 'open_loop'
PHYSICS_MODEL = 'THEORETICAL';         % 'SIMPLE' (Ideal Servo), 'COMPLEX' (DC Motor + Inductance), 'THEORETICAL' (Academic 2nd-order)

SimDate = datetime(2023, 10, 21, 8, 0, 0);  % Start at 8:00 AM for visible sun movement (ignored if SOLAR_DAY scenario)

% ══════════════════════════════════════════════════════════════════════════
% SIMULATION TIMING PARAMETERS (Only timing allowed in main)
% ══════════════════════════════════════════════════════════════════════════
dt_physics = 0.01;              % Physics simulation timestep [seconds]
dt_control = 0.01;              % Control loop timestep [seconds]
control_decimation = 1;         % Execute controller every N physics steps
DrawSkip = 5;                  % Render graphics every N control steps (0 = no graphics)

fprintf('╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  SOLAR TRACKER - OPTIMIZED MAIN (Function-Based Architecture) ║\n');
fprintf('║                                                              ║\n');
fprintf('║  Scenario:     %-40s ║\n', SCENARIO);
fprintf('║  Control:      %-40s ║\n', CONTROL_MODE);
fprintf('║  Physics:      %-40s ║\n', PHYSICS_MODEL);
fprintf('║  dt_physics:   %.3f s (control: %.3f s)                    ║\n', dt_physics, dt_control);
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

% Add all folders to path
addpath(genpath(pwd));

%% ════════════════════════════════════════════════════════════════════════════
%% LOAD SCENARIO & CONFIGURE SYSTEM
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Loading scenario: %s\n', SCENARIO);
Scenario = generateScenario(SCENARIO);

spiral_speed = Scenario.spiral_speed;
spiral_widen = Scenario.spiral_widen;
duration_sec = Scenario.duration_sec;

fprintf('Sun speed: %.4f °/s | Duration: %.0f s (%.1f min)\n\n', spiral_speed, duration_sec, duration_sec/60);

% ══════════════════════════════════════════════════════════════════════════════
% PARAMETER OWNERSHIP PHILOSOPHY (Phase 2 Refactoring)
% ══════════════════════════════════════════════════════════════════════════════
% Each module now OWNS and DEFINES its own parameters (see owning module code):
% - getSunVector.m owns: location params (from Scenario, which owns location)
% - readLDRs.m owns: ApexAngle (default 120°)
% - initSolarWorld.m owns: R_dome (default 1.5 m)
% - initSystemMechanics.m owns: servo dimensions (±100°/±90°)
% - pvPanelPower.m owns: panel area (0.04 m², 4×0.01 m² petals), efficiency (20%), tilt (41°)
% - pvTrackerPower.m owns: panel area (0.04 m², 4×0.01 m² petals), efficiency (20%)
% - applyFlipLogic.m owns: servo limits (±100°/±90°)
% - StateManagerFSM.m owns: FSM thresholds (night, lost, found, lock)
% - PID_VelocityController.m owns: Kp, Ki, Kd gains
% - FuzzyLogicController.m owns: fuzzy scaling factors
% ══════════════════════════════════════════════════════════════════════════════

% Only real sun (getSunVector) if SOLAR_DAY scenario, otherwise use spiral
TEST_MODE = ~strcmpi(Scenario.name, 'SOLAR_DAY');
fprintf('TEST_MODE (spiral): %d | Scenario: %s | Real sun: %s\n\n', TEST_MODE, Scenario.name, ~TEST_MODE);

% ── PVGIS LOADING BLOCK (Only for SOLAR_DAY scenario) ─────────────────────
if ~TEST_MODE
    PVData_full = loadPVGIS(Scenario.pvgis_file);
    [PVData, DayStats] = filterPVGISbyDate(PVData_full, ...
        Scenario.analysis_mode, Scenario.analysis_date);

    fprintf('╔══════════════════════════════════════════╗\n');
    fprintf('║  SOLAR DAY ANALYSIS                      ║\n');
    fprintf('╚══════════════════════════════════════════╝\n');
    fprintf('  %-24s %s\n', 'Reference Date:', ...
        string(DayStats.date, 'dd-MMM-yyyy'));
    fprintf('  %-24s %.1f W/m²\n', 'Peak Irradiance:', ...
        DayStats.peak_irradiance);
    fprintf('  %-24s %.2f hours\n', 'Daylight Duration:', ...
        DayStats.daylight_hours);
    fprintf('  %-24s %.2f Wh/m²\n\n', 'Daily Insolation:', ...
        DayStats.daily_insolation);
end
% ─────────────────────────────────────────────────────────────────────────

%% ════════════════════════════════════════════════════════════════════════════
%% SYSTEM INITIALIZATION
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Initializing system...\n');

% --- Simulation Date and Start Time ---
if strcmpi(Scenario.name, 'SOLAR_DAY')
    SimDate = Scenario.date + hours(Scenario.t_start_hour);
else
    SimDate = datetime(2024, 10, 21, 8, 0, 0);  % original hardcoded value
end

fprintf('SimDate: %s | Scenario: %s | Location: %.3f°N, %.3f°E\n\n', ...
    SimDate, Scenario.name, Scenario.lat, Scenario.lon);

% Initialize visualization (functions own their parameters internally)
handles = initSolarWorld();  % Owns R_dome internally (default 1.5)
ax = gca; set(ax, 'OuterPosition', [0, 0, 0.75, 1]);
Mech = initSystemMechanics(ax);  % Owns servo dimensions internally
SunDistance = 1.1;  % Visualization scale: bring sun closer for better initial visibility

% Servo states
StatePan = struct('Angle', 0, 'Velocity', 0, 'Current', 0);
StateTilt = struct('Angle', 0, 'Velocity', 0, 'Current', 0);

% Scenario-specific initialization
if strcmp(SCENARIO, 'ZENITH_STATIC')
    StatePan.Angle = 45.0;
    StateTilt.Angle = 2.0;
    fprintf('Initialized at Pan=45°, Tilt=2° (near zenith)\n');
elseif strcmp(SCENARIO, 'FLIP_BOUNDARY')
    StatePan.Angle = 10.0;
    StateTilt.Angle = 45.0;
    fprintf('Initialized at Pan=10°, Tilt=45° for flip test\n');
end

% FSM state (Supervisor persistence)
FSM_State = struct('mode', 'TRACKING', 'e_pan_prev', 0, 'e_tilt_prev', 0, ...
                   'de_pan_filtered', 0, 'de_tilt_filtered', 0, 'search_phase', 0);

% Controller state (PID integrators / FLC placeholder)
ControlState = struct('I_pan', 0, 'I_tilt', 0);

% Supervisor/FSM parameters (owned by Controllers/StateManagerFSM.m)
% Values from Scenario with embedded defaults
SupervisorParams = struct();
SupervisorParams.night_threshold    = getFieldOrDefault(Scenario, 'night_threshold', 0.3);
SupervisorParams.sun_lost_threshold = getFieldOrDefault(Scenario, 'sun_lost_threshold', 0.5);
SupervisorParams.sun_found_threshold = getFieldOrDefault(Scenario, 'sun_found_threshold', 1.0);
SupervisorParams.lock_threshold     = getFieldOrDefault(Scenario, 'lock_threshold', 0.5);
SupervisorParams.search_speed       = getFieldOrDefault(Scenario, 'search_speed', 3.0);
SupervisorParams.tracking_deadband  = getFieldOrDefault(Scenario, 'tracking_deadband', 3.0);  % °
SupervisorParams.batch_interval     = getFieldOrDefault(Scenario, 'batch_interval', 120.0);  % s
SupervisorParams.max_burst_time     = getFieldOrDefault(Scenario, 'max_burst_time', 8.0);    % s
SupervisorParams.zenith_pan_lock    = 5;        % Pan lock at zenith ±5°
SupervisorParams.tau_derivative     = 2.0;      % EMA time constant [s] — dt-invariant

% Command smoothing
CommandSmoothing = struct('target_pan_smoothed', 0, 'target_tilt_smoothed', 0);

% Flip blend factor for controller target vs sun-derived target (0=no blend, 1=full sun target)
FLIP_OVERRIDE_FACTOR = 0.5;
USE_FLIP_LOGIC = true;

% Flip tracking
flip_state = struct('is_flipped', false, 'flip_count', 0, 'last_flip_time', -inf);
FlipLog = struct('times', [], 'is_flipped', [], 'azimuth_sun', [], 'elevation_sun', [], ...
                 'is_reachable', [], 'target_pan_final', [], 'target_tilt_final', []);

% Info box for display
InfoBox = annotation('textbox', [0.76, 0.2, 0.23, 0.7], ...
                     'String', 'Initializing...', ...
                     'EdgeColor', 'k', 'BackgroundColor', [0.95 0.95 0.95], ...
                     'FaceAlpha', 0.8, 'FontSize', 10, 'FontName', 'Consolas');

fprintf('✓ System initialized\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% RETRIEVE MODULE PARAMETERS (One-time before loop)
%% ════════════════════════════════════════════════════════════════════════════

% Call each function once to extract owned parameters via props struct
% (Parameters will be used in plots and logging without duplication)

[~, ~, ServoProps] = stepTheoreticalServo(StatePan, 0, dt_physics, 'Pan');
[~, ~, ~, PIDProps] = PID_VelocityController(struct('e_pan', 0, 'e_tilt', 0, 'de_pan', 0, 'de_tilt', 0, 'mode', 'IDLE'), ControlState, [], dt_control);
[~, ~, ~, FuzzyProps] = FuzzyLogicController(struct('e_pan', 0, 'e_tilt', 0, 'de_pan', 0, 'de_tilt', 0, 'mode', 'IDLE'), ControlState, dt_control);
[~, ~, ~, FSMProps] = StateManagerFSM(zeros(1,4), zeros(3,1), 0, 0, FSM_State, SupervisorParams, dt_control, false);
[~, ~, ~, ~, ~, LDRProps] = readLDRs([0;0;1], [], []);
[~, PanelFixedProps] = pvPanelPower(0, 0, 0, struct('A', 0.04, 'eta', 0.20));   % 4×0.01 m² petals
[~, PanelTrackerProps] = pvTrackerPower(0, 0, struct('A', 0.04, 'eta', 0.20)); % 4×0.01 m² petals

fprintf('✓ Parameters retrieved from all modules\n');
fprintf('  Servo MaxSpeed: %.1f deg/s\n', ServoProps.MaxSpeed);
fprintf('  PID Kp=%.4f, Ki=%.4f\n', PIDProps.Kp, PIDProps.Ki);
fprintf('  Micro-Tracker (4 petals): %.4f m²  |  Fixed tilt: %d°  |  Efficiency: %.0f%%\n', ...
    PanelTrackerProps.Area, PanelFixedProps.TiltDeg, PanelTrackerProps.Efficiency*100);

%% ════════════════════════════════════════════════════════════════════════════
%% SIMULATION LOOP
%% ════════════════════════════════════════════════════════════════════════════

time_vector = 0 : dt_physics : duration_sec;
num_steps = length(time_vector);

% Preallocate logs
Log.Time = time_vector;
Log.TargetPan = zeros(num_steps, 1); Log.ActualPan = zeros(num_steps, 1);
Log.TargetTilt = zeros(num_steps, 1); Log.ActualTilt = zeros(num_steps, 1);
Log.ServoVelPan = zeros(num_steps, 1); Log.ServoVelTilt = zeros(num_steps, 1);
Log.I_Pan = zeros(num_steps, 1); Log.I_Tilt = zeros(num_steps, 1);
Log.IsFlip = zeros(num_steps, 1);
Log.LDR_Voltage = zeros(num_steps, 4); Log.FSM_Mode = cell(num_steps, 1);
Log.V_Total = zeros(num_steps, 1);
Log.E_norm_Pan = zeros(num_steps, 1); Log.E_norm_Tilt = zeros(num_steps, 1);
Log.E_deg_Pan = zeros(num_steps, 1); Log.E_deg_Tilt = zeros(num_steps, 1);
Log.Incidence = zeros(num_steps, 1); Log.IsLocked = zeros(num_steps, 1);
Log.PID_P_Pan = zeros(num_steps, 1); Log.PID_I_Pan = zeros(num_steps, 1); Log.PID_D_Pan = zeros(num_steps, 1);
Log.PID_P_Tilt = zeros(num_steps, 1); Log.PID_I_Tilt = zeros(num_steps, 1); Log.PID_D_Tilt = zeros(num_steps, 1);
Log.Power_Pan = zeros(num_steps, 1); Log.Power_Tilt = zeros(num_steps, 1); Log.Power_Total = zeros(num_steps, 1);
Log.LockCounter = zeros(num_steps, 1);
Log.LDR_DynamicRange = zeros(num_steps, 1);
Log.Servo_Velocity_Pan = zeros(num_steps, 1); Log.Servo_Velocity_Tilt = zeros(num_steps, 1);
Log.Servo_EquivD_Pan = zeros(num_steps, 1); Log.Servo_EquivD_Tilt = zeros(num_steps, 1);
Log.Irradiance = zeros(num_steps, 1);  % Solar irradiance W/m^2
Log.SolarPower = zeros(num_steps, 1); % Available solar power (based on sun elevation)
Log.FLC_Vel_Pan = zeros(num_steps, 1); Log.FLC_Vel_Tilt = zeros(num_steps, 1);
Log.FLC_Rate_Pan = zeros(num_steps, 1); Log.FLC_Rate_Tilt = zeros(num_steps, 1);

% ── Addition 3 — Log preallocations (always, regardless of mode) ───────
Log.P_fixed       = zeros(num_steps, 1);  % Fixed panel power (W)
Log.P_tracker     = zeros(num_steps, 1);  % Tracker panel power (W)
Log.P_net_tracker = zeros(num_steps, 1);  % Net power after motor cost (W)
Log.G             = zeros(num_steps, 1);  % Irradiance W/m²

% ── Addition 4 — Sub-panel power logging ────────────────────────────────
Log.P_subpanels = zeros(num_steps, 4);    % Power from 4 lateral panels [Right, Left, Up, Down]
Log.P_subpanel_total = zeros(num_steps, 1);  % Total power from all lateral panels

fprintf('Starting simulation (%d steps, %.0f seconds)...\n\n', num_steps, duration_sec);
G_now = 0;  % Pre-initialize for PVGIS mode (assigned inside loop after first step)

% ── Extract SubPanelProps once before loop ──────────────────────────────
[~, SubPanelProps] = pvSubPanelPower(0, [0;0;1], []);

for i = 1:num_steps
    % Safety check
    if ~isvalid(handles.h_Sun) || ~isvalid(Mech.h_Pan)
        fprintf('Simulation stopped (Window closed).\n');
        break;
    end
    
    current_time = SimDate + seconds(time_vector(i));
    sim_time_elapsed = time_vector(i);
    
    %% SUN POSITION
    if TEST_MODE
        angle_phi = spiral_speed * sim_time_elapsed;
        angle_alpha = 90 - (spiral_widen * sim_time_elapsed);
        if angle_alpha < 0, angle_alpha = 0; end
        
        az = deg2rad(angle_phi);
        el = deg2rad(angle_alpha);
        
        % ENU Frame: must match getSunVector.m frame definition
        % S_x = cos(el) * sin(az)  [East]
        % S_y = cos(el) * cos(az)  [North]
        % S_z = sin(el)             [Up]
        S_vec = [cos(el)*sin(az); cos(el)*cos(az); sin(el)];
        alpha = angle_alpha;
        phi = angle_phi;
    else
        [S_vec, alpha, phi] = getSunVector( ...
            Scenario.lat, Scenario.lon, current_time, Scenario.tz);
        if alpha <= 0
            alpha = 0;
            S_vec = [0, 0, 0];
        end
    end
    
    %% CONTROL UPDATE
    if mod(i-1, control_decimation) == 0
        theta_pan_curr = StatePan.Angle;
        theta_tilt_curr = StateTilt.Angle;
        
        % Transform sun vector to body frame
        % FIXED: Corrected to use X-axis rotation for tilt (was Y-axis)
        % ENU frame: x=East (pan axis), y=North, z=Up (vertical)
        % Pan rotates about Z-axis: CCW rotation in world frame
        % Tilt rotates about X-axis (in pan-rotated frame): perpendicular to pan direction
        cp = cosd(theta_pan_curr); sp = sind(theta_pan_curr);
        ct = cosd(theta_tilt_curr); st = sind(theta_tilt_curr);
        
        % Pan rotation (Z-axis)
        Sx_rz = cp*S_vec(1) - sp*S_vec(2);
        Sy_rz = sp*S_vec(1) + cp*S_vec(2);
        Sz_rz = S_vec(3);
        
        % FIXED: Tilt rotation now about X-axis (not Y-axis)
        % X-rotation: [1  0    0  ] [Sx]   [Sx         ]
        %            [0  cos -sin] [Sy] = [cos*Sy-sin*Sz]
        %            [0  sin  cos] [Sz]   [sin*Sy+cos*Sz]
        S_body_pre = [Sx_rz; ct*Sy_rz - st*Sz_rz; st*Sy_rz + ct*Sz_rz];
        S_body_norm = S_body_pre / (norm(S_body_pre) + 1e-8);
        
        % Read LDR sensors (owned by Sensors/readLDRs.m, owns default ApexAngle=120°)
        [~, LDR_V_ctrl, ~, ~, ~, ~] = readLDRs(S_body_norm);
        
        % Get sun position in world frame
        [azimuth_sun, elevation_sun] = cartesian2spherical(S_vec);
        ideal_pan_from_azimuth = azimuth_sun;
        ideal_tilt_from_elevation = max(-90, min(90, 90 - elevation_sun));
        
        if ideal_pan_from_azimuth > 180
            ideal_pan_from_azimuth = ideal_pan_from_azimuth - 360;
        end
        
        % Apply flip logic (owned by Utils/applyFlipLogic.m, owns default limits ±100°/±90°)
        [adjusted_pan_from_sun, adjusted_tilt_from_sun, is_flip, is_reachable] = ...
            applyFlipLogic(ideal_pan_from_azimuth, ideal_tilt_from_elevation);
        
      %% ═══ BLOCK A: SUPERVISOR (StateManagerFSM) ═══
        [ErrorSignal, FSM_State, DebugSup, ~] = StateManagerFSM(...
            LDR_V_ctrl, S_body_pre, theta_pan_curr, theta_tilt_curr, ...
            FSM_State, SupervisorParams, dt_control, is_flip);
        
        %% ═══ BLOCK B: CONTROLLER (Swappable) ═══
        if strcmp(CONTROL_MODE, 'fuzzy')
            [VelCmd, ControlState, DebugCtrl, ~] = FuzzyLogicController(...
                ErrorSignal, ControlState, dt_control);
        else
            [VelCmd, ControlState, DebugCtrl, ~] = PID_VelocityController(...
                ErrorSignal, ControlState, struct(), dt_control);
        end
        
        %% ═══ VELOCITY → POSITION INTEGRATION (was inside Controller) ═══
        pan_limit_val = 180;  % Pan limit owned by applyFlipLogic
        target_pan_from_ctrl  = theta_pan_curr  + VelCmd.v_pan  * dt_control;
        target_tilt_from_ctrl = theta_tilt_curr + VelCmd.v_tilt * dt_control;
        target_pan_from_ctrl  = max(-pan_limit_val, min(pan_limit_val, target_pan_from_ctrl));
        target_tilt_from_ctrl = max(-90, min(90, target_tilt_from_ctrl));
        
        % Determine if FSM is in an active control state
        fsm_is_active = ismember(FSM_State.mode, {'TRACKING', 'SEARCH', 'PARK'});
        
        % Blend with flip logic (owned by applyFlipLogic)
        % Only apply flip override if FSM is actively controlling motion
        if is_reachable && USE_FLIP_LOGIC && FLIP_OVERRIDE_FACTOR > 0 && fsm_is_active
            target_pan = target_pan_from_ctrl + FLIP_OVERRIDE_FACTOR * (adjusted_pan_from_sun - target_pan_from_ctrl);
            target_tilt = target_tilt_from_ctrl + FLIP_OVERRIDE_FACTOR * (adjusted_tilt_from_sun - target_tilt_from_ctrl);
        else
            target_pan = target_pan_from_ctrl;
            target_tilt = target_tilt_from_ctrl;
        end
        
        % Build DebugFSM from Supervisor output for downstream compatibility
        DebugFSM = DebugSup;
        DebugFSM.vel_pan  = VelCmd.v_pan;
        DebugFSM.vel_tilt = VelCmd.v_tilt;
        DebugFSM.target_pan  = target_pan;
        DebugFSM.target_tilt = target_tilt;
        
        % Command smoothing (owned by PID controller, use default alpha)
        % In HOLD/IDLE, freeze the smoothed target at current servo position so motors truly rest
        if fsm_is_active
            smooth_alpha_active = 0.95;
            CommandSmoothing.target_pan_smoothed = (1 - smooth_alpha_active) * CommandSmoothing.target_pan_smoothed + smooth_alpha_active * target_pan;
            CommandSmoothing.target_tilt_smoothed = (1 - smooth_alpha_active) * CommandSmoothing.target_tilt_smoothed + smooth_alpha_active * target_tilt;
        else
            % HOLD/IDLE: freeze smoothed target at current position so servo truly rests
            CommandSmoothing.target_pan_smoothed = theta_pan_curr;
            CommandSmoothing.target_tilt_smoothed = theta_tilt_curr;
        end
        
        % Log flip data (owned by applyFlipLogic, using default enable)
        if is_reachable
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
    
    %% SERVO PHYSICS (Model dispatch — Block C)
    if strcmp(PHYSICS_MODEL, 'COMPLEX')
        [StatePan, ~]  = stepDCMotorPhysics(StatePan, target_pan_smooth, dt_physics, 'Pan');
        [StateTilt, ~] = stepDCMotorPhysics(StateTilt, target_tilt_smooth, dt_physics, 'Tilt');
    elseif strcmp(PHYSICS_MODEL, 'THEORETICAL')
        [StatePan, ~, ~]  = stepTheoreticalServo(StatePan, target_pan_smooth, dt_physics, 'Pan');
        [StateTilt, ~, ~] = stepTheoreticalServo(StateTilt, target_tilt_smooth, dt_physics, 'Tilt');
    else
        [StatePan, ~]  = stepAdvancedServoPhysics(StatePan, target_pan_smooth, dt_physics, 'Pan');
        [StateTilt, ~] = stepAdvancedServoPhysics(StateTilt, target_tilt_smooth, dt_physics, 'Tilt');
    end
    
    theta_pan = StatePan.Angle;
    theta_tilt = StateTilt.Angle;
    
    %% ═══ PRE-VISUALIZATION CALCULATIONS ═══
    % Calculate irradiance for sub-panel power (needed before info box)
    sun_el_rad = deg2rad(elevation_sun);
    irradiance = 1000 * max(0, sin(sun_el_rad));  % Clear-sky model
    
    % Determine G_irradiance source and compute sub-panel power
    if ~TEST_MODE
        G_irradiance = G_now;  % Use PVGIS data
    else
        G_irradiance = irradiance;  % Use elevation-based model
    end
    [P_subpanels_i, ~] = pvSubPanelPower(G_irradiance, S_body_norm, []);
    
    %% ═══ BODY ANIMATION (Every Step) ═══
    % Update hgtransform matrices every physics step for smooth motion
    % (NOT just every visualization step, otherwise body lags motor state)
    try
        % FIXED: Negate pan angle for ENU convention (CW from North)
        % makehgtform('zrotate', angle) rotates CCW (right-hand rule)
        % ENU azimuth is CW from North, so negate the angle for correct visualization
        M_pan = makehgtform('zrotate', deg2rad(-theta_pan));
        set(Mech.h_Pan, 'Matrix', M_pan);
        
        M_tilt_trans = makehgtform('translate', Mech.PivotOffset);
        % FIXED: X-rotation with negated angle (body frame rotates vector, visualization rotates frame)
        M_tilt_rot = makehgtform('xrotate', deg2rad(-theta_tilt));
        set(Mech.h_Tilt, 'Matrix', M_tilt_trans * M_tilt_rot);
    catch
        % Handle silently; visualization may have window closed
    end
    
    %% VISUALIZATION & INFO DISPLAY
    if DrawSkip > 0 && mod(i, DrawSkip) == 0
        try
            P_sun = S_vec * SunDistance;
            if isvalid(handles.h_PathSun)
                addpoints(handles.h_PathSun, P_sun(1), P_sun(2), P_sun(3));
            end
            updateSolarWorld(handles, S_vec, SunDistance, current_time, alpha, phi);
            
            % Calculate and draw tracker path (Red Line)
            % FIXED: Negate pan angle for ENU convention, negate tilt for X-rotation direction
            M_pan_temp = makehgtform('zrotate', deg2rad(-theta_pan));
            M_tilt_temp = makehgtform('xrotate', deg2rad(-theta_tilt));
            R_Total = M_pan_temp(1:3,1:3) * M_tilt_temp(1:3,1:3);
            P_Tracker = (R_Total * [0;0;1]) * SunDistance;
            if isvalid(handles.h_PathTracker)
                addpoints(handles.h_PathTracker, P_Tracker(1), P_Tracker(2), P_Tracker(3));
            end
        catch
            % Silently handle graphics errors (window may be closed)
        end
        
        try
            % Metrics for display
            [E_pan_disp, E_tilt_disp, E_deg_pan_disp, E_deg_tilt_disp, ~] = controlLDR(...
                LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4), S_body_norm);
            [theta_inc_disp, ~] = checkAlignment(S_body_norm);
            
            flip_indicator = ternary(is_flip, ' FLIP', '→ NORMAL');
            
            % Calculate e_total from normalized error signals (valid in all FSM states)
            e_total_display = sqrt(E_deg_pan_disp^2 + E_deg_tilt_disp^2);
            
            % Update info box
            InfoStr = {
                sprintf('═══════ SCENARIO: %s ═══════', upper(SCENARIO)), ...
                '', ...
                sprintf('TIME: %.1f / %.0f s', sim_time_elapsed, duration_sec), ...
                '', ...
                sprintf('☀️  SUN POSITION'), ...
                sprintf('    Az: %.1f°  |  El: %.1f°', azimuth_sun, elevation_sun), ...
                '', ...
                sprintf('📡 LDR VOLTAGES'), ...
                sprintf('    R:%.2fV  L:%.2fV  U:%.2fV  D:%.2fV', ...
                        LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4)), ...
                sprintf('    Total: %.2f V', sum(LDR_V_ctrl)), ...
                '', ...
                sprintf('🎯 MOTOR ANGLES'), ...
                sprintf('    Pan:  %.1f°  |  Tilt: %.1f°', theta_pan, theta_tilt), ...
                '', ...
                sprintf('❌ ERRORS'), ...
                sprintf('    Pan:  %+.2f°  |  Tilt: %+.2f°', E_deg_pan_disp, E_deg_tilt_disp), ...
                sprintf('    Inc:  %.3f°  (Target: <0.5°)', theta_inc_disp), ...
                '', ...
                sprintf('🤖 FSM STATE'), ...
                sprintf('    Mode: %s', FSM_State.mode), ...
                sprintf('    Hold: %.0f/%.0f s  Burst: %.1f/%.0f s', ...
                        FSM_State.hold_timer, SupervisorParams.batch_interval, ...
                        FSM_State.burst_timer, SupervisorParams.max_burst_time), ...
                sprintf('    e_total: %.2f°  (Wake > %.1f°)', e_total_display, SupervisorParams.tracking_deadband), ...
                '', ...
                sprintf('⚡ MOTOR CURRENT'), ...
                sprintf('    Pan: %.3f A  |  Tilt: %.3f A', StatePan.Current, StateTilt.Current), ...
                sprintf('    V_Pan: %.1f °/s | V_Tilt: %.1f °/s', abs(StatePan.Velocity), abs(StateTilt.Velocity)), ...
                '', ...
                sprintf('� SUB-PANELS (W)'), ...
                sprintf('    R:%.2f  L:%.2f  U:%.2f  D:%.2f', ...
                        P_subpanels_i(1), P_subpanels_i(2), ...
                        P_subpanels_i(3), P_subpanels_i(4)), ...
                sprintf('    Total: %.3f W', sum(P_subpanels_i)), ...
                '', ...
                sprintf('�🔄 FLIP: %s (Count: %d)', flip_indicator, flip_state.flip_count)
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
    
    % ── Addition 5 — PVGIS Power Logging (only for SOLAR_DAY) ─────────────────
    if ~TEST_MODE
        pvgis_t = Scenario.t_start_hour * 3600 + sim_time_elapsed;
        [G_now, ~]          = getPVGISatTime(pvgis_t, PVData);
        Log.G(i)            = G_now;
        [Log.P_fixed(i), ~]      = pvPanelPower(G_now, azimuth_sun, elevation_sun, struct('A', PanelFixedProps.Area, 'eta', 0.20));
        [Log.P_tracker(i), ~]    = pvTrackerPower(G_now, theta_inc, struct('A', PanelTrackerProps.Area, 'eta', PanelTrackerProps.Efficiency));
        Log.P_net_tracker(i)= Log.P_tracker(i) - Log.Power_Total(i);
    else
        % Use elevation-based irradiance model for TEST_MODE
        Log.G(i)            = G_irradiance;  % Clear-sky irradiance [W/m²]
        [Log.P_fixed(i), ~]      = pvPanelPower(G_irradiance, azimuth_sun, elevation_sun, struct('A', PanelFixedProps.Area, 'eta', 0.20));
        [Log.P_tracker(i), ~]    = pvTrackerPower(G_irradiance, theta_inc, struct('A', PanelTrackerProps.Area, 'eta', PanelTrackerProps.Efficiency));
        Log.P_net_tracker(i)= Log.P_tracker(i) - Log.Power_Total(i);
    end
    % ─────────────────────────────────────────────────────────────────────────
    
    % Control Terms Logging (3-Block Architecture)
    if strcmp(CONTROL_MODE, 'fuzzy')
        Log.FLC_Vel_Pan(i)  = VelCmd.v_pan;
        Log.FLC_Vel_Tilt(i) = VelCmd.v_tilt;
        Log.FLC_Rate_Pan(i) = ErrorSignal.de_pan;
        Log.FLC_Rate_Tilt(i) = ErrorSignal.de_tilt;
        Log.PID_P_Pan(i) = 0; Log.PID_P_Tilt(i) = 0;
        Log.PID_I_Pan(i) = 0; Log.PID_I_Tilt(i) = 0;
        Log.PID_D_Pan(i) = 0; Log.PID_D_Tilt(i) = 0;
    else
        Log.PID_P_Pan(i) = DebugCtrl.P_pan;
        Log.PID_P_Tilt(i) = DebugCtrl.P_tilt;
        Log.PID_I_Pan(i) = DebugCtrl.I_pan;
        Log.PID_I_Tilt(i) = DebugCtrl.I_tilt;
        Log.PID_D_Pan(i) = DebugCtrl.D_pan;
        Log.PID_D_Tilt(i) = DebugCtrl.D_tilt;
    end
    
    Log.Servo_Velocity_Pan(i) = StatePan.Velocity;
    Log.Servo_Velocity_Tilt(i) = StateTilt.Velocity;
    
    servo_error_pan = target_pan_smooth - theta_pan;
    servo_error_tilt = target_tilt_smooth - theta_tilt - Log.Servo_EquivD_Pan(i);
    % Servo parameters (owned by Physics modules)
    Servo_Kv = 0.05;                    % Velocity constant [V·s/deg]
    Log.Servo_EquivD_Pan(i) = Servo_Kv * servo_error_pan;
    Log.Servo_EquivD_Tilt(i) = Servo_Kv * servo_error_tilt;
    
    Log.Power_Pan(i) = StatePan.Current * ServoProps.V_supply;
    Log.Power_Tilt(i) = StateTilt.Current * ServoProps.V_supply;
    Log.Power_Total(i) = Log.Power_Pan(i) + Log.Power_Tilt(i);
    
    % Log irradiance (already computed in pre-visualization block)
    Log.Irradiance(i) = irradiance;
    Log.SolarPower(i) = Log.P_tracker(i);  % Log tracker power for analysis
    
    % ── Log sub-panel power (P_subpanels_i already computed in pre-visualization) ──
    Log.P_subpanels(i, :) = P_subpanels_i';
    Log.P_subpanel_total(i) = sum(P_subpanels_i);
    % ─────────────────────────────────────────────────────────────────────────────
    
    if theta_inc < SupervisorParams.lock_threshold
        Log.LockCounter(i) = 1;
    else
        Log.LockCounter(i) = 0;
    end
    
    Log.LDR_DynamicRange(i) = max(LDR_V_ctrl) - min(LDR_V_ctrl);
end

fprintf('✓ Simulation Complete.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% CUSTOM METRICS CALCULATION
%% ════════════════════════════════════════════════════════════════════════════

% Settling Time (when error becomes < 2% of max and stays there)
error_threshold = 0.1; % 0.1 degree threshold
settling_idx = find(Log.Incidence < error_threshold, 1);
if isempty(settling_idx)
    settling_time = duration_sec;
else
    settling_time = Log.Time(settling_idx);
end

% Rise Time (first time reaching 90% of final stable error)
final_error = mean(Log.Incidence(max(1, end-100):end));
rise_threshold = final_error + 0.9 * (max(Log.Incidence) - final_error);
rise_idx = find(Log.Incidence <= rise_threshold, 1);
if isempty(rise_idx)
    rise_time = duration_sec;
else
    rise_time = Log.Time(rise_idx);
end

% Overshoot (maximum error above final steady state)
if final_error > 0
    overshoot_pct = ((max(Log.Incidence) - final_error) / final_error) * 100;
else
    overshoot_pct = 0;
end

% Steady-State Error (last 10% of simulation)
steady_state_start = max(1, round(0.9 * length(Log.Incidence)));
steady_state_error = mean(Log.Incidence(steady_state_start:end));

% Energy metrics (using fixed power calculation, not PID_Params)
power_instant = Log.Power_Total(:);
total_energy = sum(power_instant) * dt_physics / 3600;
avg_power = mean(power_instant(power_instant > 0.001));
max_power = max(power_instant);

%% ════════════════════════════════════════════════════════════════════════════
%% PERFORMANCE SUMMARY
%% ════════════════════════════════════════════════════════════════════════════

fprintf('\n════════════════════════════════════════════════════════════════\n');
fprintf('                    PERFORMANCE SUMMARY\n');
fprintf('════════════════════════════════════════════════════════════════\n\n');

tracking_error_mean = mean(Log.Incidence);
tracking_error_max = max(Log.Incidence);
if length(Log.Incidence) > 100
    tracking_error_final = mean(Log.Incidence(end-100:end));
else
    tracking_error_final = mean(Log.Incidence);
end

lock_time = sum(Log.IsLocked) * dt_physics;
lock_percentage = (lock_time / duration_sec) * 100;

fprintf('┌─ TRACKING ACCURACY ─────────────────────────────────────────┐\n');
fprintf('│ Mean error:       %.3f deg\n', tracking_error_mean);
fprintf('│ Max error:        %.3f deg\n', tracking_error_max);
fprintf('│ Final error:      %.3f deg\n', tracking_error_final);
fprintf('└─────────────────────────────────────────────────────────────┘\n\n');

max_vel_pan = max(Log.ServoVelPan);
max_vel_tilt = max(Log.ServoVelTilt);

fprintf('┌─ SERVO PERFORMANCE ─────────────────────────────────────────┐\n');
fprintf('│ Max Pan velocity:  %.1f deg/s\n', max_vel_pan);
fprintf('│ Max Tilt velocity: %.1f deg/s\n', max_vel_tilt);
fprintf('│ Speed limit:       %.1f deg/s\n', ServoProps.MaxSpeed);
fprintf('└─────────────────────────────────────────────────────────────┘\n\n');

fprintf('┌─ LOCK PERFORMANCE ──────────────────────────────────────────┐\n');
fprintf('│ Time locked:      %.1f s (%.1f%%)\n', lock_time, lock_percentage);
fprintf('│ Lock threshold:    %.1f deg\n', SupervisorParams.lock_threshold);
fprintf('└─────────────────────────────────────────────────────────────┘\n\n');

fprintf('┌─ ADVANCED METRICS ──────────────────────────────────────────┐\n');
fprintf('│ Settling time:    %.2f s (error < 0.1°)\n', settling_time);
fprintf('│ Rise time:        %.2f s (reach 90%% of final)\n', rise_time);
fprintf('│ Overshoot:        %.1f%% above steady-state\n', overshoot_pct);
fprintf('│ Steady-state err: %.4f deg (last 10%% of test)\n', steady_state_error);
fprintf('└─────────────────────────────────────────────────────────────┘\n\n');

fprintf('┌─ ENERGY CONSUMPTION ────────────────────────────────────────┐\n');
fprintf('│ Total energy:     %.4f Wh\n', total_energy);
fprintf('│ Average power:    %.2f W\n', avg_power);
fprintf('│ Peak power:       %.2f W\n', max_power);
fprintf('└─────────────────────────────────────────────────────────────┘\n\n');

fprintf('════════════════════════════════════════════════════════════════\n\n');

% Check if system spent too much time in IDLE (indicates scenario exceeds bandwidth)
idle_pct = 100 * sum(strcmp(Log.FSM_Mode, 'IDLE')) / length(Log.FSM_Mode);
if idle_pct > 50
    fprintf('⚠️  WARNING: System spent %.1f%% time in IDLE state\n', idle_pct);
    fprintf('   → %s scenario sun speed may exceed tracker bandwidth\n', SCENARIO);
    fprintf('   → Try REALISTIC or VEHICLE_FAST for meaningful tracking analysis\n\n');
end

%% ════════════════════════════════════════════════════════════════════════════
%% LIGHTWEIGHT PLOTTING - FAST & EFFICIENT
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Generating plots...\n\n');

% Create results directory
results_dir = 'Results';
if ~isfolder(results_dir)
    mkdir(results_dir);
end
timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
scenario_dir = fullfile(results_dir, sprintf('%s_%s', SCENARIO, timestamp));
mkdir(scenario_dir);

% Determine time axis label and unit
time_axis = Log.Time / 3600;
time_label = 'Time (hours)';

%% FIGURE 1: System Performance
figure('Name', 'System Performance', 'Position', [100 50 1200 900]);

subplot(4,1,1); hold on;
plot(time_axis, Log.TargetPan / 60, 'b--', 'LineWidth', 1.2, 'DisplayName', 'Target');
plot(time_axis, Log.ActualPan / 60, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Actual');
title('Pan Axis Tracking', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Angle (deg)'); grid on; ylim([-200 200]);

subplot(4,1,2); hold on;
plot(time_axis, Log.TargetTilt, 'b--', 'LineWidth', 1.2, 'DisplayName', 'Target');
plot(time_axis, Log.ActualTilt, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Actual');
title('Tilt Axis Tracking', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Angle (deg)'); grid on;

subplot(4,1,3); hold on;
plot(time_axis, Log.TargetPan - Log.ActualPan, 'm', 'LineWidth', 1.5, 'DisplayName', 'Pan Error');
plot(time_axis, Log.TargetTilt - Log.ActualTilt, 'c', 'LineWidth', 1.5, 'DisplayName', 'Tilt Error');
yline(0, 'k--', 'LineWidth', 0.5);
title('Tracking Error', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Error (deg)'); grid on;

subplot(4,1,4);
plot(time_axis, Log.Incidence, 'k-', 'LineWidth', 1.5);
yline(1.0, 'r--', 'Target (1.0°)', 'LineWidth', 1.5);
yline(0.5, 'g--', 'Excellent (0.5°)', 'LineWidth', 1.5);
title('Incidence Angle', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (hours)'); ylabel('θ_{inc} (deg)'); grid on;
saveas(gcf, fullfile(scenario_dir, '01_System_Performance.png'));

%% FIGURE 2: LDR Sensor Analysis
figure('Name', 'LDR Sensor Analysis', 'Position', [150 30 1200 900]);

subplot(4,1,1); hold on;
plot(time_axis, Log.LDR_Voltage(:,1), 'r-', 'LineWidth', 1.2, 'DisplayName', 'Right');
plot(time_axis, Log.LDR_Voltage(:,2), 'b-', 'LineWidth', 1.2, 'DisplayName', 'Left');
plot(time_axis, Log.LDR_Voltage(:,3), 'g-', 'LineWidth', 1.2, 'DisplayName', 'Up');
plot(time_axis, Log.LDR_Voltage(:,4), 'm-', 'LineWidth', 1.2, 'DisplayName', 'Down');
title('LDR Voltage Outputs (GL5528 Sensors)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Voltage (V)'); ylim([0 5.5]); grid on;

subplot(4,1,2); hold on;
plot(time_axis, Log.E_norm_Pan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'E_{norm,Pan}');
plot(time_axis, Log.E_norm_Tilt, 'b-', 'LineWidth', 1.5, 'DisplayName', 'E_{norm,Tilt}');
yline(0, 'k--', 'LineWidth', 0.5); yline(0.05, 'g:', 'Deadzone', 'LineWidth', 1); yline(-0.05, 'g:', 'LineWidth', 1);
title('Normalized Error Index', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('E_{norm} [-1, +1]'); ylim([-1.1 1.1]); grid on;

subplot(4,1,3); hold on;
plot(time_axis, Log.E_deg_Pan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Pan Error');
plot(time_axis, Log.E_deg_Tilt, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Tilt Error');
yline(0, 'k--', 'LineWidth', 0.5); yline(0.5, 'g:', 'Deadzone (0.5°)', 'LineWidth', 1); yline(-0.5, 'g:', 'LineWidth', 1);
title('Angular Error from LDR', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Angle (deg)'); grid on;

subplot(4,1,4); hold on;
yyaxis left;
plot(time_axis, Log.Incidence, 'k-', 'LineWidth', 1.5);
yline(0.5, 'g--', 'Lock Threshold (0.5°)', 'LineWidth', 1.5);
yline(1.0, 'r--', 'Target (1.0°)', 'LineWidth', 1.5);
ylabel('\theta_{inc} (deg)'); ylim([0 max(90, max(Log.Incidence)*1.1)]);
yyaxis right;
area(time_axis, Log.IsLocked, 'FaceColor', 'g', 'FaceAlpha', 0.3, 'EdgeColor', 'none');
ylabel('Lock Status'); yticks([0 1]); yticklabels({'Searching', 'LOCKED'}); ylim([-0.1 1.5]);
title('Tracking Accuracy: Incidence with Lock Status', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (hours)'); grid on;
saveas(gcf, fullfile(scenario_dir, '02_LDR_Sensor_Analysis.png'));

%% FIGURE 3: Controller Analysis (PI or FLC)
if strcmp(CONTROL_MODE, 'fuzzy')
    figure('Name', 'FLC Fuzzy Logic Analysis', 'Position', [200 10 1200 900]);
    
    subplot(3,2,1); hold on;
    plot(time_axis, Log.FLC_Vel_Pan, 'r-', 'LineWidth', 1.5);
    yline(0, 'k--', 'LineWidth', 0.5);
    title('FLC Velocity Command (Pan)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('Vel (deg/s)'); grid on;
    
    subplot(3,2,2); hold on;
    plot(time_axis, Log.FLC_Vel_Tilt, 'b-', 'LineWidth', 1.5);
    yline(0, 'k--', 'LineWidth', 0.5);
    title('FLC Velocity Command (Tilt)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('Vel (deg/s)'); grid on;
    
    subplot(3,2,3); hold on;
    plot(time_axis, Log.FLC_Rate_Pan, 'r-', 'LineWidth', 1.5);
    yline(0, 'k--', 'LineWidth', 0.5);
    title('Error Rate dE/dt (Pan)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('Rate (deg/s)'); grid on;
    
    subplot(3,2,4); hold on;
    plot(time_axis, Log.FLC_Rate_Tilt, 'b-', 'LineWidth', 1.5);
    yline(0, 'k--', 'LineWidth', 0.5);
    title('Error Rate dE/dt (Tilt)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('Rate (deg/s)'); grid on;
    
    subplot(3,2,5); hold on;
    plot(time_axis, Log.E_deg_Pan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Error');
    plot(time_axis, Log.FLC_Vel_Pan, 'r--', 'LineWidth', 1, 'DisplayName', 'FLC Vel');
    yline(0, 'k--', 'LineWidth', 0.5);
    title('Error vs FLC Output (Pan)', 'FontSize', 11, 'FontWeight', 'bold');
    legend('Location', 'best'); ylabel('deg / deg/s'); xlabel('Time (hours)'); grid on;
    
    subplot(3,2,6); hold on;
    plot(time_axis, Log.E_deg_Tilt, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Error');
    plot(time_axis, Log.FLC_Vel_Tilt, 'b--', 'LineWidth', 1, 'DisplayName', 'FLC Vel');
    yline(0, 'k--', 'LineWidth', 0.5);
    title('Error vs FLC Output (Tilt)', 'FontSize', 11, 'FontWeight', 'bold');
    legend('Location', 'best'); ylabel('deg / deg/s'); xlabel('Time (hours)'); grid on;
    
    sgtitle('Fuzzy Logic Controller Analysis (Mamdani 7-MF)', 'FontSize', 14, 'FontWeight', 'bold');
else
    figure('Name', 'PID Control Analysis', 'Position', [200 10 1200 900]);
    
    subplot(3,2,1); hold on;
    plot(time_axis, Log.PID_P_Pan, 'r-', 'LineWidth', 1.5);
    title('P Term (Pan)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('P'); grid on;
    
    subplot(3,2,2); hold on;
    plot(time_axis, Log.PID_P_Tilt, 'b-', 'LineWidth', 1.5);
    title('P Term (Tilt)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('P'); grid on;
    
    subplot(3,2,3); hold on;
    plot(time_axis, Log.PID_I_Pan, 'r-', 'LineWidth', 1.5);
    yline(PIDProps.MaxIntegral, 'k--'); yline(-PIDProps.MaxIntegral, 'k--');
    title('I Term (Pan)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('I'); grid on;
    
    subplot(3,2,4); hold on;
    plot(time_axis, Log.PID_I_Tilt, 'b-', 'LineWidth', 1.5);
    yline(PIDProps.MaxIntegral, 'k--'); yline(-PIDProps.MaxIntegral, 'k--');
    title('I Term (Tilt)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('I'); grid on;
    
    subplot(3,2,5); hold on;
    plot(time_axis, Log.Servo_Velocity_Pan, 'r-', 'LineWidth', 1.5);
    title('Servo Velocity (Pan)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('°/s'); xlabel('Time (hours)'); grid on;
    
    subplot(3,2,6); hold on;
    plot(time_axis, Log.Servo_Velocity_Tilt, 'b-', 'LineWidth', 1.5);
    title('Servo Velocity (Tilt)', 'FontSize', 11, 'FontWeight', 'bold'); ylabel('°/s'); xlabel('Time (hours)'); grid on;
    
    sgtitle('PID Control Terms Analysis', 'FontSize', 14, 'FontWeight', 'bold');
end
saveas(gcf, fullfile(scenario_dir, '03_Controller_Analysis.png'));

%% FIGURE 4: FSM State Analysis
figure('Name', 'FSM State Machine', 'Position', [250 0 1200 600]);

subplot(2,1,1); hold on;
mode_numeric = zeros(num_steps, 1);
for i = 1:num_steps
    if isempty(Log.FSM_Mode{i}), mode_numeric(i) = 0; continue; end
    switch Log.FSM_Mode{i}
        case 'IDLE', mode_numeric(i) = 0;
        case 'TRACKING', mode_numeric(i) = 1;
        case 'SEARCH', mode_numeric(i) = 2;
        case 'SAFETY', mode_numeric(i) = 3;
        otherwise, mode_numeric(i) = -1;
    end
end
area(time_axis, mode_numeric, 'FaceAlpha', 0.5);
yticks([0 1 2 3]); yticklabels({'IDLE', 'TRACKING', 'SEARCH', 'SAFETY'}); ylim([-0.5 3.5]);
title('FSM State Over Time', 'FontSize', 12, 'FontWeight', 'bold'); ylabel('Mode'); grid on;

subplot(2,1,2); hold on;
plot(time_axis, Log.V_Total, 'k-', 'LineWidth', 1.5);
yline(SupervisorParams.night_threshold, 'b--', sprintf('Night (%.1fV)', SupervisorParams.night_threshold));
yline(SupervisorParams.sun_lost_threshold, 'r--', sprintf('Lost (%.1fV)', SupervisorParams.sun_lost_threshold));
yline(SupervisorParams.sun_found_threshold, 'g--', sprintf('Found (%.1fV)', SupervisorParams.sun_found_threshold));
title('Total LDR Voltage (FSM Decision Variable)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('V_{total} (V)'); xlabel('Time (hours)'); grid on;
saveas(gcf, fullfile(scenario_dir, '04_FSM_State_Machine.png'));

%% FIGURE 5: Energy Analysis
figure('Name', 'Energy Analysis', 'Position', [300 50 1200 900]);

power_instant = Log.Power_Total(:);
energy_cumulative = cumsum(power_instant) * dt_physics / 3600;

subplot(3,1,1); hold on;
area(time_axis, power_instant, 'FaceColor', 'b', 'FaceAlpha', 0.3, 'EdgeColor', 'k', 'LineWidth', 1.5);
avg_pwr = mean(power_instant);
yline(avg_pwr, 'r--', sprintf('Avg: %.2f W', avg_pwr), 'LineWidth', 2);
title('Instantaneous Power Consumption', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Power (W)'); grid on;

subplot(3,1,2); hold on;
area(time_axis, energy_cumulative, 'FaceColor', 'b', 'FaceAlpha', 0.3, 'EdgeColor', 'k', 'LineWidth', 1.5);
title('Cumulative Energy', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Energy (Wh)'); grid on;

subplot(3,1,3); hold on;
area(time_axis, Log.P_subpanels(:, 1), 'FaceColor', 'r', 'FaceAlpha', 0.6, 'DisplayName', 'Right');
area(time_axis, Log.P_subpanels(:, 2), 'FaceColor', 'b', 'FaceAlpha', 0.6, 'DisplayName', 'Left');
area(time_axis, Log.P_subpanels(:, 3), 'FaceColor', 'g', 'FaceAlpha', 0.6, 'DisplayName', 'Up');
area(time_axis, Log.P_subpanels(:, 4), 'FaceColor', [1 0.65 0], 'FaceAlpha', 0.6, 'DisplayName', 'Down');
title('Lateral Panel Power Distribution', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); xlabel('Time (hours)'); ylabel('Sub-Panel Power (W)'); grid on;
saveas(gcf, fullfile(scenario_dir, '05_Energy_Analysis.png'));

%% FIGURE 6: Motor Control & Trajectory
figure('Name', 'Motor Control & Trajectory', 'Position', [350 100 1200 900]);

subplot(3,1,1); hold on;
yyaxis left;
plot(time_axis, Log.I_Pan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Servo Current');
ylabel('Current (A)', 'Color', 'r');
yyaxis right;
plot(time_axis, abs(Log.E_deg_Pan), 'b-', 'LineWidth', 1.5, 'DisplayName', 'Pan Error');
ylabel('Error (deg)', 'Color', 'b');
title('CLOSED-LOOP: Servo Current vs Pan Error', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); grid on; xlabel('Time (hours)');

subplot(3,1,2); hold on;
plot(time_axis, Log.ServoVelPan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Pan Velocity');
plot(time_axis, Log.ServoVelTilt, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Tilt Velocity');
yline(ServoProps.MaxSpeed, 'k--', sprintf('Max: %.0f °/s', ServoProps.MaxSpeed), 'LineWidth', 1.5);
title('Servo Motor Velocities', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Velocity (deg/s)'); grid on;

subplot(3,1,3); hold on;
if ~isempty(FlipLog.times) && length(FlipLog.azimuth_sun) > 1
    plot(FlipLog.times/3600, FlipLog.azimuth_sun, 'y-', 'LineWidth', 1.5, 'DisplayName', 'Sun Azimuth');
    plot(FlipLog.times/3600, FlipLog.elevation_sun, 'c-', 'LineWidth', 1.5, 'DisplayName', 'Sun Elevation');
    plot(FlipLog.times/3600, 90 - FlipLog.target_pan_final, 'r--', 'LineWidth', 1, 'DisplayName', 'Target Pan');
    plot(FlipLog.times/3600, 90 - FlipLog.target_tilt_final, 'b--', 'LineWidth', 1, 'DisplayName', 'Target Tilt');
    legend('Location', 'best');
else
    text(0.5, 0.5, 'Insufficient tracking data', 'HorizontalAlignment', 'center', 'Units', 'normalized');
end
title('Sun Position Trajectory', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Angle (deg)'); xlabel('Time (hours)'); grid on;
saveas(gcf, fullfile(scenario_dir, '06_Motor_Control_Trajectory.png'));

%% FIGURE 7: Energy Balance Analysis
figure('Name', 'Energy Balance', 'Position', [400 150 1200 900]);

solar_power_instant = Log.SolarPower(:);
cumul_energy_available = cumsum(solar_power_instant) * dt_physics / 3600;
efficiency_over_time = (energy_cumulative ./ (cumul_energy_available + 1e-6)) * 100;
energy_balance_vec = cumul_energy_available - energy_cumulative;

subplot(3,1,1);
hold on;
area(time_axis, cumul_energy_available, 'FaceColor', 'y', 'FaceAlpha', 0.4, 'EdgeColor', [1 0.5 0], 'LineWidth', 2);
area(time_axis, energy_cumulative, 'FaceColor', 'r', 'FaceAlpha', 0.4, 'EdgeColor', 'r', 'LineWidth', 2);
legend('Available Solar Energy', 'Used Energy', 'Location', 'best');
title('Cumulative Energy: Available vs Used', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Cumulative Energy (Wh)'); grid on;

subplot(3,1,2);
hold on;
plot(time_axis, solar_power_instant, 'Color', [1 0.5 0], 'LineWidth', 1.5);
plot(time_axis, power_instant, 'r-', 'LineWidth', 1.5);
legend('Solar Power Available', 'Power Used (Motors)', 'Location', 'best');
title('Instantaneous Power: Available vs Used', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Power (W)'); grid on;

subplot(3,1,3);
hold on;
yyaxis left;
plot(time_axis, energy_balance_vec, 'g-', 'LineWidth', 2);
yline(0, 'k--', 'LineWidth', 1);
ylabel('Energy Balance (Wh)'); 
yyaxis right;
plot(time_axis, efficiency_over_time, 'b-', 'LineWidth', 1.5);
yline(100, 'r--', '100%', 'LineWidth', 1);
ylabel('System Efficiency (%)'); 
title('Energy Balance & System Efficiency', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (hours)'); grid on;
saveas(gcf, fullfile(scenario_dir, '07_Energy_Balance.png'));

fprintf('\n✓ All 7 plots generated and saved!\n');
fprintf('✓ Location: %s\n\n', scenario_dir);

% ── Setup for academic tiledlayout figures ──────────────────────────
p_idx = 1:10:num_steps;  % downsample index (every 10th point)

% Reset time axis to seconds for tiledlayout figures
if duration_sec > 1800 && ~TEST_MODE
    time_axis = Log.Time(p_idx) / 60;
    time_label = 'Time [min]';
else
    time_axis = Log.Time(p_idx);
    time_label = 'Time [s]';
end

% Downsample FSM mode to match time_axis length
% FIX: All shadeFSMStates calls must receive downsampled FSM_Mode(p_idx)
%      so its length matches time_axis. Passing full Log.FSM_Mode causes
%      dimension mismatch and crash.
FSM_Mode_ds = Log.FSM_Mode(p_idx);

% Color palette
COL.pan    = [0.13 0.47 0.71];
COL.tilt   = [0.90 0.33 0.23];
COL.error  = [0.95 0.60 0.07];
COL.locked = [0.22 0.56 0.24];
COL.power  = [0.42 0.20 0.58];
COL.right  = [0.13 0.47 0.71];
COL.left   = [0.90 0.33 0.23];
COL.up     = [0.22 0.56 0.24];
COL.down   = [0.84 0.51 0.14];
% ─────────────────────────────────────────────────────────────────────

%% FIGURE 1: Tracking Performance (Academic Tiledlayout Version)
fig1 = figure('Visible', 'off', 'Name', 'Tracking Performance', 'NumberTitle', 'off');
set(fig1, 'Position', [100 100 1200 800]);
tl1 = tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Tile 1: Pan angle with FSM shading
ax1_1 = nexttile;
cla(ax1_1);
shadeFSMStates(ax1_1, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax1_1, 'on');
plot(time_axis, Log.ActualPan(p_idx), 'Color', COL.pan, 'LineWidth', 1.8, 'DisplayName', 'Actual');
plot(time_axis, Log.TargetPan(p_idx), '--', 'Color', COL.pan, 'LineWidth', 1.2, 'DisplayName', 'Target');
ylabel(ax1_1, 'Pan Angle [°]', 'FontSize', 11, 'FontName', 'Arial');
set(ax1_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax1_1, 'Location', 'best', 'FontSize', 10);
grid(ax1_1, 'on'); grid(ax1_1, 'minor');

% Tile 2: Tilt angle
ax1_2 = nexttile;
cla(ax1_2);
shadeFSMStates(ax1_2, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax1_2, 'on');
plot(time_axis, Log.ActualTilt(p_idx), 'Color', COL.tilt, 'LineWidth', 1.8, 'DisplayName', 'Actual');
plot(time_axis, Log.TargetTilt(p_idx), '--', 'Color', COL.tilt, 'LineWidth', 1.2, 'DisplayName', 'Target');
ylabel(ax1_2, 'Tilt Angle [°]', 'FontSize', 11, 'FontName', 'Arial');
set(ax1_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax1_2, 'Location', 'best', 'FontSize', 10);
grid(ax1_2, 'on'); grid(ax1_2, 'minor');

% Tile 3: Incidence angle with lock threshold
ax1_3 = nexttile;
cla(ax1_3);
shadeFSMStates(ax1_3, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax1_3, 'on');
plot(time_axis, Log.Incidence(p_idx), 'Color', COL.error, 'LineWidth', 1.8, 'DisplayName', 'Incidence');
yline(ax1_3, 0.5, '--', 'Color', COL.locked, 'LineWidth', 1.2, 'DisplayName', 'Lock threshold (0.5°)');
fill([time_axis, fliplr(time_axis)], [min(Log.Incidence(p_idx), 0.5)', fliplr(0.5*ones(size(time_axis)))], ...
    COL.locked, 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'HandleVisibility', 'off');
ylabel(ax1_3, 'Incidence Angle [°]', 'FontSize', 11, 'FontName', 'Arial');
set(ax1_3, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax1_3, 'Location', 'best', 'FontSize', 10);
grid(ax1_3, 'on'); grid(ax1_3, 'minor');

% Tile 4: LDR total voltage
ax1_4 = nexttile;
cla(ax1_4);
area(ax1_4, time_axis, Log.V_Total(p_idx), 'FaceColor', [0.7 0.85 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
hold(ax1_4, 'on');
yline(ax1_4, 0.3, '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.2, 'DisplayName', 'Night threshold (0.3V)');
ylabel(ax1_4, 'Σ V_{LDR} [V]', 'FontSize', 11, 'FontName', 'Arial');
xlabel(ax1_4, time_label, 'FontSize', 11, 'FontName', 'Arial');
set(ax1_4, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax1_4, 'Location', 'best', 'FontSize', 10);
grid(ax1_4, 'on'); grid(ax1_4, 'minor');

linkaxes([ax1_1 ax1_2 ax1_3 ax1_4], 'x');
title(tl1, sprintf('Tracking Performance — %s | %s', SCENARIO, upper(CONTROL_MODE)), 'FontSize', 13, 'FontName', 'Arial');

try
    drawnow; % Force MATLAB to finish rendering the UI
    saveas(fig2, fullfile(scenario_dir, '02_LDR_Sensor_Analysis.png'));
    close(fig2);
catch
    fprintf('Warning: Could not save Figure 1\n');
    close(fig1);
end

%% FIGURE 2: LDR Sensor Analysis
fig2 = figure('Visible', 'off', 'Name', 'LDR Sensor Analysis', 'NumberTitle', 'off');
set(fig2, 'Position', [100 100 1200 800]);

tl2 = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Tile 1: LDR voltages with dynamic range band
ax2_1 = nexttile;
hold(ax2_1, 'on');
ldr_max = max(Log.LDR_Voltage, [], 2);
ldr_min = min(Log.LDR_Voltage, [], 2);
fill([time_axis'; flipud(time_axis')], [ldr_max(p_idx); flipud(ldr_min(p_idx))], [0.8 0.8 0.8], 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', 'Dynamic range');
plot(time_axis, Log.LDR_Voltage(p_idx,1), 'Color', COL.right, 'LineWidth', 1.8, 'DisplayName', 'V_R');
plot(time_axis, Log.LDR_Voltage(p_idx,2), 'Color', COL.left, 'LineWidth', 1.8, 'DisplayName', 'V_L');
plot(time_axis, Log.LDR_Voltage(p_idx,3), 'Color', COL.up, 'LineWidth', 1.8, 'DisplayName', 'V_U');
plot(time_axis, Log.LDR_Voltage(p_idx,4), 'Color', COL.down, 'LineWidth', 1.8, 'DisplayName', 'V_D');
ylabel(ax2_1, 'Voltage [V]', 'FontSize', 11, 'FontName', 'Arial');
set(ax2_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax2_1, 'Location', 'best', 'FontSize', 10);
grid(ax2_1, 'on'); grid(ax2_1, 'minor');

% Tile 2: Normalized error signals
ax2_2 = nexttile;
hold(ax2_2, 'on');
plot(time_axis, Log.E_norm_Pan(p_idx), 'Color', COL.pan, 'LineWidth', 1.8, 'DisplayName', 'E_{norm,Pan}');
plot(time_axis, Log.E_norm_Tilt(p_idx), 'Color', COL.tilt, 'LineWidth', 1.8, 'DisplayName', 'E_{norm,Tilt}');
yline(ax2_2, 0, 'k-', 'LineWidth', 0.8);
yline(ax2_2, 1, 'k--', 'LineWidth', 1.0);
yline(ax2_2, -1, 'k--', 'LineWidth', 1.0);
ylabel(ax2_2, 'Normalized Differential [-]', 'FontSize', 11, 'FontName', 'Arial');
set(ax2_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax2_2, 'Location', 'best', 'FontSize', 10);
grid(ax2_2, 'on'); grid(ax2_2, 'minor');
subtitle(ax2_2, 'Differential signal driving the controller: zero = sun centered on that axis', 'FontSize', 10);

% Tile 3: Phase portrait
ax2_3 = nexttile;
scatter(ax2_3, Log.E_deg_Pan(p_idx), Log.E_deg_Tilt(p_idx), 15, Log.Time(p_idx), 'filled', 'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.7);
colormap(ax2_3, 'cool');
cbar = colorbar(ax2_3);
cbar.Label.String = 'Time [s]';
cbar.Label.FontSize = 10;
hold(ax2_3, 'on');
xline(ax2_3, 0, 'k-', 'LineWidth', 0.8);
yline(ax2_3, 0, 'k-', 'LineWidth', 0.8);
% Add lock threshold circle
circle_theta = linspace(0, 2*pi, 100);
circle_r = 0.5;
plot(ax2_3, circle_r * cos(circle_theta), circle_r * sin(circle_theta), 'g--', 'LineWidth', 1.2);
xlabel(ax2_3, 'Pan Error [°]', 'FontSize', 11, 'FontName', 'Arial');
ylabel(ax2_3, 'Tilt Error [°]', 'FontSize', 11, 'FontName', 'Arial');
set(ax2_3, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
grid(ax2_3, 'on'); grid(ax2_3, 'minor');
axis(ax2_3, 'equal');
title(ax2_3, 'Error Phase Portrait', 'FontSize', 12, 'FontName', 'Arial');
subtitle(ax2_3, 'Convergence trajectory in 2D error space — ideal endpoint: origin', 'FontSize', 10);

xlabel(tl2, time_label, 'FontSize', 11, 'FontName', 'Arial');
title(tl2, 'LDR Sensor Analysis', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig2, fullfile(scenario_dir, '02_LDR_Sensor_Analysis.png'), 'Resolution', 200);
    close(fig2);
catch
    fprintf('Warning: Could not save Figure 2\n');
    close(fig2);
end

%% FIGURE 3: Controller Internals
fig3 = figure('Visible', 'off', 'Name', 'Controller Internals', 'NumberTitle', 'off');
set(fig3, 'Position', [100 100 1200 800]);

tl3 = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

if strcmp(CONTROL_MODE, 'pid')
    % PID Control Analysis

    % Tile 1: Pan PID terms
    ax3_1 = nexttile;
    hold(ax3_1, 'on');
    plot(time_axis, Log.PID_P_Pan(p_idx), 'Color', [0.2 0.6 0.2], 'LineWidth', 1.8, 'DisplayName', 'P_{Pan}');
    plot(time_axis, Log.PID_I_Pan(p_idx), 'Color', [0.0 0.4 0.8], 'LineWidth', 1.8, 'DisplayName', 'I_{Pan}');
    plot(time_axis, Log.PID_D_Pan(p_idx), 'Color', COL.left, 'LineWidth', 1.8, 'DisplayName', 'D_{Pan}');
    yline(ax3_1, 0, 'k-', 'LineWidth', 0.8);
    shadeFSMStates(ax3_1, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
    ylabel(ax3_1, 'PID Terms — Pan [°/s]', 'FontSize', 11, 'FontName', 'Arial');
    set(ax3_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
    legend(ax3_1, 'Location', 'best', 'FontSize', 10);
    subtitle(ax3_1, 'Flat regions = HOLD state (motor de-energised by design)', 'FontSize', 10);
    grid(ax3_1, 'on'); grid(ax3_1, 'minor');

    ax3_2 = nexttile;
    hold(ax3_2, 'on');
    plot(time_axis, Log.PID_P_Tilt(p_idx), 'Color', [0.2 0.6 0.2], 'LineWidth', 1.8, 'DisplayName', 'P_{Tilt}');
    plot(time_axis, Log.PID_I_Tilt(p_idx), 'Color', [0.0 0.4 0.8], 'LineWidth', 1.8, 'DisplayName', 'I_{Tilt}');
    plot(time_axis, Log.PID_D_Tilt(p_idx), 'Color', COL.left, 'LineWidth', 1.8, 'DisplayName', 'D_{Tilt}');
    yline(ax3_2, 0, 'k-', 'LineWidth', 0.8);
    shadeFSMStates(ax3_2, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
    ylabel(ax3_2, 'PID Terms — Tilt [°/s]', 'FontSize', 11, 'FontName', 'Arial');
    set(ax3_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
    legend(ax3_2, 'Location', 'best', 'FontSize', 10);
    subtitle(ax3_2, 'Flat regions = HOLD state (motor de-energised by design)', 'FontSize', 10);
    grid(ax3_2, 'on'); grid(ax3_2, 'minor');

    ax3_3 = nexttile;
    hold(ax3_3, 'on');
    plot(time_axis, Log.ServoVelPan(p_idx), 'Color', COL.pan, 'LineWidth', 1.8, 'DisplayName', 'Vel_{Pan}');
    plot(time_axis, Log.ServoVelTilt(p_idx), 'Color', COL.tilt, 'LineWidth', 1.8, 'DisplayName', 'Vel_{Tilt}');
    vel_limit = 15;  % deg/s
    yline(ax3_3, vel_limit, '--', 'Color', [0.8 0.4 0.4], 'LineWidth', 1.2);
    yline(ax3_3, -vel_limit, '--', 'Color', [0.8 0.4 0.4], 'LineWidth', 1.2);
    ylabel(ax3_3, 'Commanded Velocity [°/s]', 'FontSize', 11, 'FontName', 'Arial');
    set(ax3_3, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
    legend(ax3_3, 'Location', 'best', 'FontSize', 10);
    grid(ax3_3, 'on'); grid(ax3_3, 'minor');
else
    % FLC Analysis with Control Surface

    % Tile 1: FLC Pan velocity
    ax3_1 = nexttile;
    cla(ax3_1);
    shadeFSMStates(ax3_1, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
    hold(ax3_1, 'on');
    plot(time_axis, Log.FLC_Vel_Pan(p_idx), 'Color', COL.pan, 'LineWidth', 1.8);
    ylabel(ax3_1, 'FLC Output — Pan [°/s]', 'FontSize', 11, 'FontName', 'Arial');
    set(ax3_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
    grid(ax3_1, 'on'); grid(ax3_1, 'minor');

    % Tile 2: FLC Tilt velocity
    ax3_2 = nexttile;
    cla(ax3_2);
    shadeFSMStates(ax3_2, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
    hold(ax3_2, 'on');
    plot(time_axis, Log.FLC_Vel_Tilt(p_idx), 'Color', COL.tilt, 'LineWidth', 1.8);
    ylabel(ax3_2, 'FLC Output — Tilt [°/s]', 'FontSize', 11, 'FontName', 'Arial');
    set(ax3_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
    grid(ax3_2, 'on'); grid(ax3_2, 'minor');

    % Tile 3: FLC Control Surface (2D heatmap)
    ax3_3 = nexttile;
    % Generate meshgrid for control surface visualization
    e_grid = linspace(-2, 2, 51);    % error range [deg]
    de_grid = linspace(-90, 90, 51); % error rate range [deg/s]
    V_mesh = zeros(length(de_grid), length(e_grid));
    % FIX: Correct FuzzyLogicController call with 3 args and 4 outputs
    %      Old code used 1-arg call and wrong field name 'vel_pan' (should be 'v_pan')
    tmp_cs = struct('I_pan', 0, 'I_tilt', 0);
    for ee = 1:length(e_grid)
        for dd = 1:length(de_grid)
            error_input = struct('e_pan', e_grid(ee), 'e_tilt', 0, ...
                'de_pan', de_grid(dd), 'de_tilt', 0, 'mode', 'TRACKING');
            [flc_out, ~, ~, ~] = FuzzyLogicController(error_input, tmp_cs, dt_control);
            V_mesh(dd, ee) = flc_out.v_pan;  % FIX: correct field name v_pan
        end
    end
    % Create red-blue diverging colormap
    n_cols = 128;
    redblue_map = [linspace(0, 1, n_cols)', linspace(0, 1, n_cols)', ones(n_cols, 1); ...
                   ones(n_cols, 1), linspace(1, 0, n_cols)', linspace(1, 0, n_cols)'];
    % Plot as 2D heatmap
    imagesc(ax3_3, e_grid, de_grid, V_mesh); axis(ax3_3, 'ij');
    colormap(ax3_3, redblue_map);
    max_abs = max(abs(V_mesh(:)));
    if max_abs == 0, max_abs = 1; end
    clim(ax3_3, [-max_abs max_abs]);
    cbar3 = colorbar(ax3_3);
    cbar3.Label.String = 'Velocity [°/s]';
    xlabel(ax3_3, 'Pan Error [°]', 'FontSize', 11, 'FontName', 'Arial');
    ylabel(ax3_3, 'Pan Error Rate [°/s]', 'FontSize', 11, 'FontName', 'Arial');
    set(ax3_3, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on');
    title(ax3_3, 'FLC Control Surface (Pan axis)', 'FontSize', 12, 'FontName', 'Arial');
end

xlabel(tl3, time_label, 'FontSize', 11, 'FontName', 'Arial');
title(tl3, 'Controller Internals', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig3, fullfile(scenario_dir, '03_Controller_Internals.png'), 'Resolution', 200);
    close(fig3);
catch
    fprintf('Warning: Could not save Figure 3\n');
    close(fig3);
end

%% FIGURE 4: FSM State Machine Analysis
fig4 = figure('Visible', 'off', 'Name', 'FSM State Machine Analysis', 'NumberTitle', 'off');
set(fig4, 'Position', [100 100 1200 800]);

tl4 = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Convert FSM mode strings to numeric
fsm_numeric = zeros(length(Log.FSM_Mode), 1);
for ii = 1:length(Log.FSM_Mode)
    mode_str = char(Log.FSM_Mode{ii});
    switch mode_str
        case 'IDLE',     fsm_numeric(ii) = 0;
        case 'SEARCH',   fsm_numeric(ii) = 1;
        case 'HOLD',     fsm_numeric(ii) = 2;
        case 'TRACKING', fsm_numeric(ii) = 3;
        otherwise,       fsm_numeric(ii) = 0;
    end
end

% Tile 1: FSM state time series
ax4_1 = nexttile;
stairs(ax4_1, time_axis, fsm_numeric(p_idx), 'LineWidth', 2.2, 'Color', [0.1 0.1 0.1]);
shadeFSMStates(ax4_1, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
set(ax4_1, 'YTick', [0 1 2 3], 'YTickLabel', {'IDLE', 'SEARCH', 'HOLD', 'TRACKING'}, 'FontSize', 11, 'FontName', 'Arial');
ylabel(ax4_1, 'FSM State', 'FontSize', 11, 'FontName', 'Arial');
set(ax4_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
grid(ax4_1, 'on'); grid(ax4_1, 'minor');
subtitle(ax4_1, 'Discrete state of the supervisor — determines control law active at each moment', 'FontSize', 10);

% Tile 2: Rolling state occupancy
ax4_2 = nexttile;
window_size = 50;
state_rolling = zeros(length(Log.FSM_Mode), 4);
for ii = 1:length(Log.FSM_Mode)
    start_idx = max(1, ii - window_size);
    end_idx = min(length(Log.FSM_Mode), ii + window_size);
    window = fsm_numeric(start_idx:end_idx);
    for ss = 0:3
        state_rolling(ii, ss+1) = sum(window == ss) / length(window);
    end
end
area(ax4_2, time_axis, state_rolling(p_idx, :), 'FaceAlpha', 0.7);
colormap_states = [0.9 0.9 0.9; 0.95 0.95 0.80; 0.85 0.85 0.94; 0.85 0.94 0.85];
set(ax4_2, 'ColorOrder', colormap_states);
legend(ax4_2, {'IDLE', 'SEARCH', 'HOLD', 'TRACKING'}, 'Location', 'best', 'FontSize', 10);
ylabel(ax4_2, 'State Proportion [-]', 'FontSize', 11, 'FontName', 'Arial');
set(ax4_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
grid(ax4_2, 'on'); grid(ax4_2, 'minor');
subtitle(ax4_2, 'Sliding window state occupancy — shows behavioral evolution over time', 'FontSize', 10);

% Tile 3: State occupancy summary
ax4_3 = nexttile;
state_times = zeros(4, 1);
for ss = 0:3
    state_times(ss+1) = sum(fsm_numeric == ss) * dt_physics;
end
[sorted_times, sorted_idx] = sort(state_times, 'descend');
state_names_sorted = {'IDLE', 'SEARCH', 'HOLD', 'TRACKING'};
state_names_sorted = state_names_sorted(sorted_idx);
colors_sorted = colormap_states(sorted_idx, :);

b4 = barh(ax4_3, state_names_sorted, sorted_times, 'FaceColor', 'flat', 'EdgeColor', 'none');
for ii = 1:length(b4.CData)
    b4.CData(ii, :) = colors_sorted(ii, :);
end

% Add value labels
hold(ax4_3, 'on');
for ii = 1:length(sorted_times)
    text(ax4_3, sorted_times(ii) + 0.1, ii, sprintf('%.1f s (%.1f%%)', sorted_times(ii), 100*sorted_times(ii)/sum(state_times)), ...
        'FontSize', 10, 'FontName', 'Arial', 'VerticalAlignment', 'middle');
end

xlabel(ax4_3, 'Time [s]', 'FontSize', 11, 'FontName', 'Arial');
set(ax4_3, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on');
grid(ax4_3, 'on');
title(ax4_3, 'State Occupancy Summary', 'FontSize', 12, 'FontName', 'Arial');
subtitle(ax4_3, 'Key result: high TRACKING + HOLD percentage indicates effective sun acquisition', 'FontSize', 10);

xlabel(tl4, time_label, 'FontSize', 11, 'FontName', 'Arial');
title(tl4, 'FSM State Machine Analysis', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig4, fullfile(scenario_dir, '04_FSM_Analysis.png'), 'Resolution', 200);
    close(fig4);
catch
    fprintf('Warning: Could not save Figure 4\n');
    close(fig4);
end

%% FIGURE 5: Sub-Panel Power Distribution
fig5 = figure('Visible', 'off', 'Name', 'Sub-Panel Power Distribution', 'NumberTitle', 'off');
set(fig5, 'Position', [100 100 1200 800]);

tl5 = tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Tile 1: Individual panel power
ax5_1 = nexttile;
hold(ax5_1, 'on');
plot(time_axis, Log.P_subpanels(p_idx, 1), 'Color', COL.right, 'LineWidth', 1.8, 'DisplayName', 'Right (+X)');
plot(time_axis, Log.P_subpanels(p_idx, 2), 'Color', COL.left, 'LineWidth', 1.8, 'DisplayName', 'Left (-X)');
plot(time_axis, Log.P_subpanels(p_idx, 3), 'Color', COL.up, 'LineWidth', 1.8, 'DisplayName', 'Up (+Y)');
plot(time_axis, Log.P_subpanels(p_idx, 4), 'Color', COL.down, 'LineWidth', 1.8, 'DisplayName', 'Down (-Y)');
shadeFSMStates(ax5_1, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
ylabel(ax5_1, 'Power per Panel [W]', 'FontSize', 11, 'FontName', 'Arial');
set(ax5_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax5_1, 'Location', 'best', 'FontSize', 10);
grid(ax5_1, 'on'); grid(ax5_1, 'minor');
subtitle(ax5_1, 'Each lateral panel only receives light when the sun is roughly in that direction — power shifts as tracker rotates', 'FontSize', 9);

% Tile 2: Total sub-panel vs reference
ax5_2 = nexttile;
hold(ax5_2, 'on');
area(ax5_2, time_axis, Log.P_subpanel_total(p_idx), 'FaceColor', COL.power, 'FaceAlpha', 0.4, 'EdgeColor', 'none');
if ~TEST_MODE && sum(Log.P_tracker) > 0
    plot(ax5_2, time_axis, Log.P_tracker(p_idx), '--', 'Color', 'k', 'LineWidth', 1.5, 'DisplayName', 'Main Tracking Panel');
else
    irradiance_ref = Log.Irradiance(p_idx) * SubPanelProps.Area * SubPanelProps.Efficiency;
    plot(ax5_2, time_axis, irradiance_ref, '--', 'Color', 'k', 'LineWidth', 1.5, 'DisplayName', 'Reference (G × A × η)');
end
ylabel(ax5_2, 'Power [W]', 'FontSize', 11, 'FontName', 'Arial');
set(ax5_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax5_2, 'Location', 'best', 'FontSize', 10);
grid(ax5_2, 'on'); grid(ax5_2, 'minor');
subtitle(ax5_2, 'Sub-panel total is always less than main panel — main panel faces sun directly', 'FontSize', 9);

% Tile 3: Stacked area of panel composition
ax5_3 = nexttile;
area(ax5_3, time_axis, Log.P_subpanels(p_idx, :), 'FaceAlpha', 0.7);
colormap_panels = [COL.right; COL.left; COL.up; COL.down];
set(ax5_3, 'ColorOrder', colormap_panels);
legend(ax5_3, {'Right', 'Left', 'Up', 'Down'}, 'Location', 'best', 'FontSize', 10);
ylabel(ax5_3, 'Stacked Power [W]', 'FontSize', 11, 'FontName', 'Arial');
set(ax5_3, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
grid(ax5_3, 'on'); grid(ax5_3, 'minor');
subtitle(ax5_3, 'Composition of total sub-panel harvest — which face dominates changes with gimbal orientation', 'FontSize', 9);

% Tile 4: Energy summary bar chart
ax5_4 = nexttile;
energy_per_face = sum(Log.P_subpanels) * dt_physics / 3600;  % Wh

b5 = barh(ax5_4, {'Right', 'Left', 'Up', 'Down'}, energy_per_face, 'FaceColor', 'flat', 'EdgeColor', 'none');
b5.CData = [COL.right; COL.left; COL.up; COL.down];
hold(ax5_4, 'on');
for ii = 1:4
    text(ax5_4, energy_per_face(ii) + 0.001, ii, sprintf('%.4f Wh', energy_per_face(ii)), ...
        'HorizontalAlignment', 'left', 'FontSize', 9, 'FontName', 'Arial', 'VerticalAlignment', 'middle');
end
xlabel(ax5_4, 'Total Energy [Wh]', 'FontSize', 11, 'FontName', 'Arial');
set(ax5_4, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on');
grid(ax5_4, 'on');
title(ax5_4, 'Cumulative Energy per Face', 'FontSize', 12, 'FontName', 'Arial');

xlabel(tl5, time_label, 'FontSize', 11, 'FontName', 'Arial');
title(tl5, 'Sub-Panel Power Distribution', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig5, fullfile(scenario_dir, '05_SubPanel_Power.png'), 'Resolution', 200);
    close(fig5);
catch
    fprintf('Warning: Could not save Figure 5\n');
    close(fig5);
end

%% FIGURE 5b: Sub-Panel Energy Summary (Pie + Bar)
% FIX: Added 'Visible','off' to prevent unwanted visible window during batch save
fig5b = figure('Visible', 'off', 'Name', 'Sub-Panel Energy Summary', 'NumberTitle', 'off');
set(fig5b, 'Position', [100 100 900 400]);
tl5b = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% Calculate energy per face
energy_per_face = sum(Log.P_subpanels) * dt_physics / 3600;  % Wh

% Tile 1: Pie chart
ax5b_1 = nexttile;
labels_pie = {sprintf('Right\n%.4f Wh', energy_per_face(1)), ...
              sprintf('Left\n%.4f Wh', energy_per_face(2)), ...
              sprintf('Up\n%.4f Wh', energy_per_face(3)), ...
              sprintf('Down\n%.4f Wh', energy_per_face(4))};
pie(ax5b_1, energy_per_face + 1e-10, labels_pie);  % +1e-10 avoids zero-slice crash
colormap(ax5b_1, [COL.right; COL.left; COL.up; COL.down]);
title(ax5b_1, 'Energy Share per Face', 'FontSize', 12, 'FontName', 'Arial');

% Tile 2: Bar chart
ax5b_2 = nexttile;
b5b = bar(ax5b_2, 1:4, energy_per_face, 'FaceColor', 'flat', 'EdgeColor', 'none');
b5b.CData = [COL.right; COL.left; COL.up; COL.down];
set(ax5b_2, 'XTick', 1:4, 'XTickLabel', {'Right','Left','Up','Down'});
ylabel(ax5b_2, 'Energy [Wh]', 'FontSize', 11, 'FontName', 'Arial');
hold(ax5b_2, 'on');
for ii = 1:4
    text(ax5b_2, ii, energy_per_face(ii)*1.05 + 1e-6, ...
        sprintf('%.4f', energy_per_face(ii)), ...
        'HorizontalAlignment', 'center', 'FontSize', 10, 'FontName', 'Arial');
end
set(ax5b_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'YGrid', 'on');
title(ax5b_2, 'Total Energy per Face [Wh]', 'FontSize', 12, 'FontName', 'Arial');

title(tl5b, 'Sub-Panel Cumulative Energy Summary', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig5b, fullfile(scenario_dir, '05b_SubPanel_Energy_Summary.png'), 'Resolution', 200);
    close(fig5b);
catch
    fprintf('Warning: Could not save Figure 5b\n');
    close(fig5b);
end

%% FIGURE 6: Energy & Power Budget
fig6 = figure('Visible', 'off', 'Name', 'Energy & Power Budget', 'NumberTitle', 'off');
set(fig6, 'Position', [100 100 1200 800]);

tl6 = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Tile 1: Motor power vs irradiance
ax6_1 = nexttile;
yyaxis(ax6_1, 'left')
hold(ax6_1, 'on');
plot(time_axis, Log.Power_Pan(p_idx), 'Color', COL.pan, 'LineWidth', 1.8, 'DisplayName', 'Pan Motor');
plot(time_axis, Log.Power_Tilt(p_idx), 'Color', COL.tilt, 'LineWidth', 1.8, 'DisplayName', 'Tilt Motor');
plot(time_axis, Log.Power_Total(p_idx), 'k', 'LineWidth', 2.0, 'DisplayName', 'Total Motor');
ylabel(ax6_1, 'Motor Power [W]', 'FontSize', 11, 'FontName', 'Arial', 'Color', 'k');

yyaxis(ax6_1, 'right')
plot(time_axis, Log.Irradiance(p_idx), '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 1.2, 'DisplayName', 'Irradiance');
ylabel(ax6_1, 'Irradiance [W/m²]', 'FontSize', 11, 'FontName', 'Arial', 'Color', [0.7 0.7 0.7]);
set(ax6_1, 'YColor', [0.7 0.7 0.7]);

set(ax6_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
grid(ax6_1, 'on'); grid(ax6_1, 'minor');
legend(ax6_1, 'Location', 'best', 'FontSize', 10);
subtitle(ax6_1, 'Motor power consumption vs available solar resource', 'FontSize', 10);

% Tile 2: Cumulative energy
ax6_2 = nexttile;
hold(ax6_2, 'on');
plot(time_axis, cumsum(Log.Power_Total(p_idx)) * dt_physics / 3600, 'k', 'LineWidth', 1.8, 'DisplayName', 'Motor Energy');
cumsum_subpanel = cumsum(Log.P_subpanel_total(p_idx)) * dt_physics / 3600;
plot(time_axis, cumsum_subpanel, '--', 'Color', COL.power, 'LineWidth', 1.5, 'DisplayName', 'Sub-panel Energy');

if ~TEST_MODE
    plot(time_axis, cumsum(Log.P_tracker(p_idx)) * dt_physics / 3600, 'Color', COL.power, 'LineWidth', 1.5, 'DisplayName', 'Tracker Gross');
    plot(time_axis, cumsum(Log.P_fixed(p_idx)) * dt_physics / 3600, '--', 'Color', [1.0 0.65 0.0], 'LineWidth', 1.5, 'DisplayName', 'Fixed Panel');
end

ylabel(ax6_2, 'Cumulative Energy [Wh]', 'FontSize', 11, 'FontName', 'Arial');
set(ax6_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax6_2, 'Location', 'best', 'FontSize', 10);
grid(ax6_2, 'on'); grid(ax6_2, 'minor');

% Tile 3: Summary statistics
ax6_3 = nexttile;
axis(ax6_3, 'off');
metrics_text = sprintf(['Test Scenario Metrics\n' ...
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
    'Scenario:\t\t%s\n' ...
    'Duration:\t\t%.1f s\n' ...
    'Mean Incidence Error:\t%.3f °\n' ...
    'Lock Time:\t\t%.1f s (%.1f%%)\n' ...
    'Max Pan Velocity:\t%.1f °/s\n' ...
    'Max Tilt Velocity:\t%.1f °/s\n' ...
    'Total Motor Energy:\t%.4f Wh\n' ...
    'Sub-panel Energy:\t%.4f Wh\n'], ...
    SCENARIO, duration_sec, ...
    mean(Log.Incidence(Log.Incidence > 0)), ...
    sum(Log.IsLocked) * dt_physics, 100 * sum(Log.IsLocked) / length(Log.IsLocked), ...
    max(abs(Log.Servo_Velocity_Pan)), max(abs(Log.Servo_Velocity_Tilt)), ...
    sum(Log.Power_Total) * dt_physics / 3600, sum(Log.P_subpanel_total) * dt_physics / 3600);

text(ax6_3, 0.1, 0.9, metrics_text, 'Units', 'normalized', 'FontSize', 11, 'FontName', 'Courier', ...
    'FontWeight', 'bold', 'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', 'BackgroundColor', [0.95 0.95 0.95]);
title(ax6_3, 'Test Scenario Summary', 'FontSize', 12, 'FontName', 'Arial');

xlabel(tl6, time_label, 'FontSize', 11, 'FontName', 'Arial');
title(tl6, 'Energy & Power Budget', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig6, fullfile(scenario_dir, '06_Energy_Budget.png'), 'Resolution', 200);
    close(fig6);
catch
    fprintf('Warning: Could not save Figure 6\n');
    close(fig6);
end

%% FIGURE 7: Gimbal Trajectory & Servo Performance
fig7 = figure('Visible', 'off', 'Name', 'Gimbal Trajectory & Servo Performance', 'NumberTitle', 'off');
set(fig7, 'Position', [100 100 1200 800]);

tl7 = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% Set practical velocity limit for plotting (not physical servo limit)
vel_limit_plot = 15.0;  % practical tracking velocity limit [deg/s]
vel_plot_max = max(max(abs(Log.Servo_Velocity_Pan)), max(abs(Log.Servo_Velocity_Tilt)));
vel_axis_lim = max(30, vel_plot_max * 1.2);  % show at least ±30

% Top-left: Pan servo velocity
ax7_1 = nexttile;
cla(ax7_1);
shadeFSMStates(ax7_1, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax7_1, 'on');
plot(time_axis, Log.Servo_Velocity_Pan(p_idx), 'Color', COL.pan, 'LineWidth', 1.8, 'DisplayName', 'Pan Velocity');
yline(ax7_1,  vel_limit_plot, '--', 'Color', [0.8 0.4 0.4], 'LineWidth', 1.2, 'DisplayName', 'Practical limit (15 °/s)', 'HandleVisibility', 'on');
yline(ax7_1, -vel_limit_plot, '--', 'Color', [0.8 0.4 0.4], 'LineWidth', 1.2, 'HandleVisibility', 'off');
ylabel(ax7_1, 'Pan Velocity [°/s]', 'FontSize', 11, 'FontName', 'Arial');
ylim(ax7_1, [-vel_axis_lim vel_axis_lim]);
set(ax7_1, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax7_1, 'Location', 'best', 'FontSize', 10);
grid(ax7_1, 'on'); grid(ax7_1, 'minor');

% Top-right: Tilt servo velocity
ax7_2 = nexttile;
cla(ax7_2);
shadeFSMStates(ax7_2, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax7_2, 'on');
plot(time_axis, Log.Servo_Velocity_Tilt(p_idx), 'Color', COL.tilt, 'LineWidth', 1.8, 'DisplayName', 'Tilt Velocity');
yline(ax7_2,  vel_limit_plot, '--', 'Color', [0.8 0.4 0.4], 'LineWidth', 1.2, 'DisplayName', 'Practical limit (15 °/s)', 'HandleVisibility', 'on');
yline(ax7_2, -vel_limit_plot, '--', 'Color', [0.8 0.4 0.4], 'LineWidth', 1.2, 'HandleVisibility', 'off');
ylabel(ax7_2, 'Tilt Velocity [°/s]', 'FontSize', 11, 'FontName', 'Arial');
ylim(ax7_2, [-vel_axis_lim vel_axis_lim]);
set(ax7_2, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax7_2, 'Location', 'best', 'FontSize', 10);
grid(ax7_2, 'on'); grid(ax7_2, 'minor');

% Bottom: Gimbal trajectory (spans 2 columns)
ax7_3 = nexttile([1 2]);
cla(ax7_3);
scatter(ax7_3, Log.ActualPan(p_idx), Log.ActualTilt(p_idx), 15, Log.Time(p_idx), 'filled', 'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.6);
colormap(ax7_3, 'parula');
cbar7 = colorbar(ax7_3);
cbar7.Label.String = 'Time [s]';
cbar7.Label.FontSize = 10;

hold(ax7_3, 'on');
% Start marker
plot(ax7_3, Log.ActualPan(1), Log.ActualTilt(1), 'o', 'Color', COL.locked, 'MarkerSize', 12, 'LineWidth', 2, 'DisplayName', 'Start');
% End marker
plot(ax7_3, Log.ActualPan(end), Log.ActualTilt(end), 's', 'Color', [0.8 0.2 0.2], 'MarkerSize', 12, 'LineWidth', 2, 'DisplayName', 'End');
% Target trajectory
plot(ax7_3, Log.TargetPan(p_idx), Log.TargetTilt(p_idx), '--', 'Color', [0.6 0.6 0.6], 'LineWidth', 1.2, 'DisplayName', 'Target Path');

xlabel(ax7_3, 'Pan Angle [°]', 'FontSize', 11, 'FontName', 'Arial');
ylabel(ax7_3, 'Tilt Angle [°]', 'FontSize', 11, 'FontName', 'Arial');
set(ax7_3, 'FontSize', 11, 'FontName', 'Arial', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on');
legend(ax7_3, 'Location', 'best', 'FontSize', 10);
grid(ax7_3, 'on'); grid(ax7_3, 'minor');
axis(ax7_3, 'equal');
title(ax7_3, 'Gimbal Trajectory in Pan-Tilt Space', 'FontSize', 12, 'FontName', 'Arial');
subtitle(ax7_3, 'Physical path traced by the gimbal — colored by time, gray dashed = target path', 'FontSize', 10);

xlabel(tl7, time_label, 'FontSize', 11, 'FontName', 'Arial');
title(tl7, 'Gimbal Trajectory & Servo Performance', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig7, fullfile(scenario_dir, '07_Gimbal_Trajectory.png'), 'Resolution', 200);
    close(fig7);
catch
    fprintf('Warning: Could not save Figure 7\n');
    close(fig7);
end

fprintf('\n✓ All tiledlayout figures (01-07) generated and saved!\n');
fprintf('✓ Location: %s\n\n', scenario_dir);

%% ════════════════════════════════════════════════════════════════════════════
%% FIGURE 8: Tracking Error & Energy Balance Analysis
%% ════════════════════════════════════════════════════════════════════════════

fig8 = figure('Visible', 'off', 'Name', 'Tracking Error & Energy', 'NumberTitle', 'off');
set(fig8, 'Position', [100 100 1200 900]);
tl8 = tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Compute tracking errors
err_pan  = Log.TargetPan  - Log.ActualPan;
err_tilt = Log.TargetTilt - Log.ActualTilt;
err_combined = sqrt(err_pan.^2 + err_tilt.^2);

% Tile 1: Pan Tracking Error
ax8_1 = nexttile(tl8, 1);
cla(ax8_1);
shadeFSMStates(ax8_1, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax8_1, 'on');
plot(ax8_1, time_axis, err_pan(p_idx), 'Color', COL.pan, 'LineWidth', 1.5, 'DisplayName', 'Pan Error');
yline(ax8_1, 2, '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'DisplayName', '±2° Guidance');
yline(ax8_1, -2, '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'HandleVisibility', 'off');
grid(ax8_1, 'on');  % FIX: removed invalid 'alpha' parameter
ylabel(ax8_1, 'Error (°)', 'FontSize', 11, 'FontName', 'Arial');
rms_pan = sqrt(mean(err_pan.^2));
max_pan = max(abs(err_pan));
final_pan = err_pan(end);
subtitle(ax8_1, sprintf('RMS: %.3f° | Max: %.3f° | Final: %.3f°', rms_pan, max_pan, final_pan), ...
         'FontSize', 10, 'FontName', 'Arial');
legend(ax8_1, 'Location', 'best', 'FontSize', 10, 'FontName', 'Arial');

% Tile 2: Tilt Tracking Error
ax8_2 = nexttile(tl8, 2);
cla(ax8_2);
shadeFSMStates(ax8_2, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax8_2, 'on');
plot(ax8_2, time_axis, err_tilt(p_idx), 'Color', COL.tilt, 'LineWidth', 1.5, 'DisplayName', 'Tilt Error');
yline(ax8_2, 2, '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'DisplayName', '±2° Guidance');
yline(ax8_2, -2, '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'HandleVisibility', 'off');
grid(ax8_2, 'on');  % FIX: removed invalid 'alpha' parameter
ylabel(ax8_2, 'Error (°)', 'FontSize', 11, 'FontName', 'Arial');
rms_tilt = sqrt(mean(err_tilt.^2));
max_tilt = max(abs(err_tilt));
final_tilt = err_tilt(end);
subtitle(ax8_2, sprintf('RMS: %.3f° | Max: %.3f° | Final: %.3f°', rms_tilt, max_tilt, final_tilt), ...
         'FontSize', 10, 'FontName', 'Arial');
legend(ax8_2, 'Location', 'best', 'FontSize', 10, 'FontName', 'Arial');

% Tile 3: Combined Error Magnitude + Incidence Angle
ax8_3 = nexttile(tl8, 3);
cla(ax8_3);
shadeFSMStates(ax8_3, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax8_3, 'on');
yyaxis(ax8_3, 'left');
plot(ax8_3, time_axis, err_combined(p_idx), 'Color', COL.error, 'LineWidth', 1.5, 'DisplayName', 'Combined |Error|');
ylabel(ax8_3, 'Combined Error (°)', 'FontSize', 11, 'FontName', 'Arial');
ax8_3.YAxis(1).Color = COL.error;
yyaxis(ax8_3, 'right');
plot(ax8_3, time_axis, Log.Incidence(p_idx), 'Color', COL.locked, 'LineWidth', 1.5, 'DisplayName', 'Incidence Angle');
yline(ax8_3, 0.5, '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'DisplayName', '0.5° Lock Threshold');
ylabel(ax8_3, 'Incidence (°)', 'FontSize', 11, 'FontName', 'Arial');
ax8_3.YAxis(2).Color = COL.locked;
grid(ax8_3, 'on');  % FIX: removed invalid 'alpha' parameter
legend(ax8_3, 'Location', 'best', 'FontSize', 10, 'FontName', 'Arial');

% Tile 4: Cumulative Energy Budget (Motors Spent vs Sub-panels Harvested)
ax8_4 = nexttile(tl8, 4);
cla(ax8_4);
shadeFSMStates(ax8_4, time_axis, FSM_Mode_ds);  % FIX: downsampled FSM_Mode_ds
hold(ax8_4, 'on');

cumsum_motors = cumsum(Log.Power_Total(p_idx)) * dt_physics / 3600;  % Wh
cumsum_panels = cumsum(Log.P_subpanel_total(p_idx)) * dt_physics / 3600;

area(ax8_4, time_axis, cumsum_motors, 'FaceColor', COL.power, 'FaceAlpha', 0.6, ...
     'EdgeColor', 'none', 'DisplayName', 'Motors Spent (Cumulative)');
plot(ax8_4, time_axis, cumsum_panels, 'Color', COL.right, 'LineWidth', 2, ...
     'DisplayName', 'Sub-panels Harvested (Cumulative)');
grid(ax8_4, 'on');  % FIX: removed invalid 'alpha' parameter
ylabel(ax8_4, 'Energy (Wh)', 'FontSize', 11, 'FontName', 'Arial');
energy_balance = cumsum_panels(end) - cumsum_motors(end);
subtitle(ax8_4, sprintf('Final Balance: %.4f Wh (Panels: %.4f | Motors: %.4f)', ...
         energy_balance, cumsum_panels(end), cumsum_motors(end)), ...
         'FontSize', 10, 'FontName', 'Arial');
legend(ax8_4, 'Location', 'best', 'FontSize', 10, 'FontName', 'Arial');

% Link all tiles to same x-axis
linkaxes([ax8_1 ax8_2 ax8_3 ax8_4], 'x');

xlabel(tl8, time_label, 'FontSize', 11, 'FontName', 'Arial');
title(tl8, 'Tracking Error & Energy Balance Analysis', 'FontSize', 13, 'FontName', 'Arial');

try
    exportgraphics(fig8, fullfile(scenario_dir, '08_Error_And_Energy.png'), 'Resolution', 200);
    close(fig8);
catch
    fprintf('Warning: Could not save Figure 8\n');
    close(fig8);
end

fprintf('\n✓ All 8 academic figures generated and saved!\n');
fprintf('✓ Location: %s\n\n', scenario_dir);

%% ════════════════════════════════════════════════════════════════════════════
%% CSV EXPORT & REPORT GENERATION
%% ════════════════════════════════════════════════════════════════════════════

% Save CSV manually (simpler approach to avoid table row mismatch)
csv_filename = fullfile(scenario_dir, 'simulation_log.csv');
fid_csv = fopen(csv_filename, 'w');
fprintf(fid_csv, 'Time_sec,Pan_Actual_deg,Pan_Target_deg,Pan_Error_deg,Tilt_Actual_deg,Tilt_Target_deg,Tilt_Error_deg,Incidence_deg,IsLocked,LDR_Right_V,LDR_Left_V,LDR_Up_V,LDR_Down_V,Current_Pan_A,Current_Tilt_A,Velocity_Pan_dps,Velocity_Tilt_dps,Power_Pan_W,Power_Tilt_W,Power_Total_W\n');
for i = 1:min(length(Log.Time), 10000) % Limit to 10k rows for CSV (to keep file manageable)
    fprintf(fid_csv, '%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n', ...
        Log.Time(i), Log.ActualPan(i), Log.TargetPan(i), Log.TargetPan(i)-Log.ActualPan(i), ...
        Log.ActualTilt(i), Log.TargetTilt(i), Log.TargetTilt(i)-Log.ActualTilt(i), ...
        Log.Incidence(i), Log.IsLocked(i), ...
        Log.LDR_Voltage(i,1), Log.LDR_Voltage(i,2), Log.LDR_Voltage(i,3), Log.LDR_Voltage(i,4), ...
        Log.I_Pan(i), Log.I_Tilt(i), ...
        Log.ServoVelPan(i), Log.ServoVelTilt(i), ...
        Log.Power_Pan(i), Log.Power_Tilt(i), Log.Power_Total(i));
end
fclose(fid_csv);
fprintf('✓ CSV log saved: %s (%d rows)\n', csv_filename, min(length(Log.Time), 10000));

% Generate automatic report
report_filename = fullfile(scenario_dir, 'REPORT.txt');
fid = fopen(report_filename, 'w');

fprintf(fid, '═══════════════════════════════════════════════════════════════\n');
fprintf(fid, '           SOLAR TRACKER SIMULATION REPORT\n');
fprintf(fid, '═══════════════════════════════════════════════════════════════\n\n');

fprintf(fid, 'TEST PARAMETERS\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Scenario:           %s\n', SCENARIO);
fprintf(fid, 'Control Mode:       %s\n', CONTROL_MODE);
fprintf(fid, 'Duration:           %.0f seconds (%.2f minutes)\n', duration_sec, duration_sec/60);
fprintf(fid, 'Sun Motion Speed:   %.4f °/s\n', spiral_speed);
fprintf(fid, 'Sampling Rate:      %.0f Hz (dt=%.3f s)\n', 1/dt_physics, dt_physics);
fprintf(fid, 'Total Data Points:  %d\n\n', num_steps);

fprintf(fid, 'TRACKING ACCURACY\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Mean Incidence Error:     %.4f deg\n', tracking_error_mean);
fprintf(fid, 'Max Incidence Error:      %.4f deg\n', tracking_error_max);
fprintf(fid, 'Final (Steady-State):     %.4f deg\n', tracking_error_final);
fprintf(fid, 'Lock Percentage:          %.2f%%\n\n', lock_percentage);

fprintf(fid, 'ADVANCED METRICS\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Settling Time:            %.2f seconds\n', settling_time);
fprintf(fid, 'Rise Time (90%%):          %.2f seconds\n', rise_time);
fprintf(fid, 'Overshoot:                %.2f%%\n', overshoot_pct);
fprintf(fid, 'Steady-State Error:       %.4f deg\n\n', steady_state_error);

fprintf(fid, 'SERVO PERFORMANCE\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Max Pan Velocity:         %.2f °/s\n', max_vel_pan);
fprintf(fid, 'Max Tilt Velocity:        %.2f °/s\n', max_vel_tilt);
fprintf(fid, 'Servo Speed Limit:        %.2f °/s\n\n', ServoProps.MaxSpeed);

fprintf(fid, 'ENERGY CONSUMPTION\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Total Energy:             %.4f Wh\n', total_energy);
fprintf(fid, 'Average Power:            %.2f W\n', avg_power);
fprintf(fid, 'Peak Power:               %.2f W\n\n', max_power);

% Calculate solar energy metrics
cumul_energy_available = sum(Log.SolarPower) * dt_physics / 3600;
cumul_energy_used = total_energy;
energy_balance = cumul_energy_available - cumul_energy_used;
solar_efficiency = (cumul_energy_used / (cumul_energy_available + 1e-6)) * 100;

fprintf(fid, '\nENERGY BALANCE (Tracker Panel: %.2f m² @ %.0f%% efficiency)\n', PanelTrackerProps.Area, PanelTrackerProps.Efficiency*100);
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Total Available Solar:    %.4f Wh\n', cumul_energy_available);
fprintf(fid, 'Total Used by Motors:     %.4f Wh\n', cumul_energy_used);
fprintf(fid, 'Net Energy Balance:       %.4f Wh\n', energy_balance);
fprintf(fid, 'System Efficiency:        %.2f%%\n\n', solar_efficiency);

fprintf(fid, 'SUB-PANEL POWER DISTRIBUTION\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Sub-Panel Specifications:\n');
fprintf(fid, '  Area per panel:         %.3f m²\n', SubPanelProps.Area);
fprintf(fid, '  Efficiency:             %.2f%%\n', SubPanelProps.Efficiency * 100);
fprintf(fid, '  Total sub-panel energy: %.4f Wh\n', sum(Log.P_subpanel_total) * dt_physics / 3600);
energy_per_face = sum(Log.P_subpanels) * dt_physics / 3600;
fprintf(fid, '  Breakdown by face:\n');
fprintf(fid, '    Right (+X):           %.4f Wh\n', energy_per_face(1));
fprintf(fid, '    Left  (-X):           %.4f Wh\n', energy_per_face(2));
fprintf(fid, '    Up    (+Y):           %.4f Wh\n', energy_per_face(3));
fprintf(fid, '    Down  (-Y):           %.4f Wh\n\n', energy_per_face(4));

% PVGIS report section (only for SOLAR_DAY scenario)
if ~TEST_MODE
    fprintf(fid, 'PVGIS IRRADIANCE ANALYSIS\n');
    fprintf(fid, '───────────────────────────────────────────────────────────────\n');
    fprintf(fid, 'Analysis Mode:            %s\n', Scenario.analysis_mode);
    fprintf(fid, 'Reference Date:           %s\n', char(string(DayStats.date, 'dd-MMM-yyyy')));
    fprintf(fid, 'Peak Irradiance:          %.1f W/m²\n', DayStats.peak_irradiance);
    fprintf(fid, 'Daylight Duration:        %.2f hours\n', DayStats.daylight_hours);
    fprintf(fid, 'Daily Insolation:         %.1f Wh/m² (∫G·dt via trapz)\n', DayStats.daily_insolation);

    % Calculate energy metrics from simulation
    E_fixed_total = sum(Log.P_fixed) * dt_physics / 3600;
    E_tracker_gross = sum(Log.P_tracker) * dt_physics / 3600;
    E_motor_consumed = sum(Log.Power_Total) * dt_physics / 3600;
    E_tracker_net = sum(Log.P_net_tracker) * dt_physics / 3600;
    gain_versus_fixed = ((E_tracker_net - E_fixed_total) / (E_fixed_total + 1e-6)) * 100;

    fprintf(fid, 'Fixed Panel Yield:        %.2f Wh\n', E_fixed_total);
    fprintf(fid, 'Tracker Gross Yield:      %.2f Wh\n', E_tracker_gross);
    fprintf(fid, 'Motor Consumption:        %.2f Wh\n', E_motor_consumed);
    fprintf(fid, 'Net Tracker Yield:        %.2f Wh\n', E_tracker_net);
    fprintf(fid, 'Gain over Fixed:          %+.1f%%\n\n', gain_versus_fixed);
else
    fprintf(fid, 'SIMULATION MODE\n');
    fprintf(fid, '───────────────────────────────────────────────────────────────\n');
    fprintf(fid, 'Mode:                     %s (Spiral/Test)\n', Scenario.name);
    fprintf(fid, 'Test Duration:            %.0f seconds\n\n', duration_sec);
end

fprintf(fid, 'PID PARAMETERS\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Proportional Gain (Kp):   %.4f\n', PIDProps.Kp);
fprintf(fid, 'Integral Gain (Ki):       %.4f\n', PIDProps.Ki);
fprintf(fid, 'Derivative Gain (Kd):     %.4f\n', PIDProps.Kd);
fprintf(fid, 'Max Integral:             %.2f\n\n', PIDProps.MaxIntegral);

fprintf(fid, 'FSM THRESHOLDS\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, 'Night Threshold:          %.2f V\n', SupervisorParams.night_threshold);
fprintf(fid, 'Sun Lost Threshold:       %.2f V\n', SupervisorParams.sun_lost_threshold);
fprintf(fid, 'Sun Found Threshold:      %.2f V\n', SupervisorParams.sun_found_threshold);
fprintf(fid, 'Lock Threshold:           %.2f deg\n\n', SupervisorParams.lock_threshold);

fprintf(fid, 'GENERATED FILES\n');
fprintf(fid, '───────────────────────────────────────────────────────────────\n');
fprintf(fid, '01_System_Performance.png\n');
fprintf(fid, '02_LDR_Sensor_Analysis.png\n');
fprintf(fid, '03_Controller_Analysis.png\n');
fprintf(fid, '04_FSM_State_Machine.png\n');
fprintf(fid, '05_Energy_Analysis.png\n');
fprintf(fid, '06_Motor_Control_Trajectory.png\n');
fprintf(fid, '07_Energy_Balance.png\n');
fprintf(fid, '01_Tracking_Performance.png  (Academic tiledlayout)\n');
fprintf(fid, '02_LDR_Sensor_Analysis.png   (Academic tiledlayout)\n');
fprintf(fid, '03_Controller_Internals.png  (Academic tiledlayout)\n');
fprintf(fid, '04_FSM_Analysis.png          (Academic tiledlayout)\n');
fprintf(fid, '05_SubPanel_Power.png        (Academic tiledlayout)\n');
fprintf(fid, '05b_SubPanel_Energy_Summary.png\n');
fprintf(fid, '06_Energy_Budget.png         (Academic tiledlayout)\n');
fprintf(fid, '07_Gimbal_Trajectory.png     (Academic tiledlayout)\n');
fprintf(fid, '08_Error_And_Energy.png      (Academic tiledlayout)\n');
fprintf(fid, 'simulation_log.csv\n');
fprintf(fid, 'REPORT.txt\n\n');

fprintf(fid, '═══════════════════════════════════════════════════════════════\n');
fprintf(fid, 'Report generated: %s\n', datetime('now'));
fprintf(fid, '═══════════════════════════════════════════════════════════════\n');

fclose(fid);
fprintf('✓ Report saved: %s\n\n', report_filename);

%% ════════════════════════════════════════════════════════════════════════════
%% LOCAL FUNCTION: FSM State Background Shading
%% ════════════════════════════════════════════════════════════════════════════
function shadeFSMStates(ax, time_axis, fsm_mode_cell)
    % USAGE: shadeFSMStates(ax, time_axis, Log.FSM_Mode(p_idx))
    % time_axis and fsm_mode_cell MUST have the same length (both downsampled).
    if nargin < 3 || isempty(fsm_mode_cell) || isempty(time_axis)
        return;
    end
    n = min(length(fsm_mode_cell), length(time_axis));
    state_colors = struct('IDLE',     [0.93 0.93 0.93], ...
                          'SEARCH',   [1.00 1.00 0.75], ...
                          'HOLD',     [0.82 0.93 1.00], ...
                          'TRACKING', [0.82 1.00 0.82]);
    y_limits = ylim(ax);
    y_min = y_limits(1); y_max = y_limits(2);
    current_state = ''; region_start = 1;
    for i = 1:n
        mode_str = char(fsm_mode_cell{i});
        is_last = (i == n);
        state_changed = ~strcmp(mode_str, current_state);
        if (state_changed || is_last) && ~isempty(current_state)
            region_end = i - 1;
            if is_last && ~state_changed
                region_end = i;
            end
            region_end   = min(region_end,   n);
            region_start = min(region_start, n);
            if isfield(state_colors, current_state)
                col = state_colors.(current_state);
            else
                col = [1 1 1];
            end
            t0 = time_axis(region_start);
            t1 = time_axis(region_end);
            if t1 > t0
                p = patch(ax, [t0 t1 t1 t0], [y_min y_min y_max y_max], ...
                    col, 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
                    'HandleVisibility', 'off', 'Tag', 'FSMShading');
                uistack(p, 'bottom');
            end
        end
        if state_changed
            current_state = mode_str;
            region_start  = i;
        end
    end
end

%% ════════════════════════════════════════════════════════════════════════════
%% HELPER FUNCTIONS (DEPRECATED - See Utils/ folder for centralized versions)
%% ════════════════════════════════════════════════════════════════════════════
% These functions have been moved to Utils/ for parameter ownership
% consistency and to enable reuse across other scripts.
% Call them as: cartesian2spherical(), applyFlipLogic(), ternary(), getFieldOrDefault()
% ════════════════════════════════════════════════════════════════════════════