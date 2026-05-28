function [state_num, motor_enable, move_phase, tgt_pan, tgt_tilt, is_flip_out, dbg] = ...
    fsm_hybrid(V_sum, e_total_ldr, ...
               sun_az, sun_el, panel_pan, panel_tilt, ...
               lat, start_doy, t_sim, dt)
%#codegen
% FSM_HYBRID  7-durumlu hibrit sonlu durum makinesi (Ephemeris + LDR)
%
% Mimari:
%   Uyanma karari   -> Ephemeris aci farki (kaba konum hatasi)
%   Kaba hareket     -> Ephemeris hedef konumuna sur (kor takip)
%   Ince ayar        -> LDR geri beslemesiyle hassas hizalama
%   Gece parki       -> Sabah dogus azimutuna yonel
%   SEARCH KALDIRILDI -> Bulutlu havada Ephemeris kor takip yapilir
%
% Durumlar:
%   1=INIT    Ilk acilis, sensor kalibrasyonu (1 sn)
%   2=SLEEP   Dusuk guc uyku, STM32 stop mode
%   3=WAKE    Sensorler okunur, Ephemeris hesaplanir
%   4=DECIDE  Gunduz/gece karari, hareket gerekli mi?
%   5=MOVE    2 fazli: Ephemeris kor takip -> LDR fine-tune
%   6=REPORT  Telemetri, logging (tek tick)
%   7=SAFE    Gece parki: sabah dogusuna yonel
%
% Girisler:
%   V_sum       : toplam LDR voltaji [V] (gece/gunduz tespiti icin)
%   e_total_ldr : LDR skaler hata [deg] (kilit tespiti icin)
%   sun_az      : gunes azimutu [deg] (0=N, 90=E, 180=S, 270=W)
%   sun_el      : gunes yuksekligi [deg] (-90..90)
%   panel_pan   : panel pan acisi [deg] (-90..90)
%   panel_tilt  : panel tilt acisi [deg] (-90..90)
%   lat         : enlem [deg]
%   start_doy   : baslangic gun sayisi (1..365)
%   t_sim       : simulasyon zamani [s]
%   dt          : kontrolcu ornekleme periyodu [s]
%
% Cikislar:
%   state_num    : aktif durum numarasi (uint8, 1..7)
%   motor_enable : motorlar aktif mi (logical)
%   move_phase   : 0=off, 1=coarse(ephem), 2=fine(LDR), 3=park
%   tgt_pan      : hedef pan acisi [deg] (coarse/park modunda)
%   tgt_tilt     : hedef tilt acisi [deg] (coarse/park modunda)
%   is_flip_out  : gimbal ters konumda mi (logical)
%   dbg          : debug struct
%
% Referanslar:
%   - Makale Eq. 12: Gimbal inverse kinematic mapping
%   - Makale Table 2: FSM state definitions (genisletilmis)
%   - SIL doc Bolum 4.4: 7-durumlu duty cycle
%
% Yazar  : Kerem Bayer (Master's Thesis, 2024 — Genisletilmis SIL)
% Tarih  : 2026-05-28
% Mimari : 3-Blok (Supervisor -> Controller -> Plant)

    %% ═══════════════════════════════════════════════════════════════
    %% SABIT PARAMETRELER (Fonksiyon sahipliginde)
    %% ═══════════════════════════════════════════════════════════════

    DEADBAND      = 3.0;     % [deg] Ephemeris uyanma esigi
    LOCK_THRESH   = 0.5;     % [deg] LDR kilit esigi
    MIN_SLEEP     = 60.0;    % [s]   Minimum uyku suresi
    MAX_BURST     = 10.0;    % [s]   Maksimum motor calisma suresi
    LOCK_HOLD     = 2.0;     % [s]   Kilit onay suresi
    NIGHT_EL      = -1.0;    % [deg] Gece esigi (gunes yuksekligi)
    NIGHT_V       = 0.30;    % [V]   Gece esigi (LDR toplam voltaj)
    COARSE_THRESH = 2.0;     % [deg] Kor takip -> LDR gecis esigi
    LDR_MIN_V     = 0.50;    % [V]   LDR sinyali yeterli mi esigi
    INIT_DURATION = 1.0;     % [s]   Baslangic kalibrasyon suresi
    PARK_DONE_TH  = 2.0;     % [deg] Park hareketi tamamlandi esigi
    SUNRISE_EL    = 10.0;    % [deg] Park tilt icin varsayilan dogus yuksekligi

    %% ═══════════════════════════════════════════════════════════════
    %% PERSISTENT DURUM (Simulink MATLAB Function uyumlu)
    %% ═══════════════════════════════════════════════════════════════

    persistent fsm_state     % uint8 : aktif durum (1..7)
    persistent init_timer    % double: INIT bekleme sayaci [s]
    persistent sleep_timer   % double: SLEEP suresi sayaci [s]
    persistent burst_timer   % double: MOVE motor calisma sayaci [s]
    persistent lock_timer    % double: kilit onay sayaci [s]
    persistent move_ph       % uint8 : MOVE alt fazi (1=coarse, 2=fine)
    persistent fsm_tgt_pan   % double: hedef pan [deg]
    persistent fsm_tgt_tilt  % double: hedef tilt [deg]
    persistent park_az       % double: park pan hedefi [deg]
    persistent park_tilt_val % double: park tilt hedefi [deg]
    persistent park_done_f   % logical: park hareketi tamamlandi mi

    if isempty(fsm_state)
        fsm_state     = uint8(1);   % INIT
        init_timer    = 0.0;
        sleep_timer   = 0.0;
        burst_timer   = 0.0;
        lock_timer    = 0.0;
        move_ph       = uint8(0);
        fsm_tgt_pan   = 0.0;
        fsm_tgt_tilt  = 0.0;
        park_az       = 0.0;
        park_tilt_val = 45.0;
        park_done_f   = false;
    end

    %% ═══════════════════════════════════════════════════════════════
    %% EPHEMERIS HEDEF HESABI (Makale Eq. 12 — Gimbal Inverse)
    %% ═══════════════════════════════════════════════════════════════
    %
    % Panel koordinat sistemi (plant_step.m ile uyumlu):
    %   panel_pan = 0, panel_tilt = 0  ->  normal yukari (zenith)
    %   Gunes karsilama:
    %     pan  = sun_az - 180  (guneye bak)
    %     tilt = 90 - sun_el   (yukseklige gore egil)
    %
    % Gimbal limiti ±90 oldugu icin |pan| > 90 olursa inverse uygulanir.

    [tgt_pan_ephem, tgt_tilt_ephem, is_flip] = ...
        compute_ephem_target(sun_az, sun_el);

    % Konum hatasi (Ephemeris vs mevcut panel pozisyonu)
    ephem_err_pan  = tgt_pan_ephem  - panel_pan;
    ephem_err_tilt = tgt_tilt_ephem - panel_tilt;
    ephem_error    = sqrt(ephem_err_pan^2 + ephem_err_tilt^2);

    %% ═══════════════════════════════════════════════════════════════
    %% GECE TESPITI (cift katmanli: astronomi + LDR)
    %% ═══════════════════════════════════════════════════════════════

    is_night = (sun_el < NIGHT_EL) || (V_sum < NIGHT_V && sun_el < 5.0);

    %% ═══════════════════════════════════════════════════════════════
    %% CIKIS ON-TANIMLARI (codegen icin zorunlu)
    %% ═══════════════════════════════════════════════════════════════

    motor_enable = false;
    move_phase   = uint8(0);
    tgt_pan      = 0.0;
    tgt_tilt     = 0.0;
    is_flip_out  = is_flip;

    %% ═══════════════════════════════════════════════════════════════
    %% 7-DURUMLU SONLU DURUM MAKINESI
    %% ═══════════════════════════════════════════════════════════════

    state = fsm_state;

    switch state

        case uint8(1)
            % ── INIT: Sistem ilk acilis, sensor kalibrasyonu ────────
            motor_enable = false;
            move_phase   = uint8(0);

            init_timer = init_timer + dt;

            if init_timer >= INIT_DURATION
                state       = uint8(2);   % -> SLEEP
                sleep_timer = 0.0;
                init_timer  = 0.0;
            end

        case uint8(2)
            % ── SLEEP: Dusuk guc uyku modu ──────────────────────────
            motor_enable = false;
            move_phase   = uint8(0);

            sleep_timer = sleep_timer + dt;

            if sleep_timer >= MIN_SLEEP
                state = uint8(3);   % -> WAKE
            end

        case uint8(3)
            % ── WAKE: Sensorler aktif, veri toplanir ────────────────
            motor_enable = false;
            move_phase   = uint8(0);

            % Tek tick'lik gecis durumu — sensorler okundu,
            % Ephemeris hesaplandi (giris argumanlari olarak geldi).
            % Dogrudan DECIDE'a gec.
            state = uint8(4);   % -> DECIDE

        case uint8(4)
            % ── DECIDE: Gunduz/gece ve hareket karari ───────────────
            motor_enable = false;
            move_phase   = uint8(0);

            if is_night
                % ── Gece tespit edildi -> SAFE (park modu) ──────────
                state       = uint8(7);   % -> SAFE
                park_done_f = false;

                % Sabah dogus azimutunu hesapla
                [park_az, park_tilt_val] = ...
                    compute_sunrise_park(lat, start_doy, t_sim, SUNRISE_EL);

            elseif ephem_error > DEADBAND
                % ── Gunes yeterince kaymis -> MOVE ──────────────────
                state       = uint8(5);   % -> MOVE
                move_ph     = uint8(1);   % Faz 1: Kaba (Ephemeris)
                burst_timer = 0.0;
                lock_timer  = 0.0;
                fsm_tgt_pan  = tgt_pan_ephem;
                fsm_tgt_tilt = tgt_tilt_ephem;

            else
                % ── Gunes yeterince kaymamis -> tekrar uyu ──────────
                state       = uint8(2);   % -> SLEEP
                sleep_timer = 0.0;
            end

        case uint8(5)
            % ── MOVE: Motorlar aktif, 2 fazli izleme ────────────────
            motor_enable = true;
            burst_timer  = burst_timer + dt;

            % Hedefi guncelle (gunes hareket ediyor)
            fsm_tgt_pan  = tgt_pan_ephem;
            fsm_tgt_tilt = tgt_tilt_ephem;

            if move_ph == uint8(1)
                % ─── FAZ 1: KABA (Ephemeris Kor Takip) ──────────────
                % PI kontrolcuye konum hatasi gidecek.
                move_phase = uint8(1);
                tgt_pan    = fsm_tgt_pan;
                tgt_tilt   = fsm_tgt_tilt;

                % Gecis kontrolleri:
                if ephem_error < COARSE_THRESH && V_sum > LDR_MIN_V
                    % LDR sinyali var VE konum hatasi kucuk -> ince ayara gec
                    move_ph    = uint8(2);
                    lock_timer = 0.0;

                elseif ephem_error < LOCK_THRESH && V_sum <= LDR_MIN_V
                    % LDR sinyal YOK (bulutlu) ama konum hatasi cok kucuk
                    % -> kor takip basarili, kilit sayacini baslat
                    lock_timer = lock_timer + dt;
                    if lock_timer >= LOCK_HOLD
                        state = uint8(6);   % -> REPORT (kor takip tamamlandi)
                    end
                else
                    % Henuz hedefe ulasilmadi veya LDR yok
                    if V_sum <= LDR_MIN_V
                        lock_timer = 0.0;
                    end
                end

            else
                % ─── FAZ 2: INCE (LDR Geri Besleme) ─────────────────
                % PI kontrolcuye LDR hatasi gidecek.
                move_phase = uint8(2);
                tgt_pan    = 0.0;    % LDR modunda kullanilmaz
                tgt_tilt   = 0.0;

                % LDR hatasi kucukse kilit sayacini baslat
                if e_total_ldr < LOCK_THRESH
                    lock_timer = lock_timer + dt;
                else
                    lock_timer = 0.0;
                end

                % Kilit suresi yeterliyse -> REPORT
                if lock_timer >= LOCK_HOLD
                    state = uint8(6);   % -> REPORT (LDR ile kilitlendi)
                end

                % LDR sinyali kaybolduysa -> tekrar kaba faza don
                if V_sum < LDR_MIN_V
                    move_ph    = uint8(1);
                    lock_timer = 0.0;
                end
            end

            % ─── Burst timeout: MAX_BURST asildiysa zorla dur ───────
            if burst_timer >= MAX_BURST
                state = uint8(6);   % -> REPORT (timeout)
            end

        case uint8(6)
            % ── REPORT: Telemetri ve logging ────────────────────────
            motor_enable = false;
            move_phase   = uint8(0);

            % Tek tick'lik gecis durumu.
            % Zamanlayicilari sifirla ve SLEEP'e gec.
            state       = uint8(2);   % -> SLEEP
            sleep_timer = 0.0;
            burst_timer = 0.0;
            lock_timer  = 0.0;
            move_ph     = uint8(0);

        case uint8(7)
            % ── SAFE: Gece parki — paneli sabah dogusuna cevir ──────
            park_err_pan  = park_az - panel_pan;
            park_err_tilt = park_tilt_val - panel_tilt;
            park_error    = sqrt(park_err_pan^2 + park_err_tilt^2);

            if park_error < PARK_DONE_TH || park_done_f
                % Park hareketi tamamlandi -> uyu
                motor_enable = false;
                move_phase   = uint8(0);
                park_done_f  = true;

                state       = uint8(2);   % -> SLEEP
                sleep_timer = 0.0;
            else
                % Park hareketine devam
                motor_enable = true;
                move_phase   = uint8(3);   % park
                tgt_pan      = park_az;
                tgt_tilt     = park_tilt_val;
            end

        otherwise
            % ── Geri donus korumasi ─────────────────────────────────
            state = uint8(1);   % -> INIT
    end

    %% ═══════════════════════════════════════════════════════════════
    %% DURUM GUNCELLE
    %% ═══════════════════════════════════════════════════════════════

    fsm_state = state;
    state_num = state;

    %% ═══════════════════════════════════════════════════════════════
    %% DEBUG CIKTISI
    %% ═══════════════════════════════════════════════════════════════

    dbg = struct( ...
        'state',           double(state), ...
        'ephem_error',     ephem_error, ...
        'e_total_ldr',     double(e_total_ldr), ...
        'V_sum',           double(V_sum), ...
        'is_night',        is_night, ...
        'burst_timer',     burst_timer, ...
        'lock_timer',      lock_timer, ...
        'sleep_timer',     sleep_timer, ...
        'move_phase_int',  double(move_ph), ...
        'is_flip',         is_flip, ...
        'tgt_pan_ephem',   tgt_pan_ephem, ...
        'tgt_tilt_ephem',  tgt_tilt_ephem, ...
        'park_az',         park_az, ...
        'park_tilt',       park_tilt_val);
end

%% ═══════════════════════════════════════════════════════════════════
%% YARDIMCI FONKSIYON 1: Ephemeris Hedef Hesabi + Gimbal Inverse
%% ═══════════════════════════════════════════════════════════════════

function [tgt_pan, tgt_tilt, is_flip] = compute_ephem_target(sun_az, sun_el)
%COMPUTE_EPHEM_TARGET  Gunes konum -> gimbal hedef acilari (Makale Eq. 12)
%
%   plant_step.m konvansiyonu:
%     mis_pan  = sun_az - (180 + panel_pan)  -> sifir hizasizlik: pan  = sun_az - 180
%     mis_tilt = (90 - panel_tilt) - sun_el  -> sifir hizasizlik: tilt = 90 - sun_el
%
%   Motor limitleri: ±90 derece (motor_step.m)
%   |pan| > 90 olursa gimbal inverse uygulanir (makale Eq. 12).

    % Ham hedef (henuz gimbal inverse oncesi)
    raw_pan = sun_az - 180.0;

    % [-180, 180] araligina normalize et
    if raw_pan > 180.0
        raw_pan = raw_pan - 360.0;
    elseif raw_pan < -180.0
        raw_pan = raw_pan + 360.0;
    end

    % Gimbal inverse mapping (Makale Eq. 12)
    if abs(raw_pan) > 90.0
        % Ters konum: 180 derece pan kaydir + tilt isaret degistir
        tgt_pan  = raw_pan - sign(raw_pan) * 180.0;
        tgt_tilt = -(90.0 - sun_el);
        is_flip  = true;
    else
        % Normal konum
        tgt_pan  = raw_pan;
        tgt_tilt = 90.0 - sun_el;
        is_flip  = false;
    end

    % Motor limitlerine clamp (guvenlik)
    tgt_pan  = max(-90.0, min(90.0, tgt_pan));
    tgt_tilt = max(-90.0, min(90.0, tgt_tilt));
end

%% ═══════════════════════════════════════════════════════════════════
%% YARDIMCI FONKSIYON 2: Sabah Dogus Park Pozisyonu Hesabi
%% ═══════════════════════════════════════════════════════════════════

function [park_pan, park_tilt] = compute_sunrise_park(lat, start_doy, t_sim, sunrise_el_assumed)
%COMPUTE_SUNRISE_PARK  Yarin sabah dogus azimutunu hesapla ve gimbal hedefine cevir
%
%   Spencer (1971) deklinasyon formulu kullanilarak yarin sabah dogus
%   azimutu hesaplanir. Panel bu yöne park edilerek sabah hizli baslar.
%
%   Girisler:
%     lat               : enlem [deg]
%     start_doy         : t_sim=0 anindaki gun sayisi
%     t_sim             : simulasyon zamani [s]
%     sunrise_el_assumed : park tilt icin varsayilan dogus yuksekligi [deg]

    SEC_PER_DAY = 86400.0;
    days_elapsed = floor(t_sim / SEC_PER_DAY);
    current_doy  = mod(start_doy - 1 + days_elapsed, 365) + 1;

    % Yarin sabah icin deklinasyon (Spencer 1971)
    next_doy   = mod(current_doy, 365) + 1;
    Gamma_next = 2.0 * pi * (next_doy - 1) / 365.0;

    delta = 0.006918 ...
          - 0.399912 * cos(Gamma_next)   + 0.070257 * sin(Gamma_next) ...
          - 0.006758 * cos(2*Gamma_next) + 0.000907 * sin(2*Gamma_next) ...
          - 0.002697 * cos(3*Gamma_next) + 0.001480 * sin(3*Gamma_next);

    lat_rad = lat * pi / 180.0;

    % Dogus saat acisi: cos(omega_sr) = -tan(lat)*tan(delta)
    cos_omega_sr = -tan(lat_rad) * tan(delta);
    cos_omega_sr = max(-1.0, min(1.0, cos_omega_sr));
    omega_sr     = -acos(cos_omega_sr);   % negatif (sabah, ogle oncesi)

    % Dogus azimutu (tam formul, solar_ephemeris_local.m ile uyumlu)
    az_num = -sin(omega_sr) * cos(delta);
    az_den = cos(lat_rad) * sin(delta) - sin(lat_rad) * cos(delta) * cos(omega_sr);
    sunrise_az_rad = mod(atan2(az_num, az_den), 2*pi);
    sunrise_az_deg = sunrise_az_rad * 180.0 / pi;

    % Gimbal hedefine cevir (compute_ephem_target ile ayni mantik)
    [park_pan, park_tilt, ~] = compute_ephem_target(sunrise_az_deg, sunrise_el_assumed);
end
