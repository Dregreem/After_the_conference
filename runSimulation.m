function [Log, Metrics] = runSimulation(cfg)
% RUNSIMULATION - Headless-capable simulation core extracted from main_easy.m
%
% SUB-STEPPING:
%   OUTER loop  dt_outer=1 s  → getSunVector / getPVGISatTime / readLDRs /
%                               StateManagerFSM / logging
%                               (all change negligibly over 1 second)
%   INNER loop  dt_physics    → PID_VelocityController / FuzzyLogicController /
%                               stepTheoreticalServo
%                               (must run at 0.01 s — PID/servo tuning)
%
%   N_sub = dt_outer / dt_physics = 100 sub-steps per outer step.
%   Zero accuracy loss; same runtime as original dt=1 s single-loop.
%
% USAGE:
%   cfg.SCENARIO      = 'SOLAR_DAY';
%   cfg.CONTROL_MODE  = 'pid';
%   cfg.PHYSICS_MODEL = 'THEORETICAL';
%   cfg.dt_physics    = 0.01;
%   cfg.dt_control    = 0.01;
%   cfg.draw          = false;
%   [Log, Metrics] = runSimulation(cfg);

%% ── UNPACK CONFIG ──────────────────────────────────────────────────────────
SCENARIO      = cfg.SCENARIO;
CONTROL_MODE  = cfg.CONTROL_MODE;
PHYSICS_MODEL = getFieldOrDefault(cfg, 'PHYSICS_MODEL', 'THEORETICAL');
dt_physics    = getFieldOrDefault(cfg, 'dt_physics',    0.01);
dt_control    = getFieldOrDefault(cfg, 'dt_control',    0.01);
DRAW          = getFieldOrDefault(cfg, 'draw',          false);
DrawSkip      = getFieldOrDefault(cfg, 'DrawSkip',      5);

% Sub-stepping constants — outer loop is always 1 s
dt_outer = 1.0;
N_sub    = round(dt_outer / dt_physics);   % = 100 when dt_physics=0.01

% dt_control is kept for interface compatibility but is not used as the
% loop timestep anymore — FSM now runs at dt_outer (1 Hz), which is
% intentionally slow and matches the supervisor design.

%% ── SCENARIO ───────────────────────────────────────────────────────────────
Scenario = generateScenario(SCENARIO);

spiral_speed = Scenario.spiral_speed;
spiral_widen = Scenario.spiral_widen;
duration_sec = Scenario.duration_sec;

TEST_MODE = ~strcmpi(Scenario.name, 'SOLAR_DAY');

if ~TEST_MODE
    PVData_full = loadPVGIS(Scenario.pvgis_file);
    [PVData, DayStats] = filterPVGISbyDate(PVData_full, ...
        Scenario.analysis_mode, Scenario.analysis_date);
end

%% ── SIM DATE ───────────────────────────────────────────────────────────────
if strcmpi(Scenario.name, 'SOLAR_DAY')
    SimDate = Scenario.date + hours(Scenario.t_start_hour);
else
    SimDate = datetime(2024, 10, 21, 8, 0, 0);
end

%% ── VISUALIZATION INIT (guarded) ───────────────────────────────────────────
if DRAW
    handles = initSolarWorld();
    ax = gca; set(ax, 'OuterPosition', [0, 0, 0.75, 1]);
    Mech = initSystemMechanics(ax);
    SunDistance = 1.1;
    InfoBox = annotation('textbox', [0.76, 0.2, 0.23, 0.7], ...
                         'String', 'Initializing...', ...
                         'EdgeColor', 'k', 'BackgroundColor', [0.95 0.95 0.95], ...
                         'FaceAlpha', 0.8, 'FontSize', 10, 'FontName', 'Consolas');
else
    handles = struct();
    Mech    = struct('h_Pan', [], 'h_Tilt', [], 'PivotOffset', [0;0;0]);
    InfoBox = [];
    SunDistance = 1.1;
end

