function Config = loadSystemConfig()
% LOADSYSTEMCONFIG - Master configuration file for Solar Tracker Simulation
%
% ╔════════════════════════════════════════════════════════════════════════╗
% ║  COMPREHENSIVE SYSTEM CONFIGURATION (Single Source of Truth)           ║
% ║  All numerical parameters, except those from Scenario struct,          ║
% ║  are defined here. Controllers and Physics use these values.           ║
% ╚════════════════════════════════════════════════════════════════════════╝
%
% Returns:
%   Config - Master struct with all system parameters organized by domain
%
% Usage:
%   Config = loadSystemConfig();
%   dt = Config.Physics.dt;
%   V_supply = Config.Hardware.V_supply;
%
% NOTE: Parameters DO NOT conflict with:
%   - Controller internals (StateManagerFSM, FuzzyLogicController, etc.)
%   - Physics simulation (stepTheoreticalServo, stepDCMotorPhysics, etc.)
%   - These functions use getFieldOrDefault() and expect Params struct

fprintf('\n╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  Loading Master System Configuration...                      ║\n');
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

% ═══════════════════════════════════════════════════════════════════════════
% 1. PHYSICS & TIMING PARAMETERS
% ═══════════════════════════════════════════════════════════════════════════
Config.Physics.dt_physics          = 0.01;      % 10 ms physics timestep (s)
Config.Physics.dt_control          = 0.01;      % 10 ms control timestep (s)
Config.Physics.control_decimation  = 1;        % Control update every step

fprintf('✓ Physics: dt=%.3f s, decimation=%d\n', ...
    Config.Physics.dt_physics, Config.Physics.control_decimation);

% ═══════════════════════════════════════════════════════════════════════════
% 2. HARDWARE PARAMETERS (Electrical & Mechanical)
% ═══════════════════════════════════════════════════════════════════════════
Config.Hardware.V_supply           = 6.0;       % Supply voltage (V)
Config.Hardware.Servo_Kv           = 10.0;      % Servo feedback velocity gain
Config.Hardware.PanServo.dims      = [0.040, 0.020, 0.040];  % [L, W, H] (m)
Config.Hardware.TiltServo.dims     = [0.040, 0.020, 0.040];  % [L, W, H] (m)
Config.Hardware.LDR.apex_angle     = 120;       % LDR sensor cone angle (°)

fprintf('✓ Hardware: V=%.1f V, LDR apex=%.0f°\n', ...
    Config.Hardware.V_supply, Config.Hardware.LDR.apex_angle);

% ═══════════════════════════════════════════════════════════════════════════
% 3. LOCATION PARAMETERS (PARAMETERIZED - Edit below for other locations)
% ═══════════════════════════════════════════════════════════════════════════

