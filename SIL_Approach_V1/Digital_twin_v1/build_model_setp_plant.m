function build_model()
% BUILD_MODEL  Programmatically create solar_tracker_SIL.slx for Plant testing.
%
% This script builds a minimal Simulink model that wraps the plant_step.m
% function inside a MATLAB Function block. Inputs are stubbed with Constants
% so the Plant can be exercised standalone before STM32_Controller and
% ESP32_Logger subsystems are added.
%
% Topology:
%   [PWM_pan]      ┐
%   [PWM_tilt]     ├─→ [Plant]
%   [FSM_state]    │       ├─→ [Power_Scope] (P_mppt, P_bus)
%   [Clock]        │       ├─→ [Angle_Scope] (sun_az, sun_el, pan, tilt)
%   [GHI/T/wind]   │       ├─→ [Motor_Scope] (I_pan, I_tilt)
%   [lat..st_hour] ┘       └─→ [Terminators]  (others)
%
% Usage:
%   >> cd <your_project_folder>     % plant_step.m must be on path
%   >> build_model                  % builds, opens .slx
%   >> sim('solar_tracker_SIL')     % runs (or click Run in Simulink)
%
% Idempotent: existing model is closed and overwritten.

    model_name = 'solar_tracker_SIL';

    %% Sanity check: plant_step on path?
    if ~exist('plant_step', 'file')
        error(['plant_step.m not found on MATLAB path.\n' ...
               'cd to the folder containing plant_step.m before calling build_model.']);
    end

    %% Close & delete existing instance
    if bdIsLoaded(model_name)
        close_system(model_name, 0);   % discard unsaved changes
    end
    slx_file = [model_name '.slx'];
    if isfile(slx_file)
        delete(slx_file);
        fprintf('Deleted existing %s\n', slx_file);
    end

    %% Create fresh model
    new_system(model_name);

    %% Solver settings (Plant_Subsystem template, SIL doc Bölüm 4.2)
    set_param(model_name, ...
        'SolverType', 'Fixed-step', ...
        'Solver',     'ode4', ...
        'FixedStep',  '0.01', ...
        'StartTime',  '0', ...
        'StopTime',   '60', ...
        'SaveOutput', 'on', ...
        'SaveTime',   'on', ...
        'SignalLogging', 'on');

    %% --- Layout grid ---
    xIn = 30;   wIn = 110;        % input column
    xP1 = 320;  xP2 = 670;        % Plant block
    xS1 = 770;  xS2 = 900;        % scope column
    xT  = 730;                    % terminators column
    yStart = 30; rowH = 50;

    %% --- 12 input blocks ---
    % Defaults: Antalya öğle, 21 Mart ekinoks
    inputs = {
        'PWM_pan',    '0',    'int16';
        'PWM_tilt',   '0',    'int16';
        'FSM_state',  '2',    'uint8';     % 2 = SLEEP per Bölüm 4.4
        'CLOCK_PH',   '0',    'double';    % placeholder; replaced by Clock block
        'GHI',        '800',  'double';
        'T_amb',      '25',   'double';
        'wind',       '2',    'double';
        'lat',        '36.9', 'double';
        'lon',        '30.7', 'double';
        'tz',         '3',    'double';
        'start_doy',  '80',   'double';
        'start_hour', '12',   'double';
    };

    for k = 1:size(inputs,1)
        name = inputs{k,1};
        val  = inputs{k,2};
        typ  = inputs{k,3};
        y    = yStart + (k-1)*rowH;
        pos  = [xIn, y, xIn+wIn, y+30];

        if strcmp(name, 'CLOCK_PH')
            % Replace placeholder with Clock block
            add_block('simulink/Sources/Clock', [model_name '/Clock'], ...
                'Position', pos);
        else
            add_block('simulink/Sources/Constant', [model_name '/' name], ...
                'Position', pos, ...
                'Value', val, ...
                'OutDataTypeStr', typ);
        end
    end

    %% --- Plant MATLAB Function block ---
    plant_block = [model_name '/Plant'];
    add_block('simulink/User-Defined Functions/MATLAB Function', plant_block, ...
        'Position', [xP1, yStart, xP2, yStart + 12*rowH]);
    set_plant_script(plant_block);

    %% --- Wire inputs to Plant (port order matches plant_step signature) ---
    % plant_step(pwm_pan, pwm_tilt, fsm_state, t_sim, GHI, T_amb, wind, ...
    %            lat, lon, tz, start_doy, start_hour)
    wiring = {
        'PWM_pan/1',     'Plant/1';
        'PWM_tilt/1',    'Plant/2';
        'FSM_state/1',   'Plant/3';
        'Clock/1',       'Plant/4';
        'GHI/1',         'Plant/5';
        'T_amb/1',       'Plant/6';
        'wind/1',        'Plant/7';
        'lat/1',         'Plant/8';
        'lon/1',         'Plant/9';
        'tz/1',          'Plant/10';
        'start_doy/1',   'Plant/11';
        'start_hour/1',  'Plant/12';
    };
    for k = 1:size(wiring,1)
        add_line(model_name, wiring{k,1}, wiring{k,2}, 'autorouting', 'on');
    end

    %% --- Scopes for key signals ---
    % Plant outputs (port index): 
    %   1: ldr_adc(4)  2: P_panel(4)  3: V_panel(4)  4: I_panel(4)
    %   5: P_mppt      6: P_bus       7: T_panel(4)
    %   8: sun_az      9: sun_el      10: panel_pan  11: panel_tilt
    %   12: I_pan      13: I_tilt     14: E_pan      15: E_tilt

    add_block('simulink/Sinks/Scope', [model_name '/Power_Scope'], ...
        'Position', [xS1, yStart, xS2, yStart+90], ...
        'NumInputPorts', '2');
    add_line(model_name, 'Plant/5', 'Power_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/6', 'Power_Scope/2', 'autorouting','on');

    add_block('simulink/Sinks/Scope', [model_name '/Angle_Scope'], ...
        'Position', [xS1, yStart+150, xS2, yStart+240], ...
        'NumInputPorts', '4');
    add_line(model_name, 'Plant/8',  'Angle_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/9',  'Angle_Scope/2', 'autorouting','on');
    add_line(model_name, 'Plant/10', 'Angle_Scope/3', 'autorouting','on');
    add_line(model_name, 'Plant/11', 'Angle_Scope/4', 'autorouting','on');

    add_block('simulink/Sinks/Scope', [model_name '/Motor_Scope'], ...
        'Position', [xS1, yStart+300, xS2, yStart+390], ...
        'NumInputPorts', '2');
    add_line(model_name, 'Plant/12', 'Motor_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/13', 'Motor_Scope/2', 'autorouting','on');

    %% --- Terminators for unused outputs (no unconnected-port warnings) ---
    unused = [1 2 3 4 7 14 15];   % ldr_adc, P/V/I_panel, T_panel, E_pan, E_tilt
    for k = 1:numel(unused)
        name = sprintf('Term_%d', unused(k));
        yT   = yStart + (k-1)*40;
        add_block('simulink/Sinks/Terminator', [model_name '/' name], ...
            'Position', [xT, yT, xT+20, yT+20]);
        add_line(model_name, sprintf('Plant/%d', unused(k)), [name '/1'], ...
            'autorouting','on');
    end

    %% --- Save & open ---
    save_system(model_name);
    open_system(model_name);

    fprintf('\n=== %s.slx built successfully ===\n', model_name);
    fprintf('  Stop time : 60 s\n');
    fprintf('  Step      : 0.01 s\n');
    fprintf('  Defaults  : Antalya 21-Mar öğle, GHI=800, T=25°C, wind=2 m/s\n');
    fprintf('  Stub      : PWM=0, FSM=2 (SLEEP) — Plant idle baseline test\n');
    fprintf('\nNext step: click Run, observe Scopes.\n');
    fprintf('  Power_Scope : P_mppt ~ 0 (sun mis-aligned), P_bus ~ 0.32 W (idle)\n');
    fprintf('  Angle_Scope : sun_az/el moving, panel_pan/tilt steady at 0\n');
    fprintf('  Motor_Scope : both currents ~ 0\n');
    fprintf('\nThen change PWM_pan Value to e.g. 300, re-run, watch motor move.\n\n');
