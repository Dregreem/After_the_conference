function [ldr_adc, P_panel, V_panel, I_panel, P_mppt, P_bus, ...
          T_panel, sun_az, sun_el, panel_pan_out, panel_tilt_out, ...
          I_motor_pan, I_motor_tilt, E_motor_pan, E_motor_tilt] = ...
    plant_step(pwm_pan, pwm_tilt, fsm_state, t_sim, ...
               GHI, T_amb, wind, ...
               lat, lon, tz, start_doy, start_hour)
    %#codegen
    coder.extrinsic('stepTheoreticalServo');

    % Codegen icin cikti on tanimlari
    ldr_adc       = uint16(zeros(4,1));
    P_panel       = zeros(4,1);
    V_panel       = zeros(4,1);
    I_panel       = zeros(4,1);
    T_panel       = zeros(4,1);
    P_mppt        = 0;  P_bus = 0;
    sun_az        = 0;  sun_el = 0;
    panel_pan_out = 0;  panel_tilt_out = 0;
    I_motor_pan   = 0;  I_motor_tilt  = 0;
    E_motor_pan   = 0;  E_motor_tilt  = 0;

    persistent state_motor_pan state_motor_tilt
    if isempty(state_motor_pan)
        state_motor_pan  = struct('Angle',0,'Velocity',0,'Current',0,'Energy',0);
        state_motor_tilt = struct('Angle',0,'Velocity',0,'Current',0,'Energy',0);
    end

    dt = 0.01;

    %% (1) Gunes pozisyonu
    [sun_az, sun_el, ~] = solar_ephemeris_local(t_sim, lat, lon, tz, ...
                                                start_doy, start_hour);

    %% (2) Motor adim - PWM -> aci
    next_pan  = state_motor_pan;
    next_tilt = state_motor_tilt;
    [next_pan,  ~, ~] = motor_step(state_motor_pan,  pwm_pan,  dt, 'Pan');
    [next_tilt, ~, ~] = motor_step(state_motor_tilt, pwm_tilt, dt, 'Tilt');
    state_motor_pan  = next_pan;
    state_motor_tilt = next_tilt;

    panel_pan      = next_pan.Angle;
    panel_tilt     = next_tilt.Angle;
    I_motor_pan    = next_pan.Current;
    I_motor_tilt   = next_tilt.Current;
    E_motor_pan    = next_pan.Energy;
    E_motor_tilt   = next_tilt.Energy;

    %% (3) Hizasizlik
    mis_pan  = sun_az - (180 + panel_pan);
    mis_tilt = (90 - panel_tilt) - sun_el;

    %% (4) LDR sensoru
    ldr_v   = ldr_model(mis_pan, mis_tilt, GHI);
    ldr_adc = uint16( min(4095, max(0, round(ldr_v * 4095/3.3))) );

    %% (5) Panel IV + termal
    [P_panel, V_panel, I_panel] = panel_iv_model(mis_pan, mis_tilt, GHI, T_amb, wind);
    T_panel = faiman_temp(GHI, T_amb, wind);
    P_mppt  = sum(P_panel);

    %% (6) Parazitik - motor akimlarini ve fsm durumunu kullaniyor
    P_bus = parasitic_power_model(I_motor_pan, I_motor_tilt, fsm_state);

    %% Cikti acilari
    panel_pan_out  = panel_pan;
    panel_tilt_out = panel_tilt;
end