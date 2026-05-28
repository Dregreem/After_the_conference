function [pwm_pan, pwm_tilt] = controller_step(ldr_adc, dt)
    %#codegen
    % CONTROLLER_STEP  FSM'siz ilk kapali cevrim (Closed-Loop) kontrolcusu
    
    % PI Parametreleri (Double)
    Kp = 3.188;
    Ki = 10.317;
    v_max = 15;
    I_max = 10;
    
    % Integrator durumlari (Double)
    persistent I_pan I_tilt
    if isempty(I_pan)
        I_pan = 0;
        I_tilt = 0;
    end
    
    % [A] Hata Cikarimi (Cikislar 'single' tipindedir)
    [e_pan, e_tilt, ~, ~] = error_extractor(ldr_adc);
    
    % [!] TIP UYUSMAZLIGI COZUMU: Coder icin her seyi Double'a ceviriyoruz
    e_pan_d  = double(e_pan);
    e_tilt_d = double(e_tilt);
    dt_d     = double(dt);
    
    % [B] PI Adimlari (Her eksen icin ayri)
    [~, I_pan, pwm_pan_int]   = pi_step(e_pan_d, I_pan, Kp, Ki, dt_d, v_max, I_max);
    [~, I_tilt, pwm_tilt_int] = pi_step(e_tilt_d, I_tilt, Kp, Ki, dt_d, v_max, I_max);
    
    % Simulink Plant 'double' bekledigi icin cast ediyoruz
    pwm_pan  = double(pwm_pan_int);
    pwm_tilt = double(pwm_tilt_int);
end