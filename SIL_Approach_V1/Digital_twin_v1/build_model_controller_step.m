function build_model()
% BUILD_MODEL  Programmatically create solar_tracker_SIL.slx for Plant testing.
% Kapali cevrim (Closed-Loop) guncellemesi - FSM'siz surekli takip modu.

    model_name = 'solar_tracker_SIL_controller';
    
    %% Sanity check
    if ~exist('plant_step', 'file') || ~exist('controller_step', 'file')
        error('plant_step.m veya controller_step.m bulunamadi. Dogru klasorde oldugundan emin ol.');
    end
    
    %% Close & delete existing instance
    if bdIsLoaded(model_name)
        close_system(model_name, 0);
    end
    slx_file = [model_name '.slx'];
    if isfile(slx_file)
        delete(slx_file);
    end
    
    %% Create fresh model
    new_system(model_name);
    
    %% Solver settings
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
    xIn = 30;   wIn = 110;        
    xC1 = 200;  xC2 = 350;        % Controller block
    xP1 = 500;  xP2 = 750;        % Plant block
    xS1 = 850;  xS2 = 980;        % Scope column
    xT  = 850;                    % Terminators
    yStart = 30; rowH = 50;
    
    %% --- Input blocks ---
    inputs = {
        'FSM_state',  '2',    'uint8';     
        'CLOCK_PH',   '0',    'double';    
        'GHI',        '800',  'double';
        'T_amb',      '25',   'double';
        'wind',       '2',    'double';
        'lat',        '36.9', 'double';
        'lon',        '30.7', 'double';
        'tz',         '3',    'double';
        'start_doy',  '80',   'double';
        'start_hour', '12',   'double';
        'dt_ctrl',    '0.05', 'double'; % Kontrolcu periyodu
    };
    
    for k = 1:size(inputs,1)
        name = inputs{k,1};
        val  = inputs{k,2};
        typ  = inputs{k,3};
        y    = yStart + (k-1)*rowH;
        pos  = [xIn, y, xIn+wIn, y+30];
        if strcmp(name, 'CLOCK_PH')
            add_block('simulink/Sources/Clock', [model_name '/Clock'], 'Position', pos);
        else
            add_block('simulink/Sources/Constant', [model_name '/' name], ...
                'Position', pos, 'Value', val, 'OutDataTypeStr', typ);
        end
    end
    
    %% --- Unit Delay (Algebraic Loop Korumasi) ---
    %% --- Unit Delay (Algebraic Loop Korumasi) ---
    delay_pos = [xC1-80, yStart, xC1-40, yStart+30];
    add_block('simulink/Discrete/Unit Delay', [model_name '/Delay'], ...
        'Position', delay_pos, ...
        'InitialCondition', 'zeros(4,1,''uint16'')'); % Çökmeyi önleyen düzeltme
    
    %% --- Controller MATLAB Function block ---
    ctrl_block = [model_name '/Controller'];
    add_block('simulink/User-Defined Functions/MATLAB Function', ctrl_block, ...
        'Position', [xC1, yStart, xC2, yStart + 80]);
    set_controller_script(ctrl_block);
    
    %% --- Plant MATLAB Function block ---
    plant_block = [model_name '/Plant'];
    add_block('simulink/User-Defined Functions/MATLAB Function', plant_block, ...
        'Position', [xP1, yStart, xP2, yStart + 12*rowH]);
    set_plant_script(plant_block);
    
    %% --- Wiring ---
    % Plant LDR Cikisi -> Delay -> Kontrolcu Girisi
    add_line(model_name, 'Plant/1', 'Delay/1', 'autorouting', 'on');
    add_line(model_name, 'Delay/1', 'Controller/1', 'autorouting', 'on');
    add_line(model_name, 'dt_ctrl/1', 'Controller/2', 'autorouting', 'on');
    
    % Kontrolcu Cikisi -> Plant PWM Girisleri
    add_line(model_name, 'Controller/1', 'Plant/1', 'autorouting', 'on');
    add_line(model_name, 'Controller/2', 'Plant/2', 'autorouting', 'on');
    
    % Diger Plant Girisleri
    plant_inputs = {'FSM_state/1', 'Clock/1', 'GHI/1', 'T_amb/1', 'wind/1', ...
                    'lat/1', 'lon/1', 'tz/1', 'start_doy/1', 'start_hour/1'};
    for k = 1:numel(plant_inputs)
        add_line(model_name, plant_inputs{k}, sprintf('Plant/%d', k+2), 'autorouting', 'on');
    end
    
    %% --- Scopes ---
    add_block('simulink/Sinks/Scope', [model_name '/Power_Scope'], ...
        'Position', [xS1, yStart, xS2, yStart+90], 'NumInputPorts', '2');
    add_line(model_name, 'Plant/5', 'Power_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/6', 'Power_Scope/2', 'autorouting','on');
    
    add_block('simulink/Sinks/Scope', [model_name '/Angle_Scope'], ...
        'Position', [xS1, yStart+150, xS2, yStart+240], 'NumInputPorts', '4');
    add_line(model_name, 'Plant/8',  'Angle_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/9',  'Angle_Scope/2', 'autorouting','on');
    add_line(model_name, 'Plant/10', 'Angle_Scope/3', 'autorouting','on');
    add_line(model_name, 'Plant/11', 'Angle_Scope/4', 'autorouting','on');
    
    add_block('simulink/Sinks/Scope', [model_name '/Motor_Scope'], ...
        'Position', [xS1, yStart+300, xS2, yStart+390], 'NumInputPorts', '2');
    add_line(model_name, 'Plant/12', 'Motor_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/13', 'Motor_Scope/2', 'autorouting','on');
    
    %% --- Terminators ---
    % ldr_adc (1) artik bagli oldugu icin cikarildi
    unused = [2 3 4 7 14 15];   
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
    disp('Kapali cevrim model basariyla kuruldu.');
end

function set_controller_script(block_path)
    code = [ ...
        'function [pwm_pan, pwm_tilt] = fcn(ldr_adc, dt)' newline ...
        '    [pwm_pan, pwm_tilt] = controller_step(ldr_adc, dt);' newline ...
        'end' newline ];
    root  = sfroot;
    chart = root.find('-isa', 'Stateflow.EMChart', 'Path', block_path);
    chart.Script = code;
end

function set_plant_script(block_path)
    code = [ ...
        'function [ldr_adc, P_panel, V_panel, I_panel, P_mppt, P_bus, ...' newline ...
        '          T_panel, sun_az, sun_el, panel_pan, panel_tilt, ...' newline ...
        '          I_pan, I_tilt, E_pan, E_tilt] = fcn( ...' newline ...
        '          pwm_pan, pwm_tilt, fsm_state, t_sim, GHI, T_amb, wind, ...' newline ...
        '          lat, lon, tz, start_doy, start_hour)' newline ...
        '    coder.extrinsic(''plant_step'');' newline ...
        '' newline ...
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
    root  = sfroot;
    chart = root.find('-isa', 'Stateflow.EMChart', 'Path', block_path);
    chart.Script = code;
end