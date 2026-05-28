function Scenario = generateScenario(scenario_name)
% GENERATESCENARIO - Creates scenario parameters for different test cases
% Based on MAIN_Simulation.m specifications (exact, no auto-scaling)
%
% Usage:
%   Scenario = generateScenario('EXTREME')

    % Default scenario
    if nargin < 1
        scenario_name = 'REALISTIC';
    end
    
    % Initialize temp struct for SOLAR_DAY specific parameters
    solar_day_params = struct();
    
    % Exact parameters from MAIN_Simulation.m (NO auto-scaling)
    switch upper(scenario_name)
        case 'REALISTIC'
            % Real sun motion (~0.25 deg/min)
            spiral_speed = 0.01;
            spiral_widen = 0.002;
            duration_sec = 300;     % 5 minutes
            fsm_tracking_deadband = 3.0;   % ° 0.14% optical loss, massive energy savings
            fsm_batch_interval    = 60.0;  % s 1-min batch interval — sensor check every 60s
            fsm_max_burst_time    = 2.0;   % s strict hardware interrupt, PID settles or sleeps
            
        case 'VEHICLE_SLOW'
            % 12× faster than sun (slow vehicle)
            spiral_speed = 0.05;
            spiral_widen = 0.01;
            duration_sec = 600;     % 10 minutes
            
        case 'VEHICLE_FAST'
            % 50× faster than sun (fast vehicle)
            spiral_speed = 0.2;
            spiral_widen = 0.05;
            duration_sec = 300;     % 5 minutes
            fsm_tracking_deadband = 0.5;   % ° very tight deadband
            fsm_batch_interval    = 5.0;   % s very short dwell
            fsm_max_burst_time    = 3.0;   % s short burst
            
        case 'ZENITH_STATIC'
            % Gimbal lock protection at zenith
            spiral_speed = 0.0;
            spiral_widen = 0.0;
            duration_sec = 60;      % 60 seconds
            
        case 'FLIP_BOUNDARY'
            % Flip transition smoothness (slow azimuth sweep, no elevation)
            spiral_speed = 0.1;
            spiral_widen = 0.0;
            duration_sec = 180;     % 3 minutes
            
        case 'EXTREME'
            % Ultra-fast stress test
            spiral_speed = 5.0;
            spiral_widen = 0.1;
            duration_sec = 1000;    % 16.7 minutes
            fsm_tracking_deadband = 1.0;   % ° tight deadband for fast sun
            fsm_batch_interval    = 15.0;  % s short dwell for fast sun
            fsm_max_burst_time    = 5.0;   % s short burst
            
        case 'SOLAR_DAY'
            % Real solar day tracking (uses actual sun position from getSunVector)
            spiral_speed = 0.0;     % No spiral - uses real sun
            spiral_widen = 0.0;
            duration_sec = (16.0 - 8.0) * 3600;  % 8 hours, 08:00 to 16:00
            fsm_tracking_deadband = 3.0;   % ° 0.14% optical loss, massive energy savings
            fsm_batch_interval    = 60.0;  % s 1-min batch interval — optimized for net yield
            fsm_max_burst_time    = 2.0;   % s strict hardware interrupt for energy optimization
            
            % Additional parameters for SOLAR_DAY analysis
            solar_day_params.use_real_sun   = true;
            solar_day_params.date           = datetime(2023, 6, 21);  % Summer solstice
            solar_day_params.t_start_hour   = 8.0;       % Simulation starts 08:00
            solar_day_params.t_end_hour     = 16.0;      % Simulation ends 16:00
            solar_day_params.pvgis_file     = 'pvgis_2023_file.csv';
            solar_day_params.analysis_mode  = 'SOLSTICE'; % 'SOLSTICE' or 'DAILY'
            solar_day_params.analysis_date  = datetime(2023, 6, 21);
            
        otherwise
            error('Unknown scenario: %s. Available: REALISTIC, VEHICLE_SLOW, VEHICLE_FAST, ZENITH_STATIC, FLIP_BOUNDARY, EXTREME, SOLAR_DAY', scenario_name);
    end
    
    % Create scenario struct with all parameters
    Scenario.name = scenario_name;
    Scenario.spiral_speed = spiral_speed;
    Scenario.spiral_widen = spiral_widen;
    Scenario.duration_sec = duration_sec;
    Scenario.use_real_sun = false;
    
    % Add FSM timing parameters if defined for this scenario
    if exist('fsm_tracking_deadband', 'var')
        Scenario.tracking_deadband = fsm_tracking_deadband;
        Scenario.batch_interval    = fsm_batch_interval;
        Scenario.max_burst_time    = fsm_max_burst_time;
    end
    
    % Add SOLAR_DAY specific parameters if applicable
    if isfield(solar_day_params, 'use_real_sun')
        Scenario.use_real_sun = solar_day_params.use_real_sun;
        Scenario.date = solar_day_params.date;
        Scenario.t_start_hour = solar_day_params.t_start_hour;
        Scenario.t_end_hour = solar_day_params.t_end_hour;
        Scenario.pvgis_file = solar_day_params.pvgis_file;
        Scenario.analysis_mode = solar_day_params.analysis_mode;
        Scenario.analysis_date = solar_day_params.analysis_date;
    end
    
    % Location parameters (Istanbul/Ankara area)
    Scenario.lat = 41.051;              % Latitude [degrees N]
    Scenario.lon = 29.010;              % Longitude [degrees E]
    Scenario.tz = 3;                    % Timezone [UTC+N]
    if ~isfield(Scenario, 't_start_hour')
        Scenario.t_start_hour = 8;      % Simulation start hour
    end
    
    % PI Controller parameters (constant across all scenarios)
    Scenario.Kp_vel = 0.25;
    Scenario.Ki_vel = 0.04;
    Scenario.max_tracking_velocity = 15.0;
    Scenario.smooth_alpha = 0.95;
    
    % FSM parameters (constant)
    Scenario.night_threshold = 0.3;
    Scenario.sun_lost_threshold = 0.5;
    Scenario.sun_found_threshold = 1.0;
    Scenario.lock_threshold = 0.5;
    Scenario.search_speed = 3.0;
    
end
