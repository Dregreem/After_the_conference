function [e_pan, e_tilt, e_total, V_sum] = error_extractor(ldr_adc)
    %#codegen
    % ERROR_EXTRACTOR  LDR ADC degerlerinden aci hatasi (makale Eq. 5-7)
    %
    % Giris:
    %   ldr_adc : 4x1 uint16, 12-bit ADC degerleri (0..4095)
    %             Siralama (readLDRs.m / plant_step.m ile uyumlu):
    %               ldr_adc(1) = Right (+X)
    %               ldr_adc(2) = Left  (-X)
    %               ldr_adc(3) = Up    (+Y)
    %               ldr_adc(4) = Down  (-Y)
    %
    % Cikislar:
    %   e_pan   : pan ekseni hatasi [derece]   (PI kontrolcuye gider)
    %   e_tilt  : tilt ekseni hatasi [derece]  (PI kontrolcuye gider)
    %   e_total : skaler birlesik hata [derece] (FSM esik mantigi icin)
    %   V_sum   : toplam voltaj [V] (FSM gece/gunduz, lost-signal mantigi icin)
    %
    % Isaret konvansiyonu:
    %   V_R > V_L  => e_pan > 0  (gunes +X tarafinda, motor +pan donsun)
    %   V_D > V_U  => e_tilt > 0

    % ADC -> voltaj (3.3 V referans, 12-bit)
    V = single(ldr_adc(:)) * 3.3 / 4095;

    V_R = V(1);  V_L = V(2);  V_U = V(3);  V_D = V(4);
    eps_reg = single(1e-3);            % sifira bolme korumasi

    % Eq. 5: normalize edilmis voltaj farki (irradyans buyuklugune dsuyarsiz)
    e_pan_hat  = (V_R - V_L) / (V_R + V_L + eps_reg);
    e_tilt_hat = (V_D - V_U) / (V_U + V_D + eps_reg);

    % Eq. 6: aci uzayina geri esleme (piramidal geometrinin tan(60) faktoru)
    e_pan  = rad2deg(atan(e_pan_hat  * tand(60)));
    e_tilt = rad2deg(atan(e_tilt_hat * tand(60)));

    % Eq. 7 yaklasimi: birlesik skaler hata
    e_total = sqrt(e_pan^2 + e_tilt^2);

    % Toplam isik sinyali
    V_sum = V_R + V_L + V_U + V_D;
end