% ──────────────────────────────────────────────────────────────────────────
% ISTANBUL (DEFAULT - Master's thesis location)
% ──────────────────────────────────────────────────────────────────────────
Config.Location.latitude           = 41.0082;   % °N
Config.Location.longitude          = 28.9784;   % °E
Config.Location.timezone           = 3;        % UTC+3
Config.Location.name               = 'Istanbul, Turkey';

% ──────────────────────────────────────────────────────────────────────────
% ALTERNATIVE LOCATIONS (UNCOMMENT TO USE):
% ──────────────────────────────────────────────────────────────────────────
% New York
% Config.Location.latitude           = 40.7128;
% Config.Location.longitude          = -74.0060;
% Config.Location.timezone           = -5;
% Config.Location.name               = 'New York, USA';

% Tokyo
% Config.Location.latitude           = 35.6762;
% Config.Location.longitude          = 139.6503;
% Config.Location.timezone           = 9;
% Config.Location.name               = 'Tokyo, Japan';

% Sydney
% Config.Location.latitude           = -33.8688;
% Config.Location.longitude          = 151.2093;
% Config.Location.timezone           = 10;
% Config.Location.name               = 'Sydney, Australia';

fprintf('✓ Location: %s (%.4f°, %.4f°, UTC%+d)\n', ...
    Config.Location.name, Config.Location.latitude, Config.Location.longitude, Config.Location.timezone);

% ═══════════════════════════════════════════════════════════════════════════
% 4. VISUALIZATION & DISPLAY PARAMETERS
% ═══════════════════════════════════════════════════════════════════════════
Config.Display.animation_delay     = 0.01;      % Frame delay (s)
Config.Display.draw_skip           = 5;        % Update graphics every N steps
Config.Display.sun_distance        = 1.0;      % Sun vector visualization scale
Config.Display.dome_radius         = 4;        % Celestial dome radius (m)

fprintf('✓ Display: skip=%d, dome_r=%.1f m\n', ...
    Config.Display.draw_skip, Config.Display.dome_radius);

% ═══════════════════════════════════════════════════════════════════════════
% 5. CONTROL ALGORITHM PARAMETERS (FSM & Flip Logic)
% ═══════════════════════════════════════════════════════════════════════════

% ──────────────────────────────────────────────────────────────────────────
% 5A. FLIP LOGIC (Dual-motion ambiguity resolution)
% ──────────────────────────────────────────────────────────────────────────
Config.Control.flip.enabled        = true;     % Enable flip detection
Config.Control.flip.override_factor = 0.5;     % Blend weight (0=control, 1=flip)
Config.Control.flip.pan_limit      = 90;      % Hardware limit (±°)
Config.Control.flip.tilt_limit     = 90;      % Hardware limit (±°)

% ──────────────────────────────────────────────────────────────────────────
% 5B. FSM SUPERVISOR THRESHOLDS
% ──────────────────────────────────────────────────────────────────────────
Config.Control.FSM.night_threshold      = 0.1;   % LDR voltage → night (V)
Config.Control.FSM.sun_lost_threshold   = 0.5;   % Total voltage → lost (V)
Config.Control.FSM.sun_found_threshold  = 1.0;   % Total voltage → found (V)
Config.Control.FSM.lock_threshold       = 0.5;   % Lock error threshold (°)
Config.Control.FSM.search_speed         = 3.0;   % Search mode velocity (°/s)
Config.Control.FSM.zenith_pan_lock      = true;  % Lock pan at zenith
Config.Control.FSM.rate_filter_alpha    = 0.3;   % Derivative LP filter factor

fprintf('✓ Control FSM: night=%.1f V, lock=%.1f°, search=%.1f °/s\n', ...
    Config.Control.FSM.night_threshold, Config.Control.FSM.lock_threshold, Config.Control.FSM.search_speed);

% ═══════════════════════════════════════════════════════════════════════════
% 6. SOLAR PANEL CONFIGURATION
% ═══════════════════════════════════════════════════════════════════════════

% ──────────────────────────────────────────────────────────────────────────
% DEFAULT: Small research-grade tracker panel
% ──────────────────────────────────────────────────────────────────────────
Config.Panel.area                  = 0.05;     % 0.05 m² (small test panel)
Config.Panel.efficiency            = 0.15;     % 15% (typical Si cells)
Config.Panel.name                  = 'Small research tracker panel (0.05 m²)';

% ──────────────────────────────────────────────────────────────────────────
% ALTERNATIVES (UNCOMMENT TO USE):
% ──────────────────────────────────────────────────────────────────────────
% Larger 1m² panel
% Config.Panel.area                  = 1.0;
% Config.Panel.efficiency            = 0.18;
% Config.Panel.name                  = 'Premium 1 m² monocrystalline';

% High-efficiency lab panel
% Config.Panel.area                  = 0.1;
% Config.Panel.efficiency            = 0.22;
% Config.Panel.name                  = 'Lab-grade high-efficiency panel';

fprintf('✓ Panel: %s (η=%.0f%%)\n', Config.Panel.name, Config.Panel.efficiency*100);

% ═══════════════════════════════════════════════════════════════════════════
% 7. CONTROLLER PARAMETERS (PI Velocity Control)
% ═══════════════════════════════════════════════════════════════════════════
% ⚠️  NOTE: These are DEFAULTS. Scenario-based gains override from generateScenario()
%           Do NOT change these unless testing new control architectures.
% ═══════════════════════════════════════════════════════════════════════════

% PI Velocity Control (used by PID_VelocityController and StateManagerFSM)
Config.Controller.Kp_vel                = 0.25;     % Proportional gain
Config.Controller.Ki_vel                = 0.04;     % Integral gain
Config.Controller.max_tracking_velocity = 15.0;     % deg/s (saturation limit)
Config.Controller.smooth_alpha          = 0.95;     % Command smoothing (0-1)
Config.Controller.deadzone              = 0.05;     % Error deadzone (°)
Config.Controller.max_integral          = 10;       % Anti-windup limit
Config.Controller.max_output            = 30;       % Output saturation (°/s)
Config.Controller.velocity_damping      = 0.10;     % Velocity feedback damping
Config.Controller.pan_limit             = 180;      % Pan range (±°)
Config.Controller.tilt_limit            = 90;       % Tilt range (±°)

fprintf('✓ Controller: Kp_vel=%.3f, Ki_vel=%.3f, max_vel=%.1f °/s\n', ...
    Config.Controller.Kp_vel, Config.Controller.Ki_vel, Config.Controller.max_tracking_velocity);

% ═══════════════════════════════════════════════════════════════════════════
% SUMMARY
% ═══════════════════════════════════════════════════════════════════════════
fprintf('\n✓ ✓ ✓ Master Configuration Loaded Successfully ✓ ✓ ✓\n');
fprintf('Total Parameters: %.0f domains organized\n\n', 7);

end