end


function set_plant_script(block_path)
% Set the inline script of a MATLAB Function block. The block becomes a
% thin wrapper that calls the external plant_step.m via coder.extrinsic.
%
% Why extrinsic: plant_step internally calls motor_step which returns a
% struct (Angle/Velocity/Current/Energy). Structs are not codegen-friendly
% in MATLAB Function blocks without Bus Objects. Extrinsic means Simulink
% runs the function in MATLAB interpretation mode, preserving struct
% support without needing Bus definitions.

    code = [ ...
        'function [ldr_adc, P_panel, V_panel, I_panel, P_mppt, P_bus, ...' newline ...
        '          T_panel, sun_az, sun_el, panel_pan, panel_tilt, ...' newline ...
        '          I_pan, I_tilt, E_pan, E_tilt] = fcn( ...' newline ...
        '          pwm_pan, pwm_tilt, fsm_state, t_sim, GHI, T_amb, wind, ...' newline ...
        '          lat, lon, tz, start_doy, start_hour)' newline ...
        '    coder.extrinsic(''plant_step'');' newline ...
        '' newline ...
        '    %% Pre-declare outputs so Simulink can infer types' newline ...
        '    ldr_adc    = uint16(zeros(4,1));' newline ...
        '    P_panel    = zeros(4,1);' newline ...
        '    V_panel    = zeros(4,1);' newline ...
        '    I_panel    = zeros(4,1);' newline ...
        '    T_panel    = zeros(4,1);' newline ...
        '    P_mppt     = 0;   P_bus = 0;' newline ...
        '    sun_az     = 0;   sun_el = 0;' newline ...
        '    panel_pan  = 0;   panel_tilt = 0;' newline ...
        '    I_pan      = 0;   I_tilt = 0;' newline ...
        '    E_pan      = 0;   E_tilt = 0;' newline ...
        '' newline ...
        '    [ldr_adc, P_panel, V_panel, I_panel, P_mppt, P_bus, ...' newline ...
        '     T_panel, sun_az, sun_el, panel_pan, panel_tilt, ...' newline ...
        '     I_pan, I_tilt, E_pan, E_tilt] = ...' newline ...
        '         plant_step(pwm_pan, pwm_tilt, fsm_state, t_sim, ...' newline ...
        '                    GHI, T_amb, wind, ...' newline ...
        '                    lat, lon, tz, start_doy, start_hour);' newline ...
        'end' newline ];

    %% Get the Stateflow chart handle and set its Script
    root  = sfroot;
    chart = root.find('-isa', 'Stateflow.EMChart', 'Path', block_path);
    if isempty(chart)
        error('Could not find embedded MATLAB chart at: %s', block_path);
    end
    chart.Script = code;
end