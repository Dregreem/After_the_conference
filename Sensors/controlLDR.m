function [E_pan, E_tilt, E_pan_deg, E_tilt_deg, IsLocked, Debug] = controlLDR(V_R, V_L, V_U, V_D, S_body, ControlParams)
% INPUT VALIDATION ÖNEMLİ!
% Orjinal: Voltajlar 0.8V gelince "hata yok" diyordu
% Yeni: Gerçekçi 1-5V aralığında, açısal hata ile doğrulama

    if nargin < 6 || isempty(ControlParams)
        ControlParams = struct();
    end
    
    epsilon = getFieldOrDefault(ControlParams, 'epsilon', 0.001);
    deadzone_deg = getFieldOrDefault(ControlParams, 'deadzone_deg', 0.5);
    VoltageMin = getFieldOrDefault(ControlParams, 'VoltageMin', 0.5);  % ÖNEMLİ: Min voltaj
    VoltageMax = getFieldOrDefault(ControlParams, 'VoltageMax', 4.5);  % ÖNEMLİ: Max voltaj
    
    %% 1. VOLTAJ VALIDASYONU
    % Yanlış voltaj gelirse -> IsLocked = true (hareket etme!)
    V_all = [V_R, V_L, V_U, V_D];
    V_min = min(V_all);
    V_max = max(V_all);
    
    if V_min < VoltageMin || V_max > VoltageMax || all(V_all < 0.1)
        % HATA: Voltaj range dışında veya tüm sensörler sıfır
        E_pan = 0;
        E_tilt = 0;
        E_pan_deg = 0;
        E_tilt_deg = 0;
        IsLocked = true;  % Hareket etme!
        
        Debug.warning = sprintf('Invalid voltage: [%.2f, %.2f] V', V_min, V_max);
        Debug.V_all = V_all;
        return;
    end
    
    %% 2. VOLTAJ TABANLI HATA (Normalize)
    sum_pan = V_L + V_R + epsilon;
    sum_tilt = V_U + V_D + epsilon;
    
    E_pan = (V_L - V_R) / sum_pan;
    E_tilt = (V_U - V_D) / sum_tilt;
    
    % Sınırla [-1, +1]
    E_pan = max(-1, min(1, E_pan));
    E_tilt = max(-1, min(1, E_tilt));
    
    %% 3. AÇISAL HATA (S_body geometrisi)
    if nargin >= 5 && ~isempty(S_body) && length(S_body) >= 3
        Sx = S_body(1);
        Sy = S_body(2);
        Sz = S_body(3);
        
        if Sz < 0.001
            % Güneş arkada veya ufukta → Kilitlenmiş kabul et
            IsLocked = true;  % Mark locked when sun is behind or at horizon
            E_pan_deg = 0;
            E_tilt_deg = 0;
        else
            E_pan_deg = atan2d(Sy, Sz);
            E_tilt_deg = atan2d(Sx, Sz);
        end
    else
        % S_body yok → Voltajdan tahmin et (kaba)
        E_pan_deg = E_pan * 45;   % [-45, +45] derece
        E_tilt_deg = E_tilt * 45;
    end
    
    %% 4. BİRbirİ DOĞRULAMA (Geçerlililik)
    % Voltaj hatası ile açısal hata uyumlu mu?
    % Örn: E_pan = 0.5 (sağda hata) veya E_pan_deg = +25° (sağda)
    %      Sign uyuşmalı!
    
    % Benzer olabilir kontrol
    sign_match_pan = sign(E_pan) == sign(E_pan_deg);
    sign_match_tilt = sign(E_tilt) == sign(E_tilt_deg);
    
    if ~(sign_match_pan && sign_match_tilt)
        % Hata işaretleri uyuşmamış → Veri tutarsız
        Debug.error_consistency = 'MISMATCH';
        IsLocked = true;
    else
        Debug.error_consistency = 'OK';
    end
    
    %% 5. KİLİTLEME DURUMU
    IsLocked_check = (abs(E_pan_deg) < deadzone_deg) && (abs(E_tilt_deg) < deadzone_deg);
    IsLocked = IsLocked_check;
    
    %% DEBUG
    Debug.V_all = V_all;
    Debug.E_pan = E_pan;
    Debug.E_tilt = E_tilt;
    Debug.E_pan_deg = E_pan_deg;
    Debug.E_tilt_deg = E_tilt_deg;
    Debug.Sz = Sz;
    Debug.sun_visible = (Sz > 0.1);
    
end

function value = getFieldOrDefault(s, field, default)
    if isfield(s, field), value = s.(field); else, value = default; end
end
