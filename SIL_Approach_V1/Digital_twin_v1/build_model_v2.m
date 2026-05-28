function build_model_v2()
% BUILD_MODEL_V2  7-Durumlu Hibrit FSM ile kapali cevrim Simulink modeli
%
% Topoloji:
%   [Clock, lat, doy, ...]  ──→  [Plant]
%                                    │
%             ┌──────────────────────┤ ldr_adc, sun_az, sun_el, pan, tilt
%             │                      │
%        [Unit Delays]               │
%             │                      │
%             ▼                      │
%   [Controller V2]  ──→  pwm_pan, pwm_tilt, fsm_state  ──→  [Plant]
%        (FSM + PI)
%
% Cikis:
%   solar_tracker_SIL_V2.slx — Calistirilabilir kapali cevrim model
%
% Kullanim:
%   >> cd <proje_klasoru>
%   >> build_model_v2
%   >> sim('solar_tracker_SIL_V2')
%
% Yazar  : Kerem Bayer (Master's Thesis, 2024 — SIL V2)
% Tarih  : 2026-05-28

    model_name = 'solar_tracker_SIL_V2';

    %% Dosya kontrolleri
    required_files = {'plant_step', 'controller_step_v2', 'fsm_hybrid', ...
                      'error_extractor', 'pi_step', 'motor_step', ...
                      'ldr_model', 'readLDRs', 'solar_ephemeris_local'};
    for k = 1:numel(required_files)
        if ~exist(required_files{k}, 'file')
            error('%s.m bulunamadi. Dogru klasorde oldugundan emin ol.', ...
                  required_files{k});
        end
    end

    %% Mevcut modeli kapat ve sil
    if bdIsLoaded(model_name)
        close_system(model_name, 0);
    end
    slx_file = [model_name '.slx'];
    if isfile(slx_file)
        delete(slx_file);
        fprintf('Silindi: %s\n', slx_file);
    end

    %% Yeni model olustur
    new_system(model_name);

    %% Solver ayarlari (SIL doc Bolum 4.2)
    set_param(model_name, ...
        'SolverType',     'Fixed-step', ...
        'Solver',         'ode4', ...
        'FixedStep',      '0.01', ...
        'StartTime',      '0', ...
        'StopTime',       '600', ...     % 10 dakika
        'SaveOutput',     'on', ...
        'SaveTime',       'on', ...
        'SignalLogging',  'on');

    %% ═══ LAYOUT GRID ═══════════════════════════════════════════════
    xIn  = 30;   wIn  = 110;          % Giris bloklari
    xDly = 250;  wDly = 60;           % Delay bloklari
    xCtl = 380;  wCtl = 180;          % Kontrolcu
    xPlt = 650;  wPlt = 300;          % Plant
    xScp = 1050; wScp = 130;          % Scope'lar
    xTrm = 1050;                      % Terminatorler
    yStart = 30;  rowH = 50;

    %% ═══ GIRIS BLOKLARI ════════════════════════════════════════════
    % Antalya oglen varsayilanlari
    inputs = {
        'CLOCK_PH',   '0',    'double';    % Placeholder -> Clock
        'GHI',        '800',  'double';
        'T_amb',      '25',   'double';
        'wind',       '2',    'double';
        'lat',        '36.9', 'double';
        'lon',        '30.7', 'double';
        'tz',         '3',    'double';
        'start_doy',  '80',   'double';
        'start_hour', '12',   'double';
        'dt_ctrl',    '0.01', 'double';    % Kontrolcu periyodu
    };

    for k = 1:size(inputs,1)
        name = inputs{k,1};
        val  = inputs{k,2};
        typ  = inputs{k,3};
        y    = yStart + (k-1)*rowH;
        pos  = [xIn, y, xIn+wIn, y+30];
        if strcmp(name, 'CLOCK_PH')
            add_block('simulink/Sources/Clock', [model_name '/Clock'], ...
                'Position', pos);
        else
            add_block('simulink/Sources/Constant', [model_name '/' name], ...
                'Position', pos, 'Value', val, 'OutDataTypeStr', typ);
        end
    end

    %% ═══ UNIT DELAY BLOKLARI (Algebraic Loop Korumasi) ═════════════
    % Plant -> Controller geri besleme sinyalleri icin gecikme
    delays = {
        'Delay_ldr',   'zeros(4,1,''uint16'')', yStart;           % ldr_adc (4x1)
        'Delay_az',    '180',                   yStart + rowH;    % sun_az
        'Delay_el',    '45',                    yStart + 2*rowH;  % sun_el
        'Delay_pan',   '0',                     yStart + 3*rowH;  % panel_pan
        'Delay_tilt',  '0',                     yStart + 4*rowH;  % panel_tilt
        'Delay_fsm',   'uint8(2)',              yStart + 5*rowH;  % fsm_state
    };

    for k = 1:size(delays,1)
        name = delays{k,1};
        ic   = delays{k,2};
        y    = delays{k,3};
        add_block('simulink/Discrete/Unit Delay', [model_name '/' name], ...
            'Position', [xDly, y, xDly+wDly, y+30], ...
            'InitialCondition', ic);
    end

    %% ═══ KONTROLCU MATLAB FUNCTION BLOGU ═══════════════════════════
    ctrl_block = [model_name '/Controller_V2'];
    add_block('simulink/User-Defined Functions/MATLAB Function', ctrl_block, ...
        'Position', [xCtl, yStart, xCtl+wCtl, yStart + 7*rowH]);
    set_controller_v2_script(ctrl_block);

    %% ═══ PLANT MATLAB FUNCTION BLOGU ═══════════════════════════════
    plant_block = [model_name '/Plant'];
    add_block('simulink/User-Defined Functions/MATLAB Function', plant_block, ...
        'Position', [xPlt, yStart, xPlt+wPlt, yStart + 12*rowH]);
    set_plant_script(plant_block);

    %% ═══ WIRING: Plant -> Delays -> Controller ═════════════════════

    % Plant cikislarini Delay'lara bagla
    add_line(model_name, 'Plant/1',  'Delay_ldr/1',  'autorouting','on');  % ldr_adc
    add_line(model_name, 'Plant/8',  'Delay_az/1',   'autorouting','on');  % sun_az
    add_line(model_name, 'Plant/9',  'Delay_el/1',   'autorouting','on');  % sun_el
    add_line(model_name, 'Plant/10', 'Delay_pan/1',  'autorouting','on');  % panel_pan
    add_line(model_name, 'Plant/11', 'Delay_tilt/1', 'autorouting','on');  % panel_tilt

    % Delay'lardan Controller'a bagla
    add_line(model_name, 'Delay_ldr/1',  'Controller_V2/1', 'autorouting','on');  % ldr_adc
    add_line(model_name, 'Delay_az/1',   'Controller_V2/2', 'autorouting','on');  % sun_az
    add_line(model_name, 'Delay_el/1',   'Controller_V2/3', 'autorouting','on');  % sun_el
    add_line(model_name, 'Delay_pan/1',  'Controller_V2/4', 'autorouting','on');  % panel_pan
    add_line(model_name, 'Delay_tilt/1', 'Controller_V2/5', 'autorouting','on');  % panel_tilt

    % Sabit girisler -> Controller
    add_line(model_name, 'lat/1',       'Controller_V2/6', 'autorouting','on');
    add_line(model_name, 'start_doy/1', 'Controller_V2/7', 'autorouting','on');
    add_line(model_name, 'Clock/1',     'Controller_V2/8', 'autorouting','on');  % t_sim
    add_line(model_name, 'dt_ctrl/1',   'Controller_V2/9', 'autorouting','on');

    %% ═══ WIRING: Controller -> Plant ═══════════════════════════════

    % PWM komutlari
    add_line(model_name, 'Controller_V2/1', 'Plant/1', 'autorouting','on');  % pwm_pan
    add_line(model_name, 'Controller_V2/2', 'Plant/2', 'autorouting','on');  % pwm_tilt

    % FSM state -> Delay -> Plant (parazitik guc modeli icin)
    add_line(model_name, 'Controller_V2/3', 'Delay_fsm/1',  'autorouting','on');
    add_line(model_name, 'Delay_fsm/1',     'Plant/3',      'autorouting','on');

    % Diger Plant girisleri (sabitler ve Clock)
    plant_const_wiring = {
        'Clock/1',       'Plant/4';    % t_sim
        'GHI/1',         'Plant/5';
        'T_amb/1',       'Plant/6';
        'wind/1',        'Plant/7';
        'lat/1',         'Plant/8';
        'lon/1',         'Plant/9';
        'tz/1',          'Plant/10';
        'start_doy/1',   'Plant/11';
        'start_hour/1',  'Plant/12';
    };
    for k = 1:size(plant_const_wiring,1)
        add_line(model_name, plant_const_wiring{k,1}, plant_const_wiring{k,2}, ...
            'autorouting','on');
    end

    %% ═══ SCOPE'LAR ═════════════════════════════════════════════════

    % Power Scope: P_mppt vs P_bus
    add_block('simulink/Sinks/Scope', [model_name '/Power_Scope'], ...
        'Position', [xScp, yStart, xScp+wScp, yStart+90], ...
        'NumInputPorts', '2');
    add_line(model_name, 'Plant/5',  'Power_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/6',  'Power_Scope/2', 'autorouting','on');

    % Angle Scope: sun_az, sun_el, panel_pan, panel_tilt
    add_block('simulink/Sinks/Scope', [model_name '/Angle_Scope'], ...
        'Position', [xScp, yStart+150, xScp+wScp, yStart+240], ...
        'NumInputPorts', '4');
    add_line(model_name, 'Plant/8',  'Angle_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/9',  'Angle_Scope/2', 'autorouting','on');
    add_line(model_name, 'Plant/10', 'Angle_Scope/3', 'autorouting','on');
    add_line(model_name, 'Plant/11', 'Angle_Scope/4', 'autorouting','on');

    % Motor Scope: I_pan, I_tilt
    add_block('simulink/Sinks/Scope', [model_name '/Motor_Scope'], ...
        'Position', [xScp, yStart+300, xScp+wScp, yStart+390], ...
        'NumInputPorts', '2');
    add_line(model_name, 'Plant/12', 'Motor_Scope/1', 'autorouting','on');
    add_line(model_name, 'Plant/13', 'Motor_Scope/2', 'autorouting','on');

    % FSM State Scope: durum numarasi (1..7)
    add_block('simulink/Sinks/Scope', [model_name '/FSM_Scope'], ...
        'Position', [xScp, yStart+450, xScp+wScp, yStart+510], ...
        'NumInputPorts', '1');
    add_line(model_name, 'Controller_V2/3', 'FSM_Scope/1', 'autorouting','on');

    %% ═══ TERMINATORLER ═════════════════════════════════════════════
    % Kullanilmayan Plant cikislari (warning onleme)
    unused_ports = [2 3 4 7 14 15];  % P_panel, V_panel, I_panel, T_panel, E_pan, E_tilt
    for k = 1:numel(unused_ports)
        name = sprintf('Term_%d', unused_ports(k));
        yT   = yStart + 500 + (k-1)*40;
        add_block('simulink/Sinks/Terminator', [model_name '/' name], ...
            'Position', [xTrm, yT, xTrm+20, yT+20]);
        add_line(model_name, sprintf('Plant/%d', unused_ports(k)), ...
            [name '/1'], 'autorouting','on');
    end

    %% ═══ KAYDET VE AC ══════════════════════════════════════════════
    save_system(model_name);
    open_system(model_name);

    fprintf('\n══════════════════════════════════════════════════════════════\n');
    fprintf('  %s.slx basariyla olusturuldu!\n', model_name);
    fprintf('══════════════════════════════════════════════════════════════\n');
    fprintf('  Stop time  : 600 s (10 dakika)\n');
    fprintf('  Step       : 0.01 s\n');
    fprintf('  Varsayilan : Antalya, 21 Mart, ogle, GHI=800 W/m²\n');
    fprintf('  FSM        : 7-durumlu hibrit (Ephemeris + LDR)\n');
    fprintf('\n');
    fprintf('  Scope''lar:\n');
    fprintf('    Power_Scope : P_mppt (panel) vs P_bus (tuketim)\n');
    fprintf('    Angle_Scope : sun_az/el vs panel_pan/tilt\n');
    fprintf('    Motor_Scope : I_pan, I_tilt motor akimlari\n');
    fprintf('    FSM_Scope   : FSM durum numarasi (1=INIT..7=SAFE)\n');
    fprintf('\n  Simulasyonu baslatmak icin: sim(''%s'')\n\n', model_name);
end

%% ═══════════════════════════════════════════════════════════════════
%% CONTROLLER V2 SCRIPT (MATLAB Function blok icerigi)
%% ═══════════════════════════════════════════════════════════════════

function set_controller_v2_script(block_path)
    code = [ ...
        'function [pwm_pan, pwm_tilt, fsm_state_out] = fcn(' ...
        'ldr_adc, sun_az, sun_el, panel_pan, panel_tilt, ' ...
        'lat, start_doy, t_sim, dt)' newline ...
        '    coder.extrinsic(''controller_step_v2'');' newline ...
        '' newline ...
        '    pwm_pan       = 0;' newline ...
        '    pwm_tilt      = 0;' newline ...
        '    fsm_state_out = uint8(2);' newline ...
        '' newline ...
        '    [pwm_pan, pwm_tilt, fsm_state_out] = ...' newline ...
        '        controller_step_v2(ldr_adc, sun_az, sun_el, ' ...
        'panel_pan, panel_tilt, ...' newline ...
        '                           lat, start_doy, t_sim, dt);' newline ...
        'end' newline ];

    root  = sfroot;
    chart = root.find('-isa', 'Stateflow.EMChart', 'Path', block_path);
    if isempty(chart)
        error('Embedded MATLAB chart bulunamadi: %s', block_path);
    end
    chart.Script = code;
end

%% ═══════════════════════════════════════════════════════════════════
%% PLANT SCRIPT (Degisiklik yok — build_model_setp_plant.m ile ayni)
%% ═══════════════════════════════════════════════════════════════════

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
    if isempty(chart)
        error('Embedded MATLAB chart bulunamadi: %s', block_path);
    end
    chart.Script = code;
end
