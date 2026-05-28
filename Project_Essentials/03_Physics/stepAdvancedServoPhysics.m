function [NextState, DebugData] = stepAdvancedServoPhysics(State, TargetAngle, dt, AxisType)
% STEPADVANCEDSERVOPHYSICS_OPTIMIZED - Simplified servo physics
    
    %% STATE INITIALIZATION
    if isfield(State, 'Angle') && isfinite(State.Angle)
        CurrentTheta = State.Angle;
    else
        CurrentTheta = 0;
    end
    
    if isfield(State, 'Velocity') && isfinite(State.Velocity)
        CurrentOmega = State.Velocity;
    else
        CurrentOmega = 0;
    end
    
    %% SERVO PARAMETERS — HARDCODED DEFAULTS (Simple Servo Physics)
    MaxSpeed = 40;             % deg/s speed limit
    Accel = 50;                % deg/s² acceleration
    StallCurrent = 2.5;        % A   max stall current
    pan_limit = 90;            % deg  mechanical pan range

    % Pan: -pan_limit to +pan_limit (usually ±90)
    % Tilt: -90 to +90 (half rotation)
    if strcmp(AxisType, 'Pan')
        LimitMin = -pan_limit;
        LimitMax = pan_limit;
    else
        LimitMin = -90;
        LimitMax = 90;
    end
    
    Backlash = 0.2;
    
    %% PROPORTIONAL VELOCITY CONTROL
    Error = TargetAngle - CurrentTheta;
    VelGain = 10;
    DesiredVelocity = Error * VelGain;
    DesiredVelocity = max(-MaxSpeed, min(MaxSpeed, DesiredVelocity));
    
    %% FIXED ACCELERATION PROFILE
    DiffVel = DesiredVelocity - CurrentOmega;
    MaxVelChange = Accel * dt;
    
    if abs(DiffVel) > MaxVelChange
        NewOmega = CurrentOmega + sign(DiffVel) * MaxVelChange;
    else
        NewOmega = DesiredVelocity;
    end
    
    %% POSITION UPDATE
    InternalTheta = CurrentTheta + NewOmega * dt;
    MechanicalNoise = (rand() - 0.5) * 2 * Backlash;
    ProposedTheta = InternalTheta + MechanicalNoise;
    
    %% HARD LIMITS
    HitWall = false;
    
    if ProposedTheta > LimitMax
        FinalTheta = LimitMax;
        HitWall = true;
        NewOmega = 0;
    elseif ProposedTheta < LimitMin
        FinalTheta = LimitMin;
        HitWall = true;
        NewOmega = 0;
    else
        FinalTheta = ProposedTheta;
    end
    
    %% CURRENT CALCULATION
    I_base = 0.25;
    I_move = abs(NewOmega) / MaxSpeed * 0.5;
    I_stall = 0;
    if HitWall && abs(Error) > 2.0
        I_stall = 2.0;
    end
    
    TotalCurrent = I_base + I_move + I_stall;
    TotalCurrent = min(StallCurrent, TotalCurrent);
    
    %% OUTPUT
    NextState.Angle = FinalTheta;
    NextState.Velocity = NewOmega;
    NextState.Current = TotalCurrent;
    NextState.IntError = 0;
    
    DebugData.Wind = 0;
    DebugData.HitWall = HitWall;
    DebugData.Error = Error;
end