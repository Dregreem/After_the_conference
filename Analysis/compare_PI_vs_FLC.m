%% ╔════════════════════════════════════════════════════════════════════════╗
%% ║     PI vs FLC CONTROLLER COMPARISON (Dual Physics Support)          ║
%% ║     Runs both controllers on BOTH physics models, plots comparison  ║
%% ╚════════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

%% ════════════════════════════════════════════════════════════════════════════
%% CONFIGURATION - Change these parameters
%% ════════════════════════════════════════════════════════════════════════════

SCENARIO = 'EXTREME';      % REALISTIC, VEHICLE_SLOW, VEHICLE_FAST, ZENITH_STATIC, FLIP_BOUNDARY, EXTREME
PHYSICS_MODEL = 'THEORETICAL';    % 'SIMPLE' (Ideal Servo), 'COMPLEX' (DC Motor), 'THEORETICAL' (Academic 2nd-Order), or 'BOTH'

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║          PI vs FLC CONTROLLER COMPARISON                    ║\n');
fprintf('║          Scenario: %-38s  ║\n', SCENARIO);
fprintf('║          Physics:  %-38s  ║\n', PHYSICS_MODEL);
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% SHARED CONFIGURATION (identical for all runs)
%% ════════════════════════════════════════════════════════════════════════════

Scenario = generateScenario(SCENARIO);

spiral_speed = Scenario.spiral_speed;
spiral_widen = Scenario.spiral_widen;
duration_sec = Scenario.duration_sec;

dt_physics = 0.01;
dt_control = 0.01;
control_decimation = 1;
SUPPLY_VOLTAGE = 6.0;
SERVO_INTERNAL_Kv = 10.0;
TEST_MODE = true;

% PI Parameters
PID_Params.Kp_vel = Scenario.Kp_vel;
PID_Params.Ki_vel = Scenario.Ki_vel;
PID_Params.max_tracking_velocity = Scenario.max_tracking_velocity;
PID_Params.smooth_alpha = Scenario.smooth_alpha;
PID_Params.max_integral = 10;
PID_Params.deadzone = 0.05;
PID_Params.max_output = 30;
PID_Params.velocity_damping = 0.10;
PID_Params.pan_limit = 180;
PID_Params.tilt_limit = 90;
PID_Params.night_threshold = 0.3;
PID_Params.sun_lost_threshold = 0.5;
PID_Params.sun_found_threshold = 1.0;
PID_Params.lock_threshold = 0.5;
PID_Params.search_speed = 3.0;
PID_Params.zenith_pan_lock = true;

% FLC Parameters
FLC_Params.error_range       = [-60, 60];
FLC_Params.rate_range        = [-15, 15];
FLC_Params.output_range      = [-20, 20];
FLC_Params.rate_filter_alpha = 0.3;
FLC_Params.output_gain       = 1.0;
FLC_Params.defuzz_resolution = 101;
FLC_Params.night_threshold    = PID_Params.night_threshold;
FLC_Params.sun_lost_threshold = PID_Params.sun_lost_threshold;
FLC_Params.sun_found_threshold = PID_Params.sun_found_threshold;
FLC_Params.lock_threshold     = PID_Params.lock_threshold;
FLC_Params.search_speed       = PID_Params.search_speed;
FLC_Params.zenith_pan_lock    = PID_Params.zenith_pan_lock;
FLC_Params.pan_limit          = PID_Params.pan_limit;
FLC_Params.smooth_alpha       = PID_Params.smooth_alpha;

% Servo (SIMPLE)
ServoProps.MaxSpeed = 40;
ServoProps.Accel = 50;
ServoProps.Jerk = 200;

