%% ═══════════════════════════════════════════════════════════════════════════
%% COMPARE_MODELS.m - Full 3×2 Physics × Controller Comparison
%% ═══════════════════════════════════════════════════════════════════════════
%
% PURPOSE:
%   Run ALL 6 combinations of [SIMPLE/COMPLEX/THEORETICAL] × [PI/FLC] on the same
%   scenario and produce comprehensive A/B comparison.
%
% COMBINATIONS:
%   1. SIMPLE  + PI      (Baseline - Ideal servo)
%   2. SIMPLE  + FLC
%   3. COMPLEX + PI      (DC Motor dynamics)
%   4. COMPLEX + FLC     
%   5. THEORETICAL + PI  (Pure 2nd-order nonlinear friction)
%   6. THEORETICAL + FLC
%
% USAGE:
%   >> compare_models
%
% Author: Antigravity AI (for Kerem Bayer's thesis)
% Date: 2026-02-20

clear; clc; close all;
addpath(genpath(pwd));

fprintf('╔════════════════════════════════════════════════════════════════════╗\n');
fprintf('║  FULL COMPARISON: 3 Physics × 2 Controllers = 6 Configurations  ║\n');
fprintf('╚════════════════════════════════════════════════════════════════════╝\n\n');

%% ═══════════════════════════════════════════════════════════════════════════
%% CONFIGURATION
%% ═══════════════════════════════════════════════════════════════════════════

SCENARIO = 'REALISTIC';   % Change this to test different scenarios
Scenario = generateScenario(SCENARIO);

spiral_speed = Scenario.spiral_speed;
spiral_widen = Scenario.spiral_widen;
duration_sec = Scenario.duration_sec;

dt_physics = 0.01;
dt_control = 0.01;
control_decimation = 1;
SUPPLY_VOLTAGE = 6.0;
SensorApexAngle = 120;

% PI Controller Parameters
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

% Simple Servo Props
ServoProps.MaxSpeed = 40;
ServoProps.Accel = 50;
ServoProps.Jerk = 200;

% Complex Motor Props (balanced — verified stable at dt=0.01)
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

% Theoretical servo (pure 2nd-order nonlinear friction model)
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
MotorProps.Backlash   = 0.0;

% Flip logic
USE_FLIP_LOGIC = true;
FLIP_OVERRIDE_FACTOR = 0.0;  % CRITICAL: Set to 0 so controllers are tested independently
                              % Old value 0.5 was blending 50% geometric ideal into both
                              % controllers, making PI and FLC produce identical outputs
FlipLimits.Pan = 90;
FlipLimits.Tilt = 90;

% Location
lat = 41.0082; lon = 28.9784; tz = 3;
SimDate = datetime(2024, 6, 21, 5, 0, 0);
TEST_MODE = true;

%% ═══════════════════════════════════════════════════════════════════════════
%% RUN ALL 6 COMBINATIONS
%% ═══════════════════════════════════════════════════════════════════════════

physics_models   = {'SIMPLE', 'COMPLEX', 'THEORETICAL'};
controllers      = {'pid', 'fuzzy'};
ctrl_labels      = {'PID', 'FLC'};

% Color map for the 6 combinations
colors = { ...
    [0.0 0.4 0.8],  ... % SIMPLE+PI      = Blue
    [0.0 0.7 0.3],  ... % SIMPLE+FLC     = Green
    [0.9 0.2 0.0],  ... % COMPLEX+PI     = Red
    [0.8 0.4 0.9],  ... % COMPLEX+FLC    = Purple
    [1.0 0.5 0.0],  ... % THEORETICAL+PI = Orange
    [0.5 0.0 0.8]   ... % THEORETICAL+FLC = Dark Magenta
};

time_vector = 0 : dt_physics : duration_sec;
num_steps = length(time_vector);

% Supervisor parameters (shared — single source of truth)
SupervisorParams = struct();
SupervisorParams.night_threshold  = PID_Params.night_threshold;
SupervisorParams.search_speed     = PID_Params.search_speed;
SupervisorParams.zenith_pan_lock  = PID_Params.zenith_pan_lock;
SupervisorParams.rate_filter_alpha = 0.3;

Results = struct();
Metrics = struct();
combo_names = {};
combo_idx = 0;

for p = 1:3
    phys = physics_models{p};
    for c = 1:2
        ctrl = controllers{c};
        combo_idx = combo_idx + 1;
        combo_key = sprintf('%s_%s', phys, ctrl);
        combo_names{combo_idx} = sprintf('%s + %s', phys, ctrl_labels{c});

        fprintf('━━━ [%d/6] Running %s + %s (controller=%s)... ', combo_idx, phys, ctrl_labels{c}, ctrl);

        % Reset states
        StatePan  = struct('Angle', 0, 'Velocity', 0, 'Current', 0);
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

        % Preallocate log
        Log.Time      = time_vector;
        Log.Incidence = zeros(num_steps, 1);
        Log.ErrPan    = zeros(num_steps, 1);
        Log.ErrTilt   = zeros(num_steps, 1);
        Log.VelPan    = zeros(num_steps, 1);
        Log.VelTilt   = zeros(num_steps, 1);
        Log.IPan      = zeros(num_steps, 1);
        Log.ITilt     = zeros(num_steps, 1);
        Log.ActPan    = zeros(num_steps, 1);
        Log.ActTilt   = zeros(num_steps, 1);
        Log.Lock      = zeros(num_steps, 1);
        Log.TargetPan = zeros(num_steps, 1);
        Log.TargetTilt= zeros(num_steps, 1);
        Log.Power     = zeros(num_steps, 1);
        Log.SolarPower= zeros(num_steps, 1);

        is_flip = false;
        target_pan = 0; target_tilt = 0;  %#ok

        for i = 1:num_steps
            sim_t = time_vector(i);

            % Sun position (spiral)
            angle_phi = spiral_speed * sim_t;
            angle_alpha = 90 - (spiral_widen * sim_t);
            if angle_alpha < 0, angle_alpha = 0; end

            az = deg2rad(angle_phi); el = deg2rad(angle_alpha);
            S_vec = [cos(el)*cos(az); cos(el)*sin(az); sin(el)];

            % Control update
            if mod(i-1, control_decimation) == 0
                cp = cosd(StatePan.Angle); sp = sind(StatePan.Angle);
                ct = cosd(StateTilt.Angle); st = sind(StateTilt.Angle);

                Sx_rz = cp*S_vec(1) - sp*S_vec(2);
                Sy_rz = sp*S_vec(1) + cp*S_vec(2);
                Sz_rz = S_vec(3);

                S_body = [ct*Sx_rz - st*Sz_rz; Sy_rz; st*Sx_rz + ct*Sz_rz];
                S_body = S_body / (norm(S_body) + 1e-8);

                [~, LDR_V, ~, ~] = readLDRs(S_body, SensorApexAngle);

                [az_sun, ~] = cartesian2spherical(S_vec);
                ideal_pan = az_sun;
                ideal_tilt = max(-90, min(90, 90 - angle_alpha));
                if ideal_pan > 180, ideal_pan = ideal_pan - 360; end

                if USE_FLIP_LOGIC
                    [adj_pan, adj_tilt, is_flip, is_reach] = applyFlipLogic(ideal_pan, ideal_tilt, FlipLimits);
                else
                    adj_pan = ideal_pan; adj_tilt = ideal_tilt; is_flip = false; is_reach = true;
                end

                %% ═══ BLOCK A: SUPERVISOR (StateManagerFSM) ═══
                [ErrorSignal, FSM_State, ~] = StateManagerFSM(...
                    LDR_V, S_body, StatePan.Angle, StateTilt.Angle, ...
                    FSM_State, SupervisorParams, dt_control, is_flip);

                %% ═══ BLOCK B: CONTROLLER (Swappable) ═══
                if strcmp(ctrl, 'fuzzy')
                    [VelCmd, ControlState, ~] = FuzzyLogicController(...
                        ErrorSignal, ControlState, FLC_Params, dt_control);
                    sa = FLC_Params.smooth_alpha;
                else
                    [VelCmd, ControlState, ~] = PID_VelocityController(...
                        ErrorSignal, ControlState, PID_Params, dt_control);
                    sa = PID_Params.smooth_alpha;
                end

                % Debug: print first controller output to verify differentiation
                if i == 1
                    fprintf('\n      [VERIFY] %s controller produced: v_pan=%.4f v_tilt=%.4f\n', ctrl, VelCmd.v_pan, VelCmd.v_tilt);
                end

                %% ═══ VELOCITY → POSITION INTEGRATION ═══
                pan_limit_val = getFieldOrDefault_cm(PID_Params, 'pan_limit', 180);
                tgt_pan  = StatePan.Angle  + VelCmd.v_pan  * dt_control;
                tgt_tilt = StateTilt.Angle + VelCmd.v_tilt * dt_control;
                tgt_pan  = max(-pan_limit_val, min(pan_limit_val, tgt_pan));
                tgt_tilt = max(-90, min(90, tgt_tilt));

                % Blend with flip logic (DISABLED for pure comparison)
                if is_reach && USE_FLIP_LOGIC && FLIP_OVERRIDE_FACTOR > 0
                    tgt_pan = tgt_pan + FLIP_OVERRIDE_FACTOR * (adj_pan - tgt_pan);
                    tgt_tilt = tgt_tilt + FLIP_OVERRIDE_FACTOR * (adj_tilt - tgt_tilt);
                end

                target_pan = tgt_pan;
                target_tilt = tgt_tilt;

                CommandSmoothing.target_pan_smoothed  = (1-sa)*CommandSmoothing.target_pan_smoothed  + sa*target_pan;
                CommandSmoothing.target_tilt_smoothed = (1-sa)*CommandSmoothing.target_tilt_smoothed + sa*target_tilt;
            end

            tp = CommandSmoothing.target_pan_smoothed;
            tt = CommandSmoothing.target_tilt_smoothed;

            % Physics dispatch
            if strcmp(phys, 'COMPLEX')
                [StatePan, ~]  = stepDCMotorPhysics(StatePan, tp, MotorProps, dt_physics, 'Pan');
                [StateTilt, ~] = stepDCMotorPhysics(StateTilt, tt, MotorProps, dt_physics, 'Tilt');
            elseif strcmp(phys, 'THEORETICAL')
                [StatePan, ~]  = stepTheoreticalServo(StatePan, tp, TheoreticalProps, dt_physics, 'Pan');
                [StateTilt, ~] = stepTheoreticalServo(StateTilt, tt, TheoreticalProps, dt_physics, 'Tilt');
            else
                [StatePan, ~]  = stepAdvancedServoPhysics(StatePan, tp, ServoProps, dt_physics, 'Pan');
                [StateTilt, ~] = stepAdvancedServoPhysics(StateTilt, tt, ServoProps, dt_physics, 'Tilt');
            end

            % Recompute body-frame for incidence
            cp2 = cosd(StatePan.Angle); sp2 = sind(StatePan.Angle);
            ct2 = cosd(StateTilt.Angle); st2 = sind(StateTilt.Angle);
            Sx2 = cp2*S_vec(1) - sp2*S_vec(2);
            Sz2 = S_vec(3);
            Sb = [ct2*Sx2 - st2*Sz2; sp2*S_vec(1) + cp2*S_vec(2); st2*Sx2 + ct2*Sz2];
            Sb = Sb / (norm(Sb) + 1e-8);

            [theta_inc, ~] = checkAlignment(Sb);

            % Log
            Log.Incidence(i) = theta_inc;
            Log.ErrPan(i)    = target_pan - StatePan.Angle;
            Log.ErrTilt(i)   = target_tilt - StateTilt.Angle;
            Log.VelPan(i)    = abs(StatePan.Velocity);
            Log.VelTilt(i)   = abs(StateTilt.Velocity);
            Log.IPan(i)      = StatePan.Current;
            Log.ITilt(i)     = StateTilt.Current;
            Log.ActPan(i)    = StatePan.Angle;
            Log.ActTilt(i)   = StateTilt.Angle;
            Log.TargetPan(i) = target_pan;
            Log.TargetTilt(i)= target_tilt;
            Log.Lock(i)      = (theta_inc < PID_Params.lock_threshold);
            Log.Power(i)     = (StatePan.Current + StateTilt.Current) * SUPPLY_VOLTAGE;

            sun_el_rad = deg2rad(angle_alpha);
            Log.SolarPower(i) = 1000 * max(0, sin(sun_el_rad)) * 0.05 * 0.15;
        end

        % Store
        Results.(combo_key) = Log;

        % Metrics
        M.mean_inc     = mean(Log.Incidence);
        M.max_inc      = max(Log.Incidence);
        M.lock_pct     = mean(Log.Lock) * 100;
        M.mean_power   = mean(Log.Power);
        M.energy_used  = sum(Log.Power) * dt_physics / 3600;
        settle_idx = find(Log.Incidence < 0.5, 1);
        if isempty(settle_idx), M.settle_time = duration_sec;
        else, M.settle_time = Log.Time(settle_idx); end
        ss_start = max(1, round(0.9*num_steps));
        M.ss_error = mean(Log.Incidence(ss_start:end));

        Metrics.(combo_key) = M;

        fprintf('Done | Mean θ=%.2f° | Lock=%.0f%%\n', M.mean_inc, M.lock_pct);
    end
end

%% ═══════════════════════════════════════════════════════════════════════════
%% RESULTS TABLE
%% ═══════════════════════════════════════════════════════════════════════════

combo_keys = {'SIMPLE_fsm', 'SIMPLE_fuzzy', 'COMPLEX_fsm', 'COMPLEX_fuzzy'};

fprintf('\n');
fprintf('┌─────────────────────────────────────────────────────────────────────────────────────────────────┐\n');
fprintf('│                    FULL COMPARISON: %s Scenario                                       │\n', SCENARIO);
fprintf('├──────────────────────┬──────────────┬──────────────┬──────────────┬──────────────────────────────┤\n');
fprintf('│ Metric               │ SIMPLE + PI  │ SIMPLE + FLC │ COMPLEX + PI │ COMPLEX + FLC              │\n');
fprintf('├──────────────────────┼──────────────┼──────────────┼──────────────┼──────────────────────────────┤\n');

m1=Metrics.SIMPLE_fsm; m2=Metrics.SIMPLE_fuzzy; m3=Metrics.COMPLEX_fsm; m4=Metrics.COMPLEX_fuzzy;

fprintf('│ Mean Incidence (°)   │ %10.3f   │ %10.3f   │ %10.3f   │ %10.3f                   │\n', m1.mean_inc, m2.mean_inc, m3.mean_inc, m4.mean_inc);
fprintf('│ Max Incidence (°)    │ %10.3f   │ %10.3f   │ %10.3f   │ %10.3f                   │\n', m1.max_inc, m2.max_inc, m3.max_inc, m4.max_inc);
fprintf('│ Settling Time (s)    │ %10.2f   │ %10.2f   │ %10.2f   │ %10.2f                   │\n', m1.settle_time, m2.settle_time, m3.settle_time, m4.settle_time);
fprintf('│ SS Error (°)         │ %10.4f   │ %10.4f   │ %10.4f   │ %10.4f                   │\n', m1.ss_error, m2.ss_error, m3.ss_error, m4.ss_error);
fprintf('│ Lock (%%)             │ %10.1f   │ %10.1f   │ %10.1f   │ %10.1f                   │\n', m1.lock_pct, m2.lock_pct, m3.lock_pct, m4.lock_pct);
fprintf('│ Mean Power (W)       │ %10.3f   │ %10.3f   │ %10.3f   │ %10.3f                   │\n', m1.mean_power, m2.mean_power, m3.mean_power, m4.mean_power);
fprintf('│ Energy Used (Wh)     │ %10.4f   │ %10.4f   │ %10.4f   │ %10.4f                   │\n', m1.energy_used, m2.energy_used, m3.energy_used, m4.energy_used);
fprintf('├──────────────────────┴──────────────┴──────────────┴──────────────┴──────────────────────────────┤\n');

% Verdict
if m3.mean_inc > m1.mean_inc * 1.3
    fprintf('│ ⚠️  COMPLEX+PI shows %.1f× worse tracking than SIMPLE+PI                                     │\n', m3.mean_inc/m1.mean_inc);
end
if m4.mean_inc < m3.mean_inc * 0.8
    fprintf('│ ✅ COMPLEX+FLC recovers %.0f%% of the performance loss vs COMPLEX+PI                           │\n', ...
        (1 - m4.mean_inc/m3.mean_inc)*100);
end
fprintf('└─────────────────────────────────────────────────────────────────────────────────────────────────┘\n\n');

%% ═══════════════════════════════════════════════════════════════════════════
%% FIGURE 1: INCIDENCE ANGLE COMPARISON (All 4)
%% ═══════════════════════════════════════════════════════════════════════════

figure('Name', 'Full Model Comparison', 'Position', [50 50 1500 1000], 'Color', 'w');

T = time_vector;

% 1. Incidence Angle — all 4
subplot(3,2,1); hold on;
for k = 1:4
    R = Results.(combo_keys{k});
    plot(T, R.Incidence, '-', 'LineWidth', 1.5, 'Color', colors{k}, 'DisplayName', combo_names{k});
end
yline(0.5, 'k--', 'Lock (0.5°)', 'LineWidth', 1);
yline(1.0, 'k:', 'Target (1.0°)', 'LineWidth', 1);
title('Incidence Angle (All Configurations)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('θ_{inc} (°)'); xlabel('Time (s)');
legend('Location', 'best'); grid on;

% 2. Moving average incidence
subplot(3,2,2); hold on;
win = max(1, round(num_steps * 0.02));
for k = 1:4
    R = Results.(combo_keys{k});
    plot(T, movmean(R.Incidence, win), '-', 'LineWidth', 2, 'Color', colors{k}, 'DisplayName', combo_names{k});
end
yline(0.5, 'k--', 'Lock', 'LineWidth', 1);
title('Incidence Angle (Moving Average)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('θ_{inc} (°)'); xlabel('Time (s)');
legend('Location', 'best'); grid on;

% 3. Pan Error
subplot(3,2,3); hold on;
for k = 1:4
    R = Results.(combo_keys{k});
    plot(T, R.ErrPan, '-', 'LineWidth', 1.2, 'Color', colors{k}, 'DisplayName', combo_names{k});
end
yline(0, 'k--', 'LineWidth', 0.5);
title('Pan Tracking Error', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Error (°)'); xlabel('Time (s)');
legend('Location', 'best'); grid on;

% 4. Tilt Error
subplot(3,2,4); hold on;
for k = 1:4
    R = Results.(combo_keys{k});
    plot(T, R.ErrTilt, '-', 'LineWidth', 1.2, 'Color', colors{k}, 'DisplayName', combo_names{k});
end
yline(0, 'k--', 'LineWidth', 0.5);
title('Tilt Tracking Error', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Error (°)'); xlabel('Time (s)');
legend('Location', 'best'); grid on;

% 5. Motor Current
subplot(3,2,5); hold on;
for k = 1:4
    R = Results.(combo_keys{k});
    plot(T, R.IPan, '-', 'LineWidth', 1.2, 'Color', colors{k}, 'DisplayName', combo_names{k});
end
title('Motor Current (Pan)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Current (A)'); xlabel('Time (s)');
legend('Location', 'best'); grid on;

% 6. Lock percentage (running)
subplot(3,2,6); hold on;
win2 = max(1, round(num_steps * 0.05));
for k = 1:4
    R = Results.(combo_keys{k});
    plot(T, movmean(R.Lock, win2)*100, '-', 'LineWidth', 2, 'Color', colors{k}, 'DisplayName', combo_names{k});
end
title('Lock Percentage (Moving Average)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Lock %'); xlabel('Time (s)'); ylim([0 105]);
legend('Location', 'best'); grid on;

sgtitle(sprintf('FULL COMPARISON — 2 Physics × 2 Controllers — %s', SCENARIO), ...
        'FontSize', 14, 'FontWeight', 'bold');

% Save
results_dir = 'Results';
if ~isfolder(results_dir), mkdir(results_dir); end
saveas(gcf, fullfile(results_dir, sprintf('COMPARE_FULL_%s.png', SCENARIO)));

%% ═══════════════════════════════════════════════════════════════════════════
%% FIGURE 2: BAR CHART SUMMARY
%% ═══════════════════════════════════════════════════════════════════════════

figure('Name', 'Metrics Bar Chart', 'Position', [100 100 1200 700], 'Color', 'w');

bar_data = [m1.mean_inc, m2.mean_inc, m3.mean_inc, m4.mean_inc;
            m1.settle_time, m2.settle_time, m3.settle_time, m4.settle_time;
            m1.lock_pct, m2.lock_pct, m3.lock_pct, m4.lock_pct;
            m1.mean_power, m2.mean_power, m3.mean_power, m4.mean_power];

metric_titles = {'Mean Incidence (°)', 'Settling Time (s)', 'Lock %', 'Mean Power (W)'};

for s = 1:4
    subplot(2,2,s);
    b = bar(bar_data(s,:));
    b.FaceColor = 'flat';
    for k = 1:4, b.CData(k,:) = colors{k}; end
    set(gca, 'XTickLabel', combo_names, 'XTickLabelRotation', 25, 'FontSize', 9);
    title(metric_titles{s}, 'FontSize', 12, 'FontWeight', 'bold');
    grid on;
end

sgtitle(sprintf('METRICS COMPARISON — %s', SCENARIO), 'FontSize', 14, 'FontWeight', 'bold');
saveas(gcf, fullfile(results_dir, sprintf('COMPARE_BARS_%s.png', SCENARIO)));

fprintf('✓ Comparison figures saved to Results/\n\n');

%% ═══════════════════════════════════════════════════════════════════════════
%% HELPER FUNCTIONS
%% ═══════════════════════════════════════════════════════════════════════════

function [azimuth, elevation] = cartesian2spherical(S_vec)
    x = S_vec(1); y = S_vec(2); z = S_vec(3);
    nv = norm(S_vec);
    if nv > 0, x = x/nv; y = y/nv; z = z/nv; end
    azimuth = atan2d(y, x);
    if azimuth < 0, azimuth = azimuth + 360; end
    elevation = asind(z);
end

function [adj_pan, adj_tilt, is_flip, is_reach] = applyFlipLogic(ideal_pan, ideal_tilt, limits)
    pan_lim = limits.Pan; tilt_lim = limits.Tilt;
    if (abs(ideal_pan) <= pan_lim) && (abs(ideal_tilt) <= tilt_lim)
        adj_pan = ideal_pan; adj_tilt = ideal_tilt;
        is_flip = false; is_reach = true; return;
    end
    flip_pan = ideal_pan + 180;
    if flip_pan > 180, flip_pan = flip_pan - 360; end
    flip_tilt = -ideal_tilt;
    if (abs(flip_pan) <= pan_lim) && (flip_tilt >= -90) && (flip_tilt <= 90)
        adj_pan = flip_pan; adj_tilt = flip_tilt;
        is_flip = true; is_reach = true; return;
    end
    adj_pan = max(-pan_lim, min(pan_lim, ideal_pan));
    adj_tilt = max(-tilt_lim, min(tilt_lim, ideal_tilt));
    is_flip = false; is_reach = false;
end

function value = getFieldOrDefault_cm(s, field, default)
    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end