%% ── SERVO STATES ────────────────────────────────────────────────────────────
StatePan  = struct('Angle', 0, 'Velocity', 0, 'Current', 0, 'Energy', 0);
StateTilt = struct('Angle', 0, 'Velocity', 0, 'Current', 0, 'Energy', 0);

if strcmp(SCENARIO, 'ZENITH_STATIC')
    StatePan.Angle  = 45.0;
    StateTilt.Angle = 2.0;
elseif strcmp(SCENARIO, 'FLIP_BOUNDARY')
    StatePan.Angle  = 10.0;
    StateTilt.Angle = 45.0;
end

%% ── FSM / CONTROLLER STATE ──────────────────────────────────────────────────
% All fields that StateManagerFSM requires — including hold_timer, burst_timer
% and was_night which were missing in the original and caused unpredictable
% transitions via ensureField() fallbacks.
FSM_State = struct('mode', 'TRACKING', ...
                   'e_pan_prev', 0, 'e_tilt_prev', 0, ...
                   'de_pan_filtered', 0, 'de_tilt_filtered', 0, ...
                   'search_phase', 0, ...
                   'hold_timer', 0, 'burst_timer', 0, ...
                   'was_night', false, ...
                   'park_target_pan', 0, 'park_target_tilt', 90);

ControlState = struct('I_pan', 0, 'I_tilt', 0, 'de_pan_filt', 0, 'de_tilt_filt', 0);

SupervisorParams = struct();
SupervisorParams.night_threshold     = getFieldOrDefault(Scenario, 'night_threshold',    0.3);
SupervisorParams.sun_lost_threshold  = getFieldOrDefault(Scenario, 'sun_lost_threshold', 0.5);
SupervisorParams.sun_found_threshold = getFieldOrDefault(Scenario, 'sun_found_threshold',1.0);
SupervisorParams.lock_threshold      = getFieldOrDefault(Scenario, 'lock_threshold',     0.5);
SupervisorParams.search_speed        = getFieldOrDefault(Scenario, 'search_speed',       3.0);
SupervisorParams.tracking_deadband   = getFieldOrDefault(Scenario, 'tracking_deadband',  3.0);
SupervisorParams.batch_interval      = getFieldOrDefault(Scenario, 'batch_interval',   120.0);
SupervisorParams.max_burst_time      = getFieldOrDefault(Scenario, 'max_burst_time',     8.0);
SupervisorParams.zenith_pan_lock     = 5;
SupervisorParams.rate_filter_alpha   = 0.95;

CommandSmoothing   = struct('target_pan_smoothed', 0, 'target_tilt_smoothed', 0);
FLIP_OVERRIDE_FACTOR = 0.5;
USE_FLIP_LOGIC       = true;

flip_state = struct('is_flipped', false, 'flip_count', 0, 'last_flip_time', -inf);
FlipLog = struct('times', [], 'is_flipped', [], 'azimuth_sun', [], ...
                 'elevation_sun', [], 'is_reachable', [], ...
                 'target_pan_final', [], 'target_tilt_final', []);

%% ── MODULE PROPS (one-time, at dt_physics so servo constants are correct) ───
[~, ~, ServoProps]  = stepTheoreticalServo(StatePan, 0, dt_physics, 'Pan');
[~, ~, ~, PIDProps] = PID_VelocityController( ...
    struct('e_pan',0,'e_tilt',0,'de_pan',0,'de_tilt',0,'mode','IDLE'), ...
    ControlState, [], dt_physics);  %#ok<ASGLU>
[~, ~, ~, ~, ~, ~] = readLDRs([0;0;1], [], []);
[~, PanelFixedProps]   = pvPanelPower(0, 0, 0, struct('A', 1.0, 'eta', 0.20));
[~, PanelTrackerProps] = pvTrackerPower(0, 0, struct('A', 1.0, 'eta', 0.20));
[~, SubPanelProps]     = pvSubPanelPower(0, [0;0;1], []);  %#ok<ASGLU>

%% ── PREALLOCATE LOGS (on 1 s outer grid) ────────────────────────────────────
% Logging at 1 Hz is sufficient for all energy integrals.
% Finer resolution would waste memory without adding information since
% irradiance and sun position themselves only update at 1 Hz.
time_vector = (0 : dt_outer : duration_sec)';
num_steps   = length(time_vector);