% DC Motor (COMPLEX — balanced, verified stable at dt=0.01)
MotorProps.R_arm      = 5.0;
MotorProps.L_arm      = 0.05;
MotorProps.Ke         = 0.1;
MotorProps.Kt         = 0.1;
MotorProps.V_supply   = 12.0;
MotorProps.J_total    = 0.002;
MotorProps.B_viscous  = 0.01;
MotorProps.T_stiction = 0.02;
MotorProps.T_coulomb  = 0.01;
MotorProps.m_load     = 0.3;
MotorProps.L_cg       = 0.05;
MotorProps.K_drive    = 1.5;
MotorProps.MaxSpeed   = 40.0;
MotorProps.pan_limit  = 180;
MotorProps.Backlash   = 0.0;

% Theoretical servo (THEORETICAL — pure 2nd-order nonlinear friction)
TheoreticalProps.MaxTorque = 0.35;          % N⋅m
TheoreticalProps.Inertia = 0.00015;         % kg⋅m²
TheoreticalProps.ViscousDamping = 0.01;   % N⋅m⋅s/rad
TheoreticalProps.StaticFriction = 0.02;   % N⋅m (stiction)
TheoreticalProps.DynamicFriction = 0.015; % N⋅m (kinetic)
TheoreticalProps.DeadbandVelocity = 0.05; % rad/s
TheoreticalProps.ServoGain = 0.1;         % Control command gain
TheoreticalProps.PanLimitMin = -deg2rad(180);
TheoreticalProps.PanLimitMax = deg2rad(180);
TheoreticalProps.TiltLimitMin = -deg2rad(90);
TheoreticalProps.TiltLimitMax = deg2rad(90);

% Flip logic
USE_FLIP_LOGIC = true;
FLIP_OVERRIDE_FACTOR = 0.0;  % Set to 0 for pure controller comparison
FlipLimits.Pan = 90;
FlipLimits.Tilt = 90;

% Location
lat = 41.0082; lon = 28.9784; tz = 3;
SimDate = datetime(2024, 6, 21, 5, 0, 0);
SunDistance = 1.0;
SensorApexAngle = 120;

% Time
time_vector = 0 : dt_physics : duration_sec;
num_steps = length(time_vector);

%% ════════════════════════════════════════════════════════════════════════════
%% BUILD RUN LIST (depends on PHYSICS_MODEL setting)
%% ════════════════════════════════════════════════════════════════════════════

if strcmp(PHYSICS_MODEL, 'BOTH')
    % Run all 4 combinations
    run_physics = {'SIMPLE', 'SIMPLE', 'COMPLEX', 'COMPLEX'};
    run_ctrls   = {'pid',   'fuzzy',  'pid',     'fuzzy'};
    run_labels  = {'SIMPLE+PID', 'SIMPLE+FLC', 'COMPLEX+PID', 'COMPLEX+FLC'};
    run_keys    = {'SIMPLE_pid','SIMPLE_fuzzy','COMPLEX_pid','COMPLEX_fuzzy'};
    run_colors  = {[0 0.4 0.8], [0 0.7 0.3], [0.9 0.2 0], [0.8 0.4 0.9]};
else
    % Run 2 controllers on selected physics model
    run_physics = {PHYSICS_MODEL, PHYSICS_MODEL};
    run_ctrls   = {'pid', 'fuzzy'};
    run_labels  = {sprintf('%s+PID', PHYSICS_MODEL), sprintf('%s+FLC', PHYSICS_MODEL)};
    run_keys    = {'pid', 'fuzzy'};
    run_colors  = {[0 0.4 0.8], [0.9 0.2 0]};
end

num_runs = length(run_ctrls);

%% ════════════════════════════════════════════════════════════════════════════
%% RUN SIMULATIONS
%% ════════════════════════════════════════════════════════════════════════════

% Supervisor parameters (shared — single source of truth)
SupervisorParams = struct();
SupervisorParams.night_threshold  = PID_Params.night_threshold;
SupervisorParams.search_speed     = PID_Params.search_speed;
SupervisorParams.zenith_pan_lock  = PID_Params.zenith_pan_lock;
SupervisorParams.rate_filter_alpha = 0.3;

