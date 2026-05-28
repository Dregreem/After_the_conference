function [v_cmd, I_out, pwm] = pi_step(e, I_prev, Kp, Ki, dt, v_max, I_max)
    %#codegen
    % PI_STEP  Hiz-modlu PI kontrolcu, tek eksen (makale Eq. 18-19)
    %
    % Girisler:
    %   e      : hata [derece]      (error_extractor cikisi: e_pan veya e_tilt)
    %   I_prev : onceki integral [derece*sn]
    %   Kp, Ki : oransal/integral kazanci (makale: 3.188, 10.317)
    %   dt     : kontrolcu ornekleme periyodu [sn] (50 ms)
    %   v_max  : hiz siniri [derece/sn] (makale: 15)
    %   I_max  : integrator clamp [derece*sn] (makale: 10)
    %
    % Cikislar:
    %   v_cmd : doymus hiz komutu [derece/sn]
    %   I_out : guncellenmis integrator [derece*sn]
    %   pwm   : motora gidecek isaretli PWM [-1000, +1000]

    % Tracking gain (back-calculation anti-windup icin)
    K_t = 1.0 / Ki;

    % Ham hiz komutu (P + I)
    v_raw = Kp * e + Ki * I_prev;

    % tanh ile yumusak doyum: keskin clamp yerine, sonsuz jerk yok
    v_cmd = v_max * tanh(v_raw / v_max);

    % Anti-windup: kirpilan miktari geri besleyip integratoru frenle
    I_out = I_prev + (e + K_t * (v_cmd - v_raw)) * dt;

    % Guvenlik clamp'i (anti-windup yuzunden nadiren tetiklenir)
    if I_out >  I_max,  I_out =  I_max;  end
    if I_out < -I_max,  I_out = -I_max;  end

    % Hiz -> PWM lineer olcek (PWM = 1000  <->  v_max = 15 derece/sn)
    pwm_raw = round(1000 * v_cmd / v_max);
    if pwm_raw >  1000,  pwm_raw =  1000;  end
    if pwm_raw < -1000,  pwm_raw = -1000;  end
    pwm = int16(pwm_raw);
end
