function P_bus = parasitic_power_model(I_motor_pan, I_motor_tilt, fsm_state)
    %#codegen
    % SIL planindaki bilesen tuketim degerleri (W)
    P_esp_modemsleep = 0.264;
    P_ina_total      = 0.0018 * 6;
    P_ds18_total     = 0.0044 * 4;
    P_rtc            = 0.00066;
    P_pcb_idle = P_esp_modemsleep + P_ina_total + P_ds18_total + P_rtc;

    % 7-durumlu FSM (SIL doc Ek C):
    % 1=INIT, 2=SLEEP, 3=WAKE, 4=DECIDE, 5=MOVE, 6=REPORT, 7=SAFE
    % STM32 aktif: WAKE(3), DECIDE(4), MOVE(5), REPORT(6)
    if any(fsm_state == [3, 4, 5, 6])
        P_stm = 0.0825;
    else
        P_stm = 0.000033;
    end

    % Motor gucu: makaledeki Eq. 9 akimlari V_servo=6V uzerinden
    V_servo  = 6.0;
    eta_buck = 0.92;
    P_motor_servo   = V_servo * (I_motor_pan + I_motor_tilt);
    P_motor_battery = P_motor_servo / eta_buck;

    % Toplam batarya tarafi guc
    P_bus = (P_pcb_idle + P_stm) / eta_buck + P_motor_battery;
end