Results = struct();
Metrics = struct();

for r = 1:num_runs
    phys = run_physics{r};
    mode = run_ctrls{r};
    key  = run_keys{r};
    fprintf('\n═══ [%d/%d] Running %s... ═══\n', r, num_runs, run_labels{r});

    % Reset states
    StatePan = struct('Angle', 0, 'Velocity', 0, 'Current', 0);
    StateTilt = struct('Angle', 0, 'Velocity', 0, 'Current', 0);

    if strcmp(SCENARIO, 'ZENITH_STATIC')
        StatePan.Angle = 45.0; StateTilt.Angle = 2.0;
    elseif strcmp(SCENARIO, 'FLIP_BOUNDARY')
        StatePan.Angle = 10.0; StateTilt.Angle = 45.0;
    end

    FSM_State = struct('mode', 'TRACKING', 'e_pan_prev', 0, 'e_tilt_prev', 0, ...
                       'de_pan_filtered', 0, 'de_tilt_filtered', 0, 'search_phase', 0);
    ControlState = struct('I_pan', 0, 'I_tilt', 0);
    CommandSmoothing = struct('target_pan_smoothed', 0, 'target_tilt_smoothed', 0);
    flip_state = struct('is_flipped', false, 'flip_count', 0, 'last_flip_time', -inf);

    % Preallocate
    Log.Time = time_vector;
    Log.TargetPan = zeros(num_steps, 1); Log.ActualPan = zeros(num_steps, 1);
    Log.TargetTilt = zeros(num_steps, 1); Log.ActualTilt = zeros(num_steps, 1);
    Log.ServoVelPan = zeros(num_steps, 1); Log.ServoVelTilt = zeros(num_steps, 1);
    Log.I_Pan = zeros(num_steps, 1); Log.I_Tilt = zeros(num_steps, 1);
    Log.IsFlip = zeros(num_steps, 1);
    Log.E_deg_Pan = zeros(num_steps, 1); Log.E_deg_Tilt = zeros(num_steps, 1);
    Log.Incidence = zeros(num_steps, 1); Log.IsLocked = zeros(num_steps, 1);
    Log.Power_Pan = zeros(num_steps, 1); Log.Power_Tilt = zeros(num_steps, 1);
    Log.Power_Total = zeros(num_steps, 1);
    Log.Irradiance = zeros(num_steps, 1);
    Log.SolarPower = zeros(num_steps, 1);
    Log.LockCounter = zeros(num_steps, 1);

    is_flip = false;
    target_pan = 0; target_tilt = 0;

    % Simulation loop (headless - no graphics)
    for i = 1:num_steps
        current_time = SimDate + seconds(time_vector(i));
        sim_time_elapsed = time_vector(i);

        % Sun position
        if TEST_MODE
            angle_phi = spiral_speed * sim_time_elapsed;
            angle_alpha = 90 - (spiral_widen * sim_time_elapsed);
            if angle_alpha < 0, angle_alpha = 0; end
            az = deg2rad(angle_phi);
            el = deg2rad(angle_alpha);
            S_vec = [cos(el)*cos(az); cos(el)*sin(az); sin(el)];
            elevation_sun = angle_alpha;
        else
            [S_vec, ~, ~] = getSunVector(lat, lon, current_time, tz);
            elevation_sun = asind(S_vec(3));
        end

        % Control update
        if mod(i-1, control_decimation) == 0
            theta_pan_curr = StatePan.Angle;
            theta_tilt_curr = StateTilt.Angle;

            cp = cosd(theta_pan_curr); sp = sind(theta_pan_curr);
            ct = cosd(theta_tilt_curr); st = sind(theta_tilt_curr);
            Sx_rz = cp*S_vec(1) - sp*S_vec(2);
            Sy_rz = sp*S_vec(1) + cp*S_vec(2);
            Sz_rz = S_vec(3);
            S_body_pre = [ct*Sx_rz - st*Sz_rz; Sy_rz; st*Sx_rz + ct*Sz_rz];
            S_body_norm = S_body_pre / (norm(S_body_pre) + 1e-8);

            [~, LDR_V_ctrl, ~, ~] = readLDRs(S_body_norm, SensorApexAngle);

            [azimuth_sun, elevation_sun_sph] = cartesian2spherical(S_vec);
            ideal_pan = azimuth_sun;
            ideal_tilt = max(-90, min(90, 90 - elevation_sun_sph));
            if ideal_pan > 180, ideal_pan = ideal_pan - 360; end

            if USE_FLIP_LOGIC
                [adj_pan, adj_tilt, is_flip, is_reachable] = ...
                    applyFlipLogic(ideal_pan, ideal_tilt, FlipLimits);
            else
                adj_pan = ideal_pan; adj_tilt = ideal_tilt;
                is_flip = false; is_reachable = true;
            end

            %% ═══ BLOCK A: SUPERVISOR (StateManagerFSM) ═══
            [ErrorSignal, FSM_State, ~] = StateManagerFSM(...
                LDR_V_ctrl, S_body_pre, theta_pan_curr, theta_tilt_curr, ...
                FSM_State, SupervisorParams, dt_control, is_flip);

            %% ═══ BLOCK B: CONTROLLER (Swappable) ═══
            if strcmp(mode, 'fuzzy')
                [VelCmd, ControlState, ~] = FuzzyLogicController(...
                    ErrorSignal, ControlState, FLC_Params, dt_control);
                sa = FLC_Params.smooth_alpha;
            else
                [VelCmd, ControlState, ~] = PID_VelocityController(...
                    ErrorSignal, ControlState, PID_Params, dt_control);
                sa = PID_Params.smooth_alpha;
            end

            %% ═══ VELOCITY → POSITION INTEGRATION ═══
            pan_limit_val = getFieldOrDefault_pf(PID_Params, 'pan_limit', 180);
            tgt_pan  = theta_pan_curr  + VelCmd.v_pan  * dt_control;
            tgt_tilt = theta_tilt_curr + VelCmd.v_tilt * dt_control;
            tgt_pan  = max(-pan_limit_val, min(pan_limit_val, tgt_pan));
            tgt_tilt = max(-90, min(90, tgt_tilt));

            % Blend with flip logic
            if is_reachable && USE_FLIP_LOGIC && FLIP_OVERRIDE_FACTOR > 0
                target_pan = tgt_pan + FLIP_OVERRIDE_FACTOR * (adj_pan - tgt_pan);
                target_tilt = tgt_tilt + FLIP_OVERRIDE_FACTOR * (adj_tilt - tgt_tilt);
            else
                target_pan = tgt_pan;
                target_tilt = tgt_tilt;
            end

            % Smoothing
            CommandSmoothing.target_pan_smoothed = (1-sa)*CommandSmoothing.target_pan_smoothed + sa*target_pan;
            CommandSmoothing.target_tilt_smoothed = (1-sa)*CommandSmoothing.target_tilt_smoothed + sa*target_tilt;
        end

        target_pan_smooth = CommandSmoothing.target_pan_smoothed;
        target_tilt_smooth = CommandSmoothing.target_tilt_smoothed;

        % Physics dispatch (SIMPLE, COMPLEX, or THEORETICAL)
        if strcmp(phys, 'COMPLEX')
            [StatePan, ~]  = stepDCMotorPhysics(StatePan, target_pan_smooth, MotorProps, dt_physics, 'Pan');
            [StateTilt, ~] = stepDCMotorPhysics(StateTilt, target_tilt_smooth, MotorProps, dt_physics, 'Tilt');
        elseif strcmp(phys, 'THEORETICAL')
            [StatePan, ~]  = stepTheoreticalServo(StatePan, target_pan_smooth, TheoreticalProps, dt_physics, 'Pan');
            [StateTilt, ~] = stepTheoreticalServo(StateTilt, target_tilt_smooth, TheoreticalProps, dt_physics, 'Tilt');
        else
            [StatePan, ~] = stepAdvancedServoPhysics(StatePan, target_pan_smooth, ServoProps, dt_physics, 'Pan');
            [StateTilt, ~] = stepAdvancedServoPhysics(StateTilt, target_tilt_smooth, ServoProps, dt_physics, 'Tilt');
        end

        theta_pan = StatePan.Angle;
        theta_tilt = StateTilt.Angle;

        % Logging
        Log.TargetPan(i) = target_pan; Log.ActualPan(i) = theta_pan;
        Log.TargetTilt(i) = target_tilt; Log.ActualTilt(i) = theta_tilt;
        Log.ServoVelPan(i) = abs(StatePan.Velocity);
        Log.ServoVelTilt(i) = abs(StateTilt.Velocity);
        Log.I_Pan(i) = StatePan.Current;
        Log.I_Tilt(i) = StateTilt.Current;
        Log.IsFlip(i) = is_flip;

        % Recompute body-frame for logging
        cp2 = cosd(theta_pan); sp2 = sind(theta_pan);
        ct2 = cosd(theta_tilt); st2 = sind(theta_tilt);
        Sx2 = cp2*S_vec(1) - sp2*S_vec(2);
        Sz2 = S_vec(3);
        Sb = [ct2*Sx2 - st2*Sz2; sp2*S_vec(1)+cp2*S_vec(2); st2*Sx2 + ct2*Sz2];
        Sb = Sb / (norm(Sb) + 1e-8);

        [E_pan, E_tilt, E_deg_pan, E_deg_tilt, ldr_locked] = controlLDR(...
            LDR_V_ctrl(1), LDR_V_ctrl(2), LDR_V_ctrl(3), LDR_V_ctrl(4), Sb);
        Log.E_deg_Pan(i) = E_deg_pan;
        Log.E_deg_Tilt(i) = E_deg_tilt;
        Log.IsLocked(i) = ldr_locked;

        [theta_inc, ~] = checkAlignment(Sb);
        Log.Incidence(i) = theta_inc;

        Log.Power_Pan(i) = StatePan.Current * SUPPLY_VOLTAGE;
        Log.Power_Tilt(i) = StateTilt.Current * SUPPLY_VOLTAGE;
        Log.Power_Total(i) = Log.Power_Pan(i) + Log.Power_Tilt(i);

        sun_el_rad = deg2rad(elevation_sun);
        irradiance = 1000 * max(0, sin(sun_el_rad));
        Log.Irradiance(i) = irradiance;
        panel_area = 0.05;
        Log.SolarPower(i) = irradiance * panel_area * 0.15;

        if theta_inc < PID_Params.lock_threshold
            Log.LockCounter(i) = 1;
        end
    end

    % Store results
    Results.(key) = Log;

    % Compute metrics
    lock_pct = sum(Log.LockCounter) / num_steps * 100;
    mean_inc = mean(Log.Incidence);
    max_inc = max(Log.Incidence);

    total_energy_used = sum(Log.Power_Total) * dt_physics / 3600;
    total_energy_solar = sum(Log.SolarPower) * dt_physics / 3600;

    cos_inc = cosd(Log.Incidence);
    harvested_power = Log.SolarPower(:) .* cos_inc(:);
    total_harvested = sum(harvested_power) * dt_physics / 3600;
    net_energy = total_harvested - total_energy_used;

    fprintf('  Mean incidence:   %.3f°\n', mean_inc);
    fprintf('  Max incidence:    %.3f°\n', max_inc);
    fprintf('  Lock time:        %.1f%%\n', lock_pct);
    fprintf('  Energy used:      %.4f Wh\n', total_energy_used);
    fprintf('  Energy harvested: %.4f Wh\n', total_harvested);
    fprintf('  Net energy:       %.4f Wh\n', net_energy);

    Metrics.(key).mean_incidence = mean_inc;
    Metrics.(key).max_incidence = max_inc;
    Metrics.(key).lock_pct = lock_pct;
    Metrics.(key).energy_used = total_energy_used;
    Metrics.(key).energy_harvested = total_harvested;
    Metrics.(key).net_energy = net_energy;
    Metrics.(key).settling_idx = find(Log.Incidence < 0.1, 1);
    if isempty(Metrics.(key).settling_idx)
        Metrics.(key).settling_time = duration_sec;
    else
        Metrics.(key).settling_time = Log.Time(Metrics.(key).settling_idx);
    end
