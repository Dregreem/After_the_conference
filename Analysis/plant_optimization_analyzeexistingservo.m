clear; clc; close all;

%% ============================================================
% 1) BASE PARAMS & PHYSICAL CONSTANTS (SI UNITS)
% ============================================================
BaseParams.MaxTorque        = 0.35;      % Nm
BaseParams.Inertia          = 0.00015;   % kg*m^2
BaseParams.StaticFriction   = 0.02;      % Nm
BaseParams.DynamicFriction  = 0.015;     % Nm
BaseParams.DeadbandVelocity = 0.01;      % rad/s

% Conversion Factors
deg2rad = pi/180;
rad2deg = 180/pi;

% MODE A: Your Current Settings (High Gain)
BaseParams.ServoGain        = 3.8197;       % Proportional Gain (Nm/rad)
BaseParams.ViscousDamping   = 0.0359;  % Viscous Damping (Nms/rad)

% MODE B: Optimization Logic (For Thesis justification)
ErrorTarget_deg = 0.3; % Aiming for 0.3 deg to stay safely under 0.5 limit
ErrorTarget_rad = ErrorTarget_deg * deg2rad; 
Target_Zeta     = 0.75; % Critically/Sub-critically damped target

% Mode B Math Correction: K = Friction / Error Target
OptParams = BaseParams;
OptParams.ServoGain      = BaseParams.StaticFriction / ErrorTarget_rad; 
OptParams.ViscousDamping = 2 * Target_Zeta * sqrt(OptParams.ServoGain * BaseParams.Inertia);

%% ============================================================
% 2) DUAL-MODE STEP TEST
% ============================================================
dt = 0.0005; % Finer time step for numerical stability
T  = 2.0; 
time = 0:dt:T; 

TargetValue_deg = 45;
TargetValue_rad = TargetValue_deg * deg2rad;

% ---------- MODE A (Current) ----------
StateA.Angle = 0; 
StateA.Velocity = 0; 
AngleLogA = zeros(size(time));
PowerLogA = zeros(size(time));

for k = 1:length(time)
    [StateA, TorqueA] = stepTheoreticalServo(StateA, TargetValue_rad, BaseParams, dt);
    AngleLogA(k) = StateA.Angle * rad2deg; % Convert to degrees for logging
    PowerLogA(k) = abs(TorqueA * StateA.Velocity); % Mechanical Power
end
EnergyA = trapz(time, PowerLogA); 

% ---------- MODE B (Optimized) ----------
StateB.Angle = 0; 
StateB.Velocity = 0; 
AngleLogB = zeros(size(time));
PowerLogB = zeros(size(time));

for k = 1:length(time)
    [StateB, TorqueB] = stepTheoreticalServo(StateB, TargetValue_rad, OptParams, dt);
    AngleLogB(k) = StateB.Angle * rad2deg; % Convert to degrees for logging
    PowerLogB(k) = abs(TorqueB * StateB.Velocity);
end
EnergyB = trapz(time, PowerLogB);

%% ============================================================
% 3) STEADY-STATE ERROR & IAE ANALYSIS
% ============================================================
% Instantaneous Error (Degrees)
ErrorA = TargetValue_deg - AngleLogA;
ErrorB = TargetValue_deg - AngleLogB;

ss_error_A = abs(ErrorA(end));
ss_error_B = abs(ErrorB(end));

% Integral of Absolute Error (IAE) - Thesis Metric
IAE_A = trapz(time, abs(ErrorA));
IAE_B = trapz(time, abs(ErrorB));

%% ============================================================
% 4) REPORT
% ============================================================
fprintf('\n=========== THESIS SERVO AUDIT REPORT ===========\n');
fprintf('%-25s | %-12s | %-12s\n', 'Metric', 'Mode A', 'Mode B (Opt)');
fprintf('------------------------------------------------------------\n');
fprintf('%-25s | %-12.4f | %-12.4f\n', 'Servo Gain (K)', BaseParams.ServoGain, OptParams.ServoGain);
fprintf('%-25s | %-12.4f | %-12.4f\n', 'Viscous Damping (B)', BaseParams.ViscousDamping, OptParams.ViscousDamping);
fprintf('%-25s | %-12.4f | %-12.4f\n', 'Final SS Error (deg)', ss_error_A, ss_error_B);
fprintf('%-25s | %-12.6f | %-12.6f\n', 'Total Energy (J)', EnergyA, EnergyB);
fprintf('%-25s | %-12.4f | %-12.4f\n', 'Total IAE (deg*s)', IAE_A, IAE_B);
fprintf('%-25s | %-12s | %-12s\n', 'Precision Goal (<0.5)', ...
    mat2str(ss_error_A < 0.5), mat2str(ss_error_B < 0.5));

%% ============================================================
% 5) VISUALIZATION
% ============================================================
figure('Color', 'w', 'Position', [100, 100, 1200, 400]);

% Subplot 1: Position
subplot(1,3,1);
plot(time, TargetValue_deg*ones(size(time)), 'k--', 'LineWidth', 1.2); hold on;
plot(time, AngleLogA, 'r', 'LineWidth', 1.5);
plot(time, AngleLogB, 'b', 'LineWidth', 1.5);
grid on; xlabel('Time (s)'); ylabel('Angle (deg)');
title('Position Step Response');
legend('Target', 'Mode A', 'Mode B', 'Location','southeast');

% Subplot 2: Error (Angle Difference)
subplot(1,3,2);
plot(time, ErrorA, 'r', 'LineWidth', 1.5); hold on;
plot(time, ErrorB, 'b', 'LineWidth', 1.5);
yline(0.5, 'g--', 'Threshold (0.5°)');
grid on; xlabel('Time (s)'); ylabel('Error (deg)');
title('Instantaneous Tracking Error');
ylim([-2, 5]); % Zoomed in to see the settling behavior

% Subplot 3: Power
subplot(1,3,3);
plot(time, PowerLogA, 'r', 'LineWidth', 1.5); hold on;
plot(time, PowerLogB, 'b', 'LineWidth', 1.5);
grid on; xlabel('Time (s)'); ylabel('Power (W)');
title('Mechanical Power');

%% ============================================================
% 6) HELPER FUNCTION: SERVO PHYSICS ENGINE
% ============================================================
function [nextState, torque] = stepTheoreticalServo(state, target_rad, p, dt)
    % 1. Proportional Control
    error_rad = target_rad - state.Angle;
    torque_cmd = error_rad * p.ServoGain;
    
    % Apply Max Torque Saturation
    torque = max(min(torque_cmd, p.MaxTorque), -p.MaxTorque);
    
    % 2. Resistance (Viscous Damping)
    damping_force = p.ViscousDamping * state.Velocity;
    
    % 3. Friction Logic & Newton's Second Law
    if abs(state.Velocity) < p.DeadbandVelocity
        % MOTOR IS STOPPED (Stiction phase)
        if abs(torque) <= p.StaticFriction
            % Torque cannot break static friction. Motor stays locked.
            acceleration = 0;
            nextState.Velocity = 0; 
        else
            % Torque breaks static friction
            resistance = sign(torque) * p.StaticFriction + damping_force;
            acceleration = (torque - resistance) / p.Inertia;
            nextState.Velocity = state.Velocity + acceleration * dt;
        end
    else
        % MOTOR IS MOVING (Dynamic friction phase)
        resistance = sign(state.Velocity) * p.DynamicFriction + damping_force;
        acceleration = (torque - resistance) / p.Inertia;
        nextState.Velocity = state.Velocity + acceleration * dt;
    end
    
    % 4. Integration for Position
    nextState.Angle = state.Angle + nextState.Velocity * dt;
end