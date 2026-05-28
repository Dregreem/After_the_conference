function [NextState, DebugData, props] = stepTheoreticalServo( ...
    State, TargetAngle_deg, dt, AxisType)
% STEPTHEORETICALSERVO_V2
% Fully rad-consistent nonlinear 2nd-order servo plant
%
% Internal units:
%   Angle      -> rad
%   Velocity   -> rad/s
%   Accel      -> rad/s²
%   Torque     -> N·m
%
% External interface:
%   Angle, Velocity in DEG for compatibility with main simulation
%
% Numerics:
%   Semi-implicit Euler (symplectic) integration

%% ─────────────────────────────────────────────────────────────
%% 1) STATE INIT
%% ─────────────────────────────────────────────────────────────

if isempty(State) || ~isstruct(State)
    State = struct('Angle',0,'Velocity',0,'Current',0,'Energy',0);
end

Angle_rad     = deg2rad(getFieldOrDefault(State,'Angle',0));
Velocity_rad  = deg2rad(getFieldOrDefault(State,'Velocity',0));
Energy_total  = getFieldOrDefault(State,'Energy',0);

Target_rad = deg2rad(TargetAngle_deg);

%% ─────────────────────────────────────────────────────────────
%% 2) PARAMETERS (SI CONSISTENT) — HARDCODED DEFAULTS
%% ─────────────────────────────────────────────────────────────

MaxTorque        = 0.35;          % N⋅m
J                = 0.00015;       % kg⋅m²
B                = 0.01;          % N⋅m⋅s/rad (Viscous damping)
T_static         = 0.02;          % N⋅m (stiction)
T_dynamic        = 0.015;         % N⋅m (kinetic friction)
DeadbandVel      = 0.05;          % rad/s
ServoGain        = 5.0;           % Control command gain

% Electrical parameters (MG995R servo datasheet)
I_STALL          = 2.0;           % Stall current [A] at 6V (Typical is 1.5A - 2.5A)
I_NO_LOAD        = 0.17;          % Running current just to spin gears [A] (~170mA)
V_SUPPLY         = 6.0;           % Nominal supply voltage [V]

% Expose owned parameters via props struct
props = struct();
props.MaxTorque = MaxTorque;
props.Inertia = J;
props.ViscousDamping = B;
props.StaticFriction = T_static;
props.DynamicFriction = T_dynamic;
props.DeadbandVel = DeadbandVel;
props.ServoGain = ServoGain;
props.MaxSpeed = 300.0;  % Slew rate limit [deg/s]
props.I_stall = I_STALL;
props.V_supply = V_SUPPLY;

if nargin < 4 || isempty(AxisType)
    AxisType = 'Pan';
end

if strcmp(AxisType,'Pan')
    LimitMin = -pi;
    LimitMax = pi;
else
    LimitMin = -pi/2;
    LimitMax = pi/2;
end

%% ─────────────────────────────────────────────────────────────
%% STEP 1) RAW ERROR CALCULATION
%% ─────────────────────────────────────────────────────────────

Error_rad = Target_rad - Angle_rad;

%% ─────────────────────────────────────────────────────────────
%% STEP 2) DEADBAND ZEROING
%% ─────────────────────────────────────────────────────────────

if abs(Error_rad) < 1e-6  % ~0.0006 degrees
    Error_rad = 0;
end

%% ─────────────────────────────────────────────────────────────
%% STEP 3) PROPORTIONAL CONTROL EFFORT
%% ─────────────────────────────────────────────────────────────

u = ServoGain * Error_rad;

%% ─────────────────────────────────────────────────────────────
%% STEP 4) VOLTAGE SATURATION CLAMP TO ±1.0
%% ─────────────────────────────────────────────────────────────

u = max(-1.0, min(1.0, u));

%% ─────────────────────────────────────────────────────────────
%% STEP 5) STALL TORQUE MULTIPLICATION
%% ─────────────────────────────────────────────────────────────

TorqueMotor = u * MaxTorque;

%% ─────────────────────────────────────────────────────────────
%% STEP 6) NONLINEAR FRICTION & NET DYNAMICS
%% θ¨ = (Tmotor − Tfriction − Bω) / J
%% ─────────────────────────────────────────────────────────────

