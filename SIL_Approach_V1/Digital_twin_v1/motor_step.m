function [NextState, DebugData, props] = stepTheoreticalServo( ...
    State, PWM_command, dt, AxisType)
% STEPTHEORETICALSERVO - Pure electromechanical MG995R model.
%
% Girisler:
%   State       : struct {Angle [deg], Velocity [deg/s], Current [A], Energy [J]}
%   PWM_command : isaretli PWM [-1000, +1000] (STM32 timer compare value)
%                 Ic kontrol sinyali u = PWM_command/1000  -> [-1, +1]
%   dt          : zaman adimi [s]
%   AxisType    : 'Pan' veya 'Tilt'
%
% Mimari notu:
%   PI kontrolcu BU FONKSIYONDA YOK. Velocity-mode PI firmware tarafinda.
%   Motor saf elektromekanik bir blok: PWM -> tork -> ivme -> aci.

%% State init
if isempty(State) || ~isstruct(State)
    State = struct('Angle',0,'Velocity',0,'Current',0,'Energy',0);
end
Angle_rad    = deg2rad(getFieldOrDefault(State,'Angle',0));
Velocity_rad = deg2rad(getFieldOrDefault(State,'Velocity',0));
Energy_total = getFieldOrDefault(State,'Energy',0);

%% MG995R parametreleri (makale Table 1)
MaxTorque  = 0.35;        % N·m
J          = 1.5e-4;      % kg·m²
B          = 0.01;        % N·m·s/rad
T_static   = 0.02;        % N·m
T_dynamic  = 0.015;       % N·m
DeadbandVel= 0.05;        % rad/s
I_STALL    = 2.0;         % A
I_NO_LOAD  = 0.17;        % A
V_SUPPLY   = 6.0;         % V
MAX_SPEED  = 300.0;       % deg/s

%% Eksen limitleri — FIZIKSEL MG995R sinir (makale Tablo 1)
% Ayna haritalamasi applyFlipLogic.m icinde UPSTREAM yapilir; motor daima ±90°
% gorur. Bu, SIL → Asama 2 firmware co-simulation'da fiziksel hardware ile
% sinyal uyumunu garantiler.
LimitMin = -pi/2;
LimitMax =  pi/2;
% AxisType artik limit farki yaratmiyor; ileri kullanim icin props'a tasinabilir
% AxisType degiskeni props icin tutuluyor; limit fark yok

%% (1) PWM -> kontrol sinyali u
u = max(-1.0, min(1.0, double(PWM_command) / 1000.0));

%% (2) Motor torku
TorqueMotor = u * MaxTorque;

%% (3) Surtunme (stiction / kinetik) + viskoz
StictionEngaged = false;
if abs(Velocity_rad) < DeadbandVel
    if abs(TorqueMotor) < T_static
        TorqueFriction = TorqueMotor;            % stiction kilitliyor
        StictionEngaged = true;
    else
        TorqueFriction = sign(TorqueMotor) * T_dynamic;  % kopus
    end
else
    TorqueFriction = sign(Velocity_rad) * T_dynamic;
end
ViscousTorque = B * Velocity_rad;

%% (4) Dinamik, semi-implicit Euler
NetTorque    = TorqueMotor - TorqueFriction - ViscousTorque;
AngularAccel = NetTorque / J;
omega_new    = Velocity_rad + AngularAccel * dt;

% Slew rate clamp
MAX_SPEED_RAD = deg2rad(MAX_SPEED);
omega_new     = max(-MAX_SPEED_RAD, min(MAX_SPEED_RAD, omega_new));
Velocity_rad  = omega_new;

%% (5) Pozisyon entegrasyonu
Angle_rad = Angle_rad + Velocity_rad * dt;

%% (6) Mekanik limitler
HardStopHit = false;
if Angle_rad > LimitMax
    Angle_rad = LimitMax;  Velocity_rad = 0;  HardStopHit = true;
elseif Angle_rad < LimitMin
    Angle_rad = LimitMin;  Velocity_rad = 0;  HardStopHit = true;
end

%% (7) Akim - makale Eq. 9: I = I_nL + |u|*(I_stall - I_nL)
% PWM=0 iken H-bridge driver de-energize -> akim 0
if abs(u) < 1e-6
    CurrentEstimate = 0.0;
else
    CurrentEstimate = I_NO_LOAD + abs(u) * (I_STALL - I_NO_LOAD);
end

%% (8) Enerji
Energy_step  = V_SUPPLY * CurrentEstimate * dt;
Energy_total = Energy_total + Energy_step;

%% Cikti (deg birimine geri)
NextState = struct( ...
    'Angle',    rad2deg(Angle_rad), ...
    'Velocity', rad2deg(Velocity_rad), ...
    'Current',  CurrentEstimate, ...
    'Energy',   Energy_total);

DebugData = struct( ...
    'TorqueMotor',     TorqueMotor, ...
    'TorqueFriction',  TorqueFriction, ...
    'ViscousTorque',   ViscousTorque, ...
    'NetTorque',       NetTorque, ...
    'Acceleration',    AngularAccel, ...
    'Stiction_Engaged',StictionEngaged, ...
    'Hard_Stop_Hit',   HardStopHit, ...
    'Control_Signal',  u, ...
    'AxisType',        AxisType);

props = struct( ...
    'MaxTorque',      MaxTorque, ...
    'Inertia',        J, ...
    'ViscousDamping', B, ...
    'StaticFriction', T_static, ...
    'DynamicFriction',T_dynamic, ...
    'MaxSpeed',       MAX_SPEED, ...
    'I_stall',        I_STALL, ...
    'I_noload',       I_NO_LOAD, ...
    'V_supply',       V_SUPPLY);
end

function value = getFieldOrDefault(S, fieldname, default)
if isstruct(S) && isfield(S,fieldname)
    value = S.(fieldname);
else
    value = default;
end
end