Log.Time          = time_vector';   % row vector — keeps compatibility with original
Log.TargetPan     = zeros(num_steps, 1); Log.ActualPan      = zeros(num_steps, 1);
Log.TargetTilt    = zeros(num_steps, 1); Log.ActualTilt     = zeros(num_steps, 1);
Log.ServoVelPan   = zeros(num_steps, 1); Log.ServoVelTilt   = zeros(num_steps, 1);
Log.I_Pan         = zeros(num_steps, 1); Log.I_Tilt         = zeros(num_steps, 1);
Log.IsFlip        = zeros(num_steps, 1);
Log.LDR_Voltage   = zeros(num_steps, 4); Log.FSM_Mode       = cell(num_steps, 1);
Log.V_Total       = zeros(num_steps, 1);
Log.E_norm_Pan    = zeros(num_steps, 1); Log.E_norm_Tilt    = zeros(num_steps, 1);
Log.E_deg_Pan     = zeros(num_steps, 1); Log.E_deg_Tilt     = zeros(num_steps, 1);
Log.Incidence     = zeros(num_steps, 1); Log.IsLocked       = zeros(num_steps, 1);
Log.PID_P_Pan     = zeros(num_steps, 1); Log.PID_I_Pan      = zeros(num_steps, 1); Log.PID_D_Pan  = zeros(num_steps, 1);
Log.PID_P_Tilt    = zeros(num_steps, 1); Log.PID_I_Tilt     = zeros(num_steps, 1); Log.PID_D_Tilt = zeros(num_steps, 1);
Log.FLC_Vel_Pan   = zeros(num_steps, 1); Log.FLC_Vel_Tilt   = zeros(num_steps, 1);
Log.FLC_Rate_Pan  = zeros(num_steps, 1); Log.FLC_Rate_Tilt  = zeros(num_steps, 1);
Log.Power_Pan     = zeros(num_steps, 1); Log.Power_Tilt     = zeros(num_steps, 1); Log.Power_Total = zeros(num_steps, 1);
Log.LockCounter   = zeros(num_steps, 1); Log.LDR_DynamicRange = zeros(num_steps, 1);
Log.Servo_Velocity_Pan  = zeros(num_steps, 1); Log.Servo_Velocity_Tilt  = zeros(num_steps, 1);
Log.Servo_EquivD_Pan    = zeros(num_steps, 1); Log.Servo_EquivD_Tilt    = zeros(num_steps, 1);
Log.Irradiance    = zeros(num_steps, 1); Log.SolarPower     = zeros(num_steps, 1);
Log.P_fixed       = zeros(num_steps, 1); Log.P_tracker      = zeros(num_steps, 1);
Log.P_net_tracker = zeros(num_steps, 1); Log.G              = zeros(num_steps, 1);
Log.P_subpanels   = zeros(num_steps, 4); Log.P_subpanel_total = zeros(num_steps, 1);
for k = 1:num_steps, Log.FSM_Mode{k} = 'IDLE'; end

%% ── SEED VARIABLES (used before first update) ───────────────────────────────
azimuth_sun   = 0;    elevation_sun = 45;
S_vec         = [0; 0; 1];
LDR_V_ctrl    = ones(4,1);
is_flip       = false; is_reachable = true;
target_pan    = 0;     target_tilt  = 0;
S_body_norm   = [0;0;1];
P_subpanels_i = zeros(4,1);
G_now         = 0;    irradiance   = 0;   G_irradiance = 0;
DebugFSM      = struct('mode','TRACKING','vel_pan',0,'vel_tilt',0,'target_pan',0,'target_tilt',0);
ErrorSignal   = struct('e_pan',0,'e_tilt',0,'de_pan',0,'de_tilt',0,'mode','TRACKING');
VelCmd        = struct('v_pan',0,'v_tilt',0);
DebugCtrl     = struct('P_pan',0,'P_tilt',0,'I_pan',0,'I_tilt',0,'D_pan',0,'D_tilt',0);
adjusted_pan_from_sun  = 0;
adjusted_tilt_from_sun = 0;
fsm_is_active = true;

