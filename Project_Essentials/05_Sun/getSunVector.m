function [S_vec, alpha_deg, phi_deg] = getSunVector(lat, lon, date_time, timezone)
    % getSunVector: Güneşin konum vektörünü hesaplar.
    % Çıktı: S_vec (3x1 Birim Vektör), alpha (Yükseklik), phi (Azimut)

    doy = day(date_time, 'dayofyear');
    
    % Deklinasyon ve Zaman Denklemi
    delta_rad = asin(sin(deg2rad(23.45)) * sin(deg2rad(360/365 * (doy - 81))));
    B = deg2rad(360/364 * (doy - 81));
    EoT = 9.87 * sin(2*B) - 7.53 * cos(B) - 1.5 * sin(B);
    
    % Yerel Güneş Zamanı
    local_time_dec = hour(date_time) + minute(date_time)/60 + second(date_time)/3600;
    time_correction = 4 * (lon - (15 * timezone)) + EoT;
    LST = local_time_dec + time_correction / 60;
    
    % Açılar
    omega_rad = deg2rad(15 * (LST - 12));
    lat_rad = deg2rad(lat);
    
    sin_alpha = sin(lat_rad)*sin(delta_rad) + cos(lat_rad)*cos(delta_rad)*cos(omega_rad);
    alpha_rad = asin(sin_alpha);
    
    az_rad = atan2(-sin(omega_rad)*cos(delta_rad), ...
                   cos(lat_rad)*sin(delta_rad) - sin(lat_rad)*cos(delta_rad)*cos(omega_rad));
    phi_rad = mod(az_rad, 2*pi);
    
    % Çıktılar
    alpha_deg = rad2deg(alpha_rad);
    phi_deg = rad2deg(phi_rad);
    
    % Vektör (ENU Frame)
    S_x = cos(alpha_rad) * sin(phi_rad);
    S_y = cos(alpha_rad) * cos(phi_rad);
    S_z = sin(alpha_rad);
    
    S_vec = [S_x; S_y; S_z];
    
    % Gece Kontrolü
    if alpha_deg < 0
        S_vec = [0; 0; 0];
    end
end