end

%% ════════════════════════════════════════════════════════════════════════════
%% COMPARISON PLOTS
%% ════════════════════════════════════════════════════════════════════════════

fprintf('\n\nGenerating comparison plots...\n');

results_dir = 'Results';
if ~isfolder(results_dir), mkdir(results_dir); end
timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
compare_dir = fullfile(results_dir, sprintf('COMPARE_%s_%s_%s', SCENARIO, PHYSICS_MODEL, timestamp));
mkdir(compare_dir);

T = time_vector / 3600;  % hours

%% FIGURE 1: TRACKING ACCURACY COMPARISON
figure('Name', 'Tracking Accuracy Comparison', 'Position', [50 50 1400 900]);

subplot(3,2,1); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, R.ActualPan, '-', 'LineWidth', 1.5, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
plot(T, Results.(run_keys{1}).TargetPan, 'k--', 'LineWidth', 0.8, 'DisplayName', 'Target');
title('Pan Angle', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Angle (°)'); grid on;

subplot(3,2,2); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, R.ActualTilt, '-', 'LineWidth', 1.5, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
plot(T, Results.(run_keys{1}).TargetTilt, 'k--', 'LineWidth', 0.8, 'DisplayName', 'Target');
title('Tilt Angle', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Angle (°)'); grid on;

subplot(3,2,3); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, R.Incidence, '-', 'LineWidth', 1.5, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
yline(0.5, 'g--', 'Lock (0.5°)', 'LineWidth', 1.5);
yline(1.0, 'k--', 'Target (1.0°)', 'LineWidth', 1);
title('Incidence Angle', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('θ_{inc} (°)'); grid on;

subplot(3,2,4); hold on;
win = max(1, round(num_steps * 0.01));
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, movmean(R.Incidence, win), '-', 'LineWidth', 2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
yline(0.5, 'g--', 'Lock', 'LineWidth', 1);
title('Incidence Angle (Moving Average)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('θ_{inc} (°)'); grid on;

subplot(3,2,5); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, R.E_deg_Pan, '-', 'LineWidth', 1.2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
yline(0, 'k--', 'LineWidth', 0.5);
title('Pan Error (LDR)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Error (°)'); xlabel('Time (hours)'); grid on;

subplot(3,2,6); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, R.E_deg_Tilt, '-', 'LineWidth', 1.2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
yline(0, 'k--', 'LineWidth', 0.5);
title('Tilt Error (LDR)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Error (°)'); xlabel('Time (hours)'); grid on;

sgtitle(sprintf('TRACKING ACCURACY — %s (%s)', SCENARIO, PHYSICS_MODEL), 'FontSize', 14, 'FontWeight', 'bold');
saveas(gcf, fullfile(compare_dir, '01_Tracking_Accuracy.png'));

%% FIGURE 2: ENERGY COMPARISON
figure('Name', 'Energy Comparison', 'Position', [100 30 1400 900]);

% Power consumed
subplot(3,2,1); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, R.Power_Total, '-', 'LineWidth', 1.2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
title('Instantaneous Power Consumption', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Power (W)'); grid on;

% Cumulative energy consumed
subplot(3,2,2); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    cum_e = cumsum(R.Power_Total) * dt_physics / 3600;
    plot(T, cum_e, '-', 'LineWidth', 2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
title('Cumulative Energy Used', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Energy (Wh)'); grid on;

% Harvested power
subplot(3,2,3); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    harvest = R.SolarPower(:) .* cosd(R.Incidence(:));
    plot(T, harvest, '-', 'LineWidth', 1.2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
R1 = Results.(run_keys{1});
plot(T, R1.SolarPower, 'k--', 'LineWidth', 0.8, 'DisplayName', 'Available');
title('Harvested Solar Power', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Power (W)'); grid on;

% Cumulative harvested
subplot(3,2,4); hold on;
cum_available = cumsum(R1.SolarPower) * dt_physics / 3600;
for k = 1:num_runs
    R = Results.(run_keys{k});
    cum_h = cumsum(R.SolarPower(:) .* cosd(R.Incidence(:))) * dt_physics / 3600;
    plot(T, cum_h, '-', 'LineWidth', 2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
plot(T, cum_available, 'k--', 'LineWidth', 1, 'DisplayName', 'Available');
title('Cumulative Harvested Energy', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Energy (Wh)'); grid on;

% Net energy (harvested - consumed)
subplot(3,2,5); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    cum_h = cumsum(R.SolarPower(:) .* cosd(R.Incidence(:))) * dt_physics / 3600;
    cum_u = cumsum(R.Power_Total) * dt_physics / 3600;
    plot(T, cum_h - cum_u, '-', 'LineWidth', 2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
yline(0, 'k--', 'Break-even', 'LineWidth', 1);
title('Net Energy Balance (Harvested − Consumed)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Net Energy (Wh)'); xlabel('Time (hours)'); grid on;

% Servo velocities
subplot(3,2,6); hold on;
for k = 1:num_runs
    R = Results.(run_keys{k});
    plot(T, R.ServoVelPan + R.ServoVelTilt, '-', 'LineWidth', 1.2, 'Color', run_colors{k}, 'DisplayName', run_labels{k});
end
title('Total Servo Velocity (Pan + Tilt)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best'); ylabel('Velocity (°/s)'); xlabel('Time (hours)'); grid on;

sgtitle(sprintf('ENERGY ANALYSIS — %s (%s)', SCENARIO, PHYSICS_MODEL), 'FontSize', 14, 'FontWeight', 'bold');
saveas(gcf, fullfile(compare_dir, '02_Energy_Comparison.png'));

%% FIGURE 3: METRICS SUMMARY TABLE
figure('Name', 'Metrics Summary', 'Position', [150 100 1100 600]);
ax = axes('Visible', 'off');

metric_names = {'Mean Incidence (°)'; 'Max Incidence (°)'; 'Settling Time (s)';
                'Lock Time (%)'; 'Energy Used (Wh)'; 'Energy Harvested (Wh)';
                'Net Energy (Wh)'};

% Build value matrix
vals = zeros(length(metric_names), num_runs);
for k = 1:num_runs
    M = Metrics.(run_keys{k});
    vals(:,k) = [M.mean_incidence; M.max_incidence; M.settling_time;
                 M.lock_pct; M.energy_used; M.energy_harvested; M.net_energy];
end

y_start = 0.88;
dy = 0.09;

text(0.5, 0.97, sprintf('COMPARISON — %s (%s)', SCENARIO, PHYSICS_MODEL), ...
    'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
    'Units', 'normalized');

% Header
text(0.02, y_start, 'Metric', 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized');
x_pos = linspace(0.35, 0.85, num_runs);
for k = 1:num_runs
    text(x_pos(k), y_start, run_labels{k}, 'FontSize', 11, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'Units', 'normalized', 'Color', run_colors{k});
end

annotation('line', [0.01, 0.99], [y_start - 0.02, y_start - 0.02], 'Color', 'k', 'LineWidth', 1.5);

for m_idx = 1:length(metric_names)
    y = y_start - (m_idx * dy);
    text(0.02, y, metric_names{m_idx}, 'FontSize', 10, 'Units', 'normalized');
    for k = 1:num_runs
        text(x_pos(k), y, sprintf('%.4f', vals(m_idx, k)), 'FontSize', 10, ...
            'HorizontalAlignment', 'center', 'Units', 'normalized', 'Color', run_colors{k});
    end
end

saveas(gcf, fullfile(compare_dir, '03_Metrics_Summary.png'));

%% ════════════════════════════════════════════════════════════════════════════
%% CONSOLE SUMMARY
%% ════════════════════════════════════════════════════════════════════════════

fprintf('\n\n');
fprintf('╔══════════════════════════════════════════════════════════════════════╗\n');
fprintf('║              COMPARISON SUMMARY (%s, %s)                ║\n', SCENARIO, PHYSICS_MODEL);
fprintf('╠══════════════════════════════════════════════════════════════════════╣\n');

% Dynamic header
hdr = '║ Metric                  │';
for k = 1:num_runs
    hdr = [hdr, sprintf(' %12s │', run_labels{k})]; %#ok
end
fprintf('%s\n', hdr);

sep = '╠═════════════════════════╪';
for k = 1:num_runs
    sep = [sep, '══════════════╪']; %#ok
end
fprintf('%s\n', sep);

row_names = {'Mean Incidence (°)', 'Max Incidence (°)', 'Settling Time (s)', ...
             'Lock Time (%)', 'Energy Used (Wh)', 'Harvested (Wh)', 'Net Energy (Wh)'};
for m_idx = 1:length(row_names)
    row = sprintf('║ %-24s│', row_names{m_idx});
    for k = 1:num_runs
        row = [row, sprintf(' %12.4f │', vals(m_idx, k))]; %#ok
    end
    fprintf('%s\n', row);
end

fprintf('╚══════════════════════════════════════════════════════════════════════╝\n\n');
fprintf('✓ Plots saved to: %s\n\n', compare_dir);

%% ════════════════════════════════════════════════════════════════════════════
%% HELPER FUNCTIONS
%% ════════════════════════════════════════════════════════════════════════════

function [azimuth, elevation] = cartesian2spherical(S_vec)
    x = S_vec(1); y = S_vec(2); z = S_vec(3);
    norm_vec = norm(S_vec);
    if norm_vec > 0
        x = x / norm_vec; y = y / norm_vec; z = z / norm_vec;
    end
    azimuth = atan2d(y, x);
    if azimuth < 0, azimuth = azimuth + 360; end
    elevation = asind(z);
end

function [adjusted_pan, adjusted_tilt, is_flip, is_reachable] = applyFlipLogic(ideal_pan, ideal_tilt, limits)
    pan_lim = limits.Pan; tilt_lim = limits.Tilt;

    if (abs(ideal_pan) <= pan_lim) && (abs(ideal_tilt) <= tilt_lim)
        adjusted_pan = ideal_pan; adjusted_tilt = ideal_tilt;
        is_flip = false; is_reachable = true; return;
    end

    flip_pan = ideal_pan + 180;
    if flip_pan > 180, flip_pan = flip_pan - 360; end
    flip_tilt = -ideal_tilt;

    if (abs(flip_pan) <= pan_lim) && (flip_tilt >= -90) && (flip_tilt <= 90)
        adjusted_pan = flip_pan; adjusted_tilt = flip_tilt;
        is_flip = true; is_reachable = true; return;
    end

    adjusted_pan = max(-pan_lim, min(pan_lim, ideal_pan));
    adjusted_tilt = max(-tilt_lim, min(tilt_lim, ideal_tilt));
    is_flip = false; is_reachable = false;
end

function value = getFieldOrDefault_pf(s, field, default)
    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end