%% ══════════════════════════════════════════════════════════════════════════
%% OUTER LOOP  (1 Hz — sun / PVGIS / FSM / logging)
%% ══════════════════════════════════════════════════════════════════════════

for i = 1:num_steps

    %% ── Abort guard (draw mode only) ────────────────────────────────────
    if DRAW
        try
            if ~isvalid(handles.h_Sun) || ~isvalid(Mech.h_Pan), break; end
        catch; break; end
    end

    sim_time_elapsed = time_vector(i);
    current_time     = SimDate + seconds(sim_time_elapsed);

    %% ── SUN POSITION (1 Hz) ─────────────────────────────────────────────
    if TEST_MODE
        angle_phi   = spiral_speed * sim_time_elapsed;
        angle_alpha = 90 - (spiral_widen * sim_time_elapsed);
        if angle_alpha < 0, angle_alpha = 0; end
        az    = deg2rad(angle_phi);
        el    = deg2rad(angle_alpha);
        S_vec = [cos(el)*sin(az); cos(el)*cos(az); sin(el)];
        alpha = angle_alpha;
        phi   = angle_phi;
    else
        [S_vec, alpha, phi] = getSunVector(Scenario.lat, Scenario.lon, current_time, Scenario.tz);
        if alpha <= 0, alpha = 0; S_vec = [0;0;0]; end
    end

    %% ── PVGIS / irradiance (1 Hz) ───────────────────────────────────────
    sun_el_rad = deg2rad(alpha);
    irradiance = 1000 * max(0, sin(sun_el_rad));

    if ~TEST_MODE
        pvgis_t = Scenario.t_start_hour * 3600 + sim_time_elapsed;
        [G_now, ~]   = getPVGISatTime(pvgis_t, PVData);
        G_irradiance = G_now;
    else
        G_now        = irradiance;
        G_irradiance = irradiance;
    end

    %% ── Body frame + LDR + Flip logic (1 Hz — slow-changing) ───────────
    theta_pan_curr  = StatePan.Angle;
    theta_tilt_curr = StateTilt.Angle;

    cp = cosd(theta_pan_curr);  sp = sind(theta_pan_curr);
    ct = cosd(theta_tilt_curr); st = sind(theta_tilt_curr);
    Sx_rz = cp*S_vec(1) - sp*S_vec(2);
    Sy_rz = sp*S_vec(1) + cp*S_vec(2);
    Sz_rz = S_vec(3);
    S_body_pre  = [Sx_rz; ct*Sy_rz - st*Sz_rz; st*Sy_rz + ct*Sz_rz];
    S_body_norm = S_body_pre / (norm(S_body_pre) + 1e-8);

    [~, LDR_V_ctrl, ~, ~, ~, ~] = readLDRs(S_body_norm);

    [azimuth_sun, elevation_sun] = cartesian2spherical(S_vec);
    ideal_pan_from_azimuth    = azimuth_sun;
    ideal_tilt_from_elevation = max(-90, min(90, 90 - elevation_sun));
    if ideal_pan_from_azimuth > 180
        ideal_pan_from_azimuth = ideal_pan_from_azimuth - 360;
    end

    [adjusted_pan_from_sun, adjusted_tilt_from_sun, is_flip, is_reachable] = ...
        applyFlipLogic(ideal_pan_from_azimuth, ideal_tilt_from_elevation);

    %% ── BLOCK A: FSM Supervisor (1 Hz — slow decision-maker by design) ──
    % FSM runs with dt_outer so its hold_timer and burst_timer accumulate
    % correctly at 1 s/step, which matches the batch_interval (120 s) and
    % max_burst_time (8 s) parameters.
    [ErrorSignal, FSM_State, DebugSup, ~] = StateManagerFSM( ...
        LDR_V_ctrl, S_body_pre, theta_pan_curr, theta_tilt_curr, ...
        FSM_State, SupervisorParams, dt_outer, is_flip);

    fsm_is_active = ismember(FSM_State.mode, {'TRACKING','SEARCH','PARK'});

    % Flip log (identical to original)
    if is_reachable
        FlipLog.times           = [FlipLog.times,           sim_time_elapsed];
        FlipLog.is_flipped      = [FlipLog.is_flipped,      is_flip];
        FlipLog.azimuth_sun     = [FlipLog.azimuth_sun,     azimuth_sun];
        FlipLog.elevation_sun   = [FlipLog.elevation_sun,   elevation_sun];
        FlipLog.is_reachable    = [FlipLog.is_reachable,    is_reachable];
        FlipLog.target_pan_final  = [FlipLog.target_pan_final,  target_pan];
        FlipLog.target_tilt_final = [FlipLog.target_tilt_final, target_tilt];
        if is_flip && ~flip_state.is_flipped
            flip_state.is_flipped     = true;
            flip_state.flip_count     = flip_state.flip_count + 1;
            flip_state.last_flip_time = sim_time_elapsed;
        elseif ~is_flip && flip_state.is_flipped
            flip_state.is_flipped = false;
        end
    end

    %% ════════════════════════════════════════════════════════════════════
    %% INNER LOOP  (100 Hz — PID + servo at dt_physics = 0.01 s)
    %% ErrorSignal, adjusted_pan/tilt, is_flip, is_reachable are all held
    %% constant from the outer step — they change <0.004° over 1 second.
    %% ════════════════════════════════════════════════════════════════════

    for s_inner = 1:N_sub

        %% BLOCK B: CONTROLLER (at dt_physics — matches tuning) ──────────
        if strcmp(CONTROL_MODE, 'fuzzy')
            [VelCmd, ControlState, DebugCtrl, ~] = FuzzyLogicController( ...
                ErrorSignal, ControlState, dt_physics);
        else
            [VelCmd, ControlState, DebugCtrl, ~] = PID_VelocityController( ...
                ErrorSignal, ControlState, struct(), dt_physics);
        end

        %% VELOCITY → POSITION INTEGRATION ───────────────────────────────
        pan_limit_val = 180;
        target_pan_from_ctrl  = StatePan.Angle  + VelCmd.v_pan  * dt_physics;
        target_tilt_from_ctrl = StateTilt.Angle + VelCmd.v_tilt * dt_physics;
        target_pan_from_ctrl  = max(-pan_limit_val, min(pan_limit_val, target_pan_from_ctrl));
        target_tilt_from_ctrl = max(-90,             min(90,             target_tilt_from_ctrl));

        if is_reachable && USE_FLIP_LOGIC && FLIP_OVERRIDE_FACTOR > 0 && fsm_is_active
            target_pan  = target_pan_from_ctrl  + FLIP_OVERRIDE_FACTOR*(adjusted_pan_from_sun  - target_pan_from_ctrl);
            target_tilt = target_tilt_from_ctrl + FLIP_OVERRIDE_FACTOR*(adjusted_tilt_from_sun - target_tilt_from_ctrl);
        else
            target_pan  = target_pan_from_ctrl;
            target_tilt = target_tilt_from_ctrl;
        end

        if fsm_is_active
            smooth_alpha_active = 0.95;
            CommandSmoothing.target_pan_smoothed  = (1-smooth_alpha_active)*CommandSmoothing.target_pan_smoothed  + smooth_alpha_active*target_pan;
            CommandSmoothing.target_tilt_smoothed = (1-smooth_alpha_active)*CommandSmoothing.target_tilt_smoothed + smooth_alpha_active*target_tilt;
        else
            % HOLD / IDLE — freeze at current position so motors de-energise
            CommandSmoothing.target_pan_smoothed  = StatePan.Angle;
            CommandSmoothing.target_tilt_smoothed = StateTilt.Angle;
        end

        target_pan_smooth  = CommandSmoothing.target_pan_smoothed;
        target_tilt_smooth = CommandSmoothing.target_tilt_smoothed;

        %% BLOCK C: SERVO PHYSICS (at dt_physics = 0.01 s) ───────────────
        if strcmp(PHYSICS_MODEL, 'COMPLEX')
            [StatePan,  ~] = stepDCMotorPhysics(StatePan,  target_pan_smooth,  dt_physics, 'Pan');
            [StateTilt, ~] = stepDCMotorPhysics(StateTilt, target_tilt_smooth, dt_physics, 'Tilt');
        elseif strcmp(PHYSICS_MODEL, 'THEORETICAL')
            [StatePan,  ~, ~] = stepTheoreticalServo(StatePan,  target_pan_smooth,  dt_physics, 'Pan');
            [StateTilt, ~, ~] = stepTheoreticalServo(StateTilt, target_tilt_smooth, dt_physics, 'Tilt');
        else
            [StatePan,  ~] = stepAdvancedServoPhysics(StatePan,  target_pan_smooth,  dt_physics, 'Pan');
            [StateTilt, ~] = stepAdvancedServoPhysics(StateTilt, target_tilt_smooth, dt_physics, 'Tilt');
        end

    end  %% ── end inner loop ──────────────────────────────────────────────

    %% ── Post-outer: refresh body frame with final servo angles ──────────
    theta_pan  = StatePan.Angle;
    theta_tilt = StateTilt.Angle;

    cp2 = cosd(theta_pan);  sp2 = sind(theta_pan);
    ct2 = cosd(theta_tilt); st2 = sind(theta_tilt);
    Sx2 = cp2*S_vec(1)-sp2*S_vec(2);
    Sy2 = sp2*S_vec(1)+cp2*S_vec(2);
    Sb  = [Sx2; ct2*Sy2-st2*S_vec(3); st2*Sy2+ct2*S_vec(3)];
    S_body_norm = Sb / (norm(Sb)+1e-8);

    %% ── Sub-panel power (uses refreshed body frame) ─────────────────────
    [P_subpanels_i, ~] = pvSubPanelPower(G_irradiance, S_body_norm, []);

    %% ── DebugFSM (identical fields to original) ─────────────────────────
    DebugFSM          = DebugSup;
    DebugFSM.vel_pan  = VelCmd.v_pan;
    DebugFSM.vel_tilt = VelCmd.v_tilt;
    DebugFSM.target_pan  = target_pan;
    DebugFSM.target_tilt = target_tilt;

    %% ── VISUALIZATION (draw mode, every DrawSkip outer steps) ───────────
    if DRAW && DrawSkip > 0 && mod(i, DrawSkip) == 0
        try
            M_pan = makehgtform('zrotate', deg2rad(-theta_pan));
            set(Mech.h_Pan, 'Matrix', M_pan);
            M_tilt_trans = makehgtform('translate', Mech.PivotOffset);
            M_tilt_rot   = makehgtform('xrotate', deg2rad(-theta_tilt));
            set(Mech.h_Tilt, 'Matrix', M_tilt_trans * M_tilt_rot);

            P_sun = S_vec * SunDistance;
            if isvalid(handles.h_PathSun)
                addpoints(handles.h_PathSun, P_sun(1), P_sun(2), P_sun(3));
            end
            updateSolarWorld(handles, S_vec, SunDistance, current_time, alpha, phi);

            M_pan_temp  = makehgtform('zrotate', deg2rad(-theta_pan));
            M_tilt_temp = makehgtform('xrotate', deg2rad(-theta_tilt));
            R_Total     = M_pan_temp(1:3,1:3) * M_tilt_temp(1:3,1:3);
            P_Tracker   = (R_Total * [0;0;1]) * SunDistance;
            if isvalid(handles.h_PathTracker)
                addpoints(handles.h_PathTracker, P_Tracker(1), P_Tracker(2), P_Tracker(3));
            end

            [E_pan_disp, E_tilt_disp, E_deg_pan_disp, E_deg_tilt_disp, ~] = controlLDR( ...
                LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4), S_body_norm);
            [theta_inc_disp, ~] = checkAlignment(S_body_norm);
            flip_indicator  = ternary(is_flip, ' FLIP', '→ NORMAL');
            e_total_display = sqrt(E_deg_pan_disp^2 + E_deg_tilt_disp^2);

            InfoStr = { ...
                sprintf('═══════ SCENARIO: %s ═══════', upper(SCENARIO)), ...
                '', ...
                sprintf('TIME: %.1f / %.0f s', sim_time_elapsed, duration_sec), ...
                '', sprintf('☀️  Az: %.1f°  |  El: %.1f°', azimuth_sun, elevation_sun), ...
                '', sprintf('Pan:  %.1f°  |  Tilt: %.1f°', theta_pan, theta_tilt), ...
                '', sprintf('Inc:  %.3f°', theta_inc_disp), ...
                '', sprintf('FSM: %s', FSM_State.mode), ...
                sprintf('Hold: %.0f/%.0f s', FSM_State.hold_timer, SupervisorParams.batch_interval), ...
                sprintf('e_total: %.2f°', e_total_display), ...
                '', sprintf('Pan: %.3fA  Tilt: %.3fA', StatePan.Current, StateTilt.Current), ...
                '', sprintf('Flip: %s (x%d)', flip_indicator, flip_state.flip_count) ...
            };
            set(InfoBox, 'String', InfoStr);
            drawnow limitrate;
        catch
            fprintf('Graphics error. Continuing...\n');
            break;
        end
    end

    %% ── LOGGING (1 Hz — identical fields to original) ───────────────────
    Log.TargetPan(i)  = target_pan;    Log.ActualPan(i)   = theta_pan;
    Log.TargetTilt(i) = target_tilt;   Log.ActualTilt(i)  = theta_tilt;
    Log.ServoVelPan(i)  = abs(StatePan.Velocity);
    Log.ServoVelTilt(i) = abs(StateTilt.Velocity);
    Log.I_Pan(i)  = StatePan.Current;  Log.I_Tilt(i) = StateTilt.Current;
    Log.IsFlip(i) = is_flip;
    Log.FSM_Mode{i} = DebugFSM.mode;
    Log.V_Total(i)  = sum(LDR_V_ctrl);
    Log.LDR_Voltage(i,:) = LDR_V_ctrl';

    [E_pan, E_tilt, E_deg_pan, E_deg_tilt, ldr_locked] = controlLDR( ...
        LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4), S_body_norm);
    Log.E_deg_Pan(i)  = E_deg_pan;   Log.E_deg_Tilt(i)  = E_deg_tilt;
    Log.E_norm_Pan(i) = E_pan;       Log.E_norm_Tilt(i) = E_tilt;
    Log.IsLocked(i)   = ldr_locked;

    [theta_inc, ~] = checkAlignment(S_body_norm);
    Log.Incidence(i) = theta_inc;

    if ~TEST_MODE
        Log.G(i)              = G_now;
        [Log.P_fixed(i), ~]   = pvPanelPower(G_now, azimuth_sun, elevation_sun, ...
                                struct('A', PanelFixedProps.Area, 'eta', 0.20));
        [Log.P_tracker(i), ~] = pvTrackerPower(G_now, theta_inc, ...
                                struct('A', PanelTrackerProps.Area, 'eta', PanelTrackerProps.Efficiency));
        Log.P_net_tracker(i)  = Log.P_tracker(i) - Log.Power_Total(i);
    else
        Log.G(i)              = G_irradiance;
        [Log.P_fixed(i), ~]   = pvPanelPower(G_irradiance, azimuth_sun, elevation_sun, ...
                                struct('A', PanelFixedProps.Area, 'eta', 0.20));
        [Log.P_tracker(i), ~] = pvTrackerPower(G_irradiance, theta_inc, ...
                                struct('A', PanelTrackerProps.Area, 'eta', PanelTrackerProps.Efficiency));
        Log.P_net_tracker(i)  = Log.P_tracker(i) - Log.Power_Total(i);
    end

    if strcmp(CONTROL_MODE, 'fuzzy')
        Log.FLC_Vel_Pan(i)   = VelCmd.v_pan;
        Log.FLC_Vel_Tilt(i)  = VelCmd.v_tilt;
        Log.FLC_Rate_Pan(i)  = ErrorSignal.de_pan;
        Log.FLC_Rate_Tilt(i) = ErrorSignal.de_tilt;
    else
        Log.PID_P_Pan(i)  = DebugCtrl.P_pan;   Log.PID_P_Tilt(i)  = DebugCtrl.P_tilt;
        Log.PID_I_Pan(i)  = DebugCtrl.I_pan;   Log.PID_I_Tilt(i)  = DebugCtrl.I_tilt;
        Log.PID_D_Pan(i)  = DebugCtrl.D_pan;   Log.PID_D_Tilt(i)  = DebugCtrl.D_tilt;
    end

    Log.Servo_Velocity_Pan(i)  = StatePan.Velocity;
    Log.Servo_Velocity_Tilt(i) = StateTilt.Velocity;

    servo_error_pan  = target_pan_smooth  - theta_pan;
    servo_error_tilt = target_tilt_smooth - theta_tilt;
    Servo_Kv = 0.05;
    Log.Servo_EquivD_Pan(i)  = Servo_Kv * servo_error_pan;
    Log.Servo_EquivD_Tilt(i) = Servo_Kv * servo_error_tilt;

    Log.Power_Pan(i)   = StatePan.Current  * ServoProps.V_supply;
    Log.Power_Tilt(i)  = StateTilt.Current * ServoProps.V_supply;
    Log.Power_Total(i) = Log.Power_Pan(i) + Log.Power_Tilt(i);

    Log.Irradiance(i) = irradiance;
    Log.SolarPower(i) = Log.P_tracker(i);

    Log.P_subpanels(i,:)    = P_subpanels_i';
    Log.P_subpanel_total(i) = sum(P_subpanels_i);

    Log.LockCounter(i)      = double(theta_inc < SupervisorParams.lock_threshold);
    Log.LDR_DynamicRange(i) = max(LDR_V_ctrl) - min(LDR_V_ctrl);

end  %% ── end outer loop ───────────────────────────────────────────────────

%% ══════════════════════════════════════════════════════════════════════════
%% METRICS
%% (use dt_outer — that is the log timestep; energy integrals are correct)
%% ══════════════════════════════════════════════════════════════════════════

Metrics = struct();

valid = Log.Incidence > 0;
Metrics.mean_incidence = mean(Log.Incidence(valid));
Metrics.max_incidence  = max(Log.Incidence);

lock_time = sum(Log.IsLocked) * dt_outer;
Metrics.lock_percentage = 100 * lock_time / duration_sec;
Metrics.lock_time_s     = lock_time;

Metrics.total_energy_Wh      = sum(Log.Power_Total)    * dt_outer / 3600;
Metrics.avg_power_W          = mean(Log.Power_Total(Log.Power_Total > 0.001));
Metrics.peak_power_W         = max(Log.Power_Total);

Metrics.tracker_yield_Wh     = sum(Log.P_tracker)      * dt_outer / 3600;
Metrics.fixed_yield_Wh       = sum(Log.P_fixed)        * dt_outer / 3600;
Metrics.net_tracker_yield_Wh = sum(Log.P_net_tracker)  * dt_outer / 3600;

if Metrics.fixed_yield_Wh > 0
    Metrics.gain_vs_fixed = 100 * (Metrics.net_tracker_yield_Wh - Metrics.fixed_yield_Wh) / Metrics.fixed_yield_Wh;
else
    Metrics.gain_vs_fixed = 0;
end

Metrics.subpanel_energy_Wh = sum(Log.P_subpanel_total) * dt_outer / 3600;
Metrics.duration_sec       = duration_sec;
Metrics.scenario           = SCENARIO;
Metrics.controller         = CONTROL_MODE;
Metrics.dt_physics         = dt_physics;
Metrics.dt_outer           = dt_outer;
Metrics.N_sub              = N_sub;

end

%% ── LOCAL HELPER ────────────────────────────────────────────────────────────
function value = getFieldOrDefault(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        value = s.(field);
    else
        value = default;
    end
end