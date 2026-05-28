function [NextState, DebugData] = stepDCMotorPhysics(State, TargetAngle, dt, AxisType)
% STEPDCMOTORPHYSICS - 3rd-Order DC Motor Model (v3.1 — working)
%
% INTERNAL SERVO CONTROLLER:
%   Real servos use a potentiometer + H-bridge: the voltage is directly
%   proportional to the position error. This is NOT a feedforward estimate
%   but a high-gain proportional drive — exactly how MG996R works.
%
%   V_cmd = K_drive * (θ_target - θ_actual)
%   Clamped to [-V_supply, +V_supply]
%
% VERIFIED:
%   1° error → V=1.5V → I_ss=0.3A → T=0.03 > T_stiction(0.02) ✓ MOVES
%   5° error → V=7.5V → I_ss=1.5A → T=0.15 N·m (strong tracking)     ✓
%   τ_e = L/R = 10ms → visible lag at dt=0.01                          ✓
%   α_max = 0.24/0.002 = 120 rad/s² → Δω/step = 69°/s                 ✓

    %% 1. STATE INITIALIZATION
    if isfield(State, 'Angle') && isfinite(State.Angle)
        theta_deg = State.Angle;
    else
        theta_deg = 0;
    end
    if isfield(State, 'Velocity') && isfinite(State.Velocity)
        omega_dps = State.Velocity;
    else
        omega_dps = 0;
    end
    if isfield(State, 'Current') && isfinite(State.Current)
        I_arm = State.Current;
    else
        I_arm = 0;
    end

    %% 2. PARAMETERS — HARDCODED DEFAULTS (DC Motor Physics)
    % Electrical
    R_arm      = 5.0;          % Ω
    L_arm      = 0.05;         % H  (τ_e = L/R = 10ms)
    Ke         = 0.1;          % V·s/rad - Back-EMF constant
    Kt         = 0.1;          % N·m/A   - Torque constant
    V_supply   = 12.0;         % V   - Supply voltage

    % Mechanical
    J_total    = 0.002;        % kg·m²  - Geared servo + small panel
    B_viscous  = 0.01;         % N·m·s/rad - Viscous damping
    T_stiction = 0.02;         % N·m  - Stiction (causes PI steady-state error)
    T_coulomb  = 0.01;         % N·m  - Coulomb friction

    % Gravity (tilt only)
    m_load     = 0.3;          % kg   - Panel mass
    L_cg       = 0.05;         % m    - CG distance

    % Internal servo drive
    K_drive    = 1.5;          % V/deg - Internal servo proportional drive
    MaxSpeed   = 40.0;         % deg/s speed limit

    % Limits
    pan_limit  = 180;          % deg  mechanical limit
    Backlash   = 0.0;          % deg  (disabled for clean comparison)

    if strcmp(AxisType, 'Pan')
        LMin = -pan_limit; LMax = pan_limit;
    else
        LMin = -90; LMax = 90;
    end

    %% 3. INTERNAL SERVO CONTROLLER
    % Real servo: potentiometer senses position, H-bridge drives proportionally.
    % V_cmd = K_drive * posError (voltage proportional to position error)
    % This is physically how the MG996R works internally.
    posError = TargetAngle - theta_deg;
    V_cmd = K_drive * posError;
    V_cmd = max(-V_supply, min(V_supply, V_cmd));

    %% 4. ELECTRICAL DYNAMICS: L·(dI/dt) = V - IR - Ke·ω
    omega_rad = omega_dps * pi / 180;
    backEMF = Ke * omega_rad;

    dI_dt = (V_cmd - I_arm * R_arm - backEMF) / L_arm;

    % Clamp dI/dt for safety
    dI_dt = max(-200, min(200, dI_dt));

    % Integrate current
    I_new = I_arm + dI_dt * dt;

    % Current limit
    I_stall = V_supply / R_arm;
    I_new = max(-I_stall, min(I_stall, I_new));

    %% 5. TORQUE
    T_motor = Kt * I_new;
    T_damping = B_viscous * omega_rad;

    % Friction
    if abs(omega_rad) < 0.01  % Stiction zone
        T_applied = T_motor - T_damping;
        if abs(T_applied) < T_stiction
            T_friction = T_applied;  % Stuck
        else
            T_friction = sign(T_applied) * T_coulomb;  % Breakaway
        end
    else
        T_friction = sign(omega_rad) * T_coulomb;  % Sliding
    end

    % Gravity (tilt only)
    if strcmp(AxisType, 'Tilt')
        T_gravity = m_load * 9.81 * L_cg * sind(theta_deg);
    else
        T_gravity = 0;
    end

    T_wind = 0;  % FIX (BUG-3): Wind load not modeled in this simulation

    %% 6. MECHANICAL DYNAMICS
    T_net = T_motor - T_damping - T_friction - T_gravity - T_wind;
    alpha_rad = T_net / J_total;
    alpha_rad = max(-1000, min(1000, alpha_rad));  % Safety clamp

    %% 7. INTEGRATION
    omega_new_rad = omega_rad + alpha_rad * dt;
    omega_new_dps = omega_new_rad * 180 / pi;

    % Speed limit (represents gear + PWM saturation)
    omega_new_dps = max(-MaxSpeed, min(MaxSpeed, omega_new_dps));

    % Position update
    theta_new = theta_deg + omega_new_dps * dt;

    if Backlash > 0
        theta_new = theta_new + (rand() - 0.5) * 2 * Backlash;
    end

    %% 8. HARD LIMITS
    HitWall = false;
    if theta_new > LMax
        theta_new = LMax; omega_new_dps = 0; HitWall = true;
    elseif theta_new < LMin
        theta_new = LMin; omega_new_dps = 0; HitWall = true;
    end

    %% OUTPUT
    NextState.Angle    = theta_new;
    NextState.Velocity = omega_new_dps;
    NextState.Current  = abs(I_new);
    NextState.IntError = 0;

    %% DEBUG
    DebugData.Wind       = T_wind;
    DebugData.HitWall    = HitWall;
    DebugData.Error      = posError;
    DebugData.T_motor    = T_motor;
    DebugData.T_friction = T_friction;
    DebugData.T_gravity  = T_gravity;
    DebugData.T_net      = T_net;
    DebugData.V_cmd      = V_cmd;
    DebugData.I_arm      = I_new;
    DebugData.dI_dt      = dI_dt;
    DebugData.Alpha      = alpha_rad;
    DebugData.BackEMF    = backEMF;
end

function val = getParam(P, field, default)
    if isstruct(P) && isfield(P, field)
        val = P.(field);
    else
        val = default;
    end
end
