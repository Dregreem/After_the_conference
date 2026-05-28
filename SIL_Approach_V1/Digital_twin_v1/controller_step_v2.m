function [pwm_pan, pwm_tilt, fsm_state_out] = ...
    controller_step_v2(ldr_adc, sun_az, sun_el, panel_pan, panel_tilt, ...
                       lat, start_doy, t_sim, dt)
%#codegen
% CONTROLLER_STEP_V2  7-Durumlu Hibrit FSM + PI kontrolcu entegrasyonu
%
% Mimari:
%   [1] error_extractor  ->  LDR ADC'den aci hatasi cikar
%   [2] fsm_hybrid       ->  FSM mantigi: durum, hedef, faz karari
%   [3] hata yonlendirme ->  Faza gore LDR veya konum hatasi sec
%   [4] pi_step (x2)     ->  PI kontrolcu ile hiz komutu uret
%
% Girisler:
%   ldr_adc    : 4x1 uint16, 12-bit ADC degerleri (plant_step cikisi)
%   sun_az     : gunes azimutu [deg] (plant_step cikisi)
%   sun_el     : gunes yuksekligi [deg] (plant_step cikisi)
%   panel_pan  : panel pan acisi [deg] (plant_step cikisi)
%   panel_tilt : panel tilt acisi [deg] (plant_step cikisi)
%   lat        : enlem [deg]
%   start_doy  : baslangic gun sayisi (1..365)
%   t_sim      : simulasyon zamani [s]
%   dt         : kontrolcu ornekleme periyodu [s]
%
% Cikislar:
%   pwm_pan       : pan motor PWM komutu (double, [-1000, +1000])
%   pwm_tilt      : tilt motor PWM komutu (double, [-1000, +1000])
%   fsm_state_out : FSM durum numarasi (uint8, 1..7)
%
% Referanslar:
%   - Makale Eq. 18-19: PI hiz kontrolcu
%   - fsm_hybrid.m: 7-durumlu FSM mantigi
%   - error_extractor.m: LDR hata cikarimi
%   - pi_step.m: PI kontrolcu tek eksen
%
% Yazar  : Kerem Bayer (Master's Thesis, 2024 — SIL V2)
% Tarih  : 2026-05-28

    %% ═══════════════════════════════════════════════════════════════
    %% PI PARAMETRELERI (Makale Section 4.2 — Optimize edilmis)
    %% ═══════════════════════════════════════════════════════════════

    Kp    = 3.188;    % Oransal kazanc [deg/s per deg]
    Ki    = 10.317;   % Integral kazanc [deg/s per deg*s]
    v_max = 15.0;     % Hiz siniri [deg/s]
    I_max = 10.0;     % Integrator clamp [deg*s]

    %% ═══════════════════════════════════════════════════════════════
    %% PERSISTENT INTEGRATOR DURUMLARI
    %% ═══════════════════════════════════════════════════════════════

    persistent I_pan I_tilt
    if isempty(I_pan)
        I_pan  = 0.0;
        I_tilt = 0.0;
    end

    %% ═══════════════════════════════════════════════════════════════
    %% [1] LDR HATA CIKARIMI
    %% ═══════════════════════════════════════════════════════════════

    [e_pan_ldr, e_tilt_ldr, e_total_ldr, V_sum] = error_extractor(ldr_adc);

    %% ═══════════════════════════════════════════════════════════════
    %% [2] FSM MANTIGI
    %% ═══════════════════════════════════════════════════════════════

    [state_num, motor_enable, move_phase, tgt_pan, tgt_tilt, is_flip, ~] = ...
        fsm_hybrid(V_sum, e_total_ldr, ...
                   sun_az, sun_el, panel_pan, panel_tilt, ...
                   lat, start_doy, t_sim, dt);

    fsm_state_out = state_num;

    %% ═══════════════════════════════════════════════════════════════
    %% [3] HATA YONLENDIRME (Faza gore kaynak secimi)
    %% ═══════════════════════════════════════════════════════════════
    %
    %  move_phase = 0  ->  Motorlar kapali, hata = 0
    %  move_phase = 1  ->  Kaba (Ephemeris kor takip): hata = konum farki
    %  move_phase = 2  ->  Ince (LDR geri besleme): hata = LDR voltaj farki
    %  move_phase = 3  ->  Park (gece): hata = park konum farki

    if ~motor_enable
        % ── Motorlar kapali: integrator sifirla, cikis sifir ────────
        e_pan_ctrl  = 0.0;
        e_tilt_ctrl = 0.0;
        I_pan  = 0.0;
        I_tilt = 0.0;

    elseif move_phase == uint8(1) || move_phase == uint8(3)
        % ── Kaba veya Park: konum hatasi (hedef - mevcut) ───────────
        e_pan_ctrl  = double(tgt_pan  - panel_pan);
        e_tilt_ctrl = double(tgt_tilt - panel_tilt);

    elseif move_phase == uint8(2)
        % ── Ince: LDR hatasi ────────────────────────────────────────
        % Gimbal flip durumunda pan hatasi isaret degistirir
        % (Makale Section 3.3, StateManagerFSM.m:89-93 ile uyumlu)
        if is_flip
            e_pan_ctrl = -double(e_pan_ldr);
        else
            e_pan_ctrl =  double(e_pan_ldr);
        end
        e_tilt_ctrl = double(e_tilt_ldr);

    else
        e_pan_ctrl  = 0.0;
        e_tilt_ctrl = 0.0;
    end

    %% ═══════════════════════════════════════════════════════════════
    %% [4] PI KONTROLCU (Her eksen icin ayri)
    %% ═══════════════════════════════════════════════════════════════

    if ~motor_enable
        % Motorlar kapali -> PWM = 0
        pwm_pan  = 0.0;
        pwm_tilt = 0.0;
    else
        % PI adimlari (pi_step.m — Makale Eq. 18-19)
        dt_d = double(dt);
        [~, I_pan,  pwm_pan_int]  = pi_step(e_pan_ctrl,  I_pan,  Kp, Ki, dt_d, v_max, I_max);
        [~, I_tilt, pwm_tilt_int] = pi_step(e_tilt_ctrl, I_tilt, Kp, Ki, dt_d, v_max, I_max);

        % Simulink Plant double beklediginden cast
        pwm_pan  = double(pwm_pan_int);
        pwm_tilt = double(pwm_tilt_int);
    end
end