StictionEngaged = false;

if abs(Velocity_rad) < DeadbandVel
    % Possible stiction region
    if abs(TorqueMotor) < T_static
        % Locked (static equilibrium)
        TorqueFriction = TorqueMotor;
        StictionEngaged = true;
    else
        % Breakaway → dynamic friction
        TorqueFriction = sign(TorqueMotor) * T_dynamic;
    end
else
    % Sliding region
    TorqueFriction = sign(Velocity_rad) * T_dynamic;
end

ViscousTorque = B * Velocity_rad;

NetTorque = TorqueMotor - TorqueFriction - ViscousTorque;

AngularAccel = NetTorque / J;

%% ─────────────────────────────────────────────────────────────
%% STEP 7) VELOCITY INTEGRATION (Euler step - compute new velocity)
%% ─────────────────────────────────────────────────────────────

omega_new = Velocity_rad + AngularAccel * dt;

%% ─────────────────────────────────────────────────────────────
%% STEP 7b) SLEW RATE CLAMP (MaxSpeed = 300 °/s BEFORE position integration)
%% ─────────────────────────────────────────────────────────────

MAX_SPEED = 300.0;  % degrees/s
MAX_SPEED_RAD = deg2rad(MAX_SPEED);  % convert to rad/s

% Clamp velocity to ±MAX_SPEED using the specified formula
omega_new_clamped = max(-MAX_SPEED_RAD, min(MAX_SPEED_RAD, omega_new));

Velocity_rad = omega_new_clamped;

%% ─────────────────────────────────────────────────────────────
%% STEP 8) POSITION INTEGRATION
%% ─────────────────────────────────────────────────────────────

Angle_rad = Angle_rad + Velocity_rad * dt;

%% ─────────────────────────────────────────────────────────────
%% STEP 9) MECHANICAL STOP CLAMP WITH VELOCITY ZEROING AT WALL
%% ─────────────────────────────────────────────────────────────

HardStopHit = false;

if Angle_rad > LimitMax
    Angle_rad = LimitMax;
    Velocity_rad = 0;
    HardStopHit = true;
elseif Angle_rad < LimitMin
    Angle_rad = LimitMin;
    Velocity_rad = 0;
    HardStopHit = true;
end

%% ─────────────────────────────────────────────────────────────
%% STEP 10) CURRENT ESTIMATION (moved before energy)
%% ─────────────────────────────────────────────────────────────

if abs(omega_new) < 0.1 && abs(Error_rad) < deg2rad(0.1)
    % Truly stationary: FSM is in HOLD state. Motors de-energized.
    CurrentEstimate = 0.0;  
else
    % Motor is energized: Baseline spin current + effort-based load current
    CurrentEstimate = I_NO_LOAD + (abs(u) * (I_STALL - I_NO_LOAD)); 
end

%% ─────────────────────────────────────────────────────────────
%% STEP 11) ENERGY TRACKING (Physical P = V*I integration)
%% ─────────────────────────────────────────────────────────────

Energy_step = V_SUPPLY * CurrentEstimate * dt;   % P = V*I => E = P*dt [J]
Energy_total = Energy_total + Energy_step;

%% ─────────────────────────────────────────────────────────────
%% STEP 12) OUTPUT (Back to DEG)
%% ─────────────────────────────────────────────────────────────

NextState = struct( ...
    'Angle',    rad2deg(Angle_rad), ...
    'Velocity', rad2deg(Velocity_rad), ...
    'Current',  CurrentEstimate, ...
    'Energy',   Energy_total);

DebugData = struct( ...
    'TorqueMotor', TorqueMotor, ...
    'TorqueFriction', TorqueFriction, ...
    'ViscousTorque', ViscousTorque, ...
    'NetTorque', NetTorque, ...
    'Acceleration', AngularAccel, ...
    'Stiction_Engaged', StictionEngaged, ...
    'Hard_Stop_Hit', HardStopHit, ...
    'Control_Signal', u, ...
    'Error_rad', Error_rad);

% props already populated above with owned parameters
end

%% Utility
function value = getFieldOrDefault(S, fieldname, default)
if isstruct(S) && isfield(S,fieldname)
    value = S.(fieldname);
else
    value = default;
end
end