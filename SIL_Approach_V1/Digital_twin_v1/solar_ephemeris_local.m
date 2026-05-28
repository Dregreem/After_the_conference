function [sun_az_deg, sun_el_deg, S_vec] = solar_ephemeris_local(t_sim, lat, lon, tz, start_doy, start_hour)
    %#codegen
    % SOLAR_EPHEMERIS_LOCAL  Spencer (1971) tabanli, codegen-uyumlu ephemeris.
    %
    % Girisler:
    %   t_sim      : simulasyon basindan itibaren saniye
    %   lat, lon   : enlem/boylam [deg]
    %   tz         : UTC offset [saat]
    %   start_doy  : t_sim=0 anindaki gun sayisi (1..365)
    %   start_hour : t_sim=0 anindaki yerel saat (0..24, ondalik)
    %
    % Cikislar:
    %   sun_az_deg : 0..360 (kuzeyden saat yonunde)
    %   sun_el_deg : -90..90
    %   S_vec      : 3x1 birim vektor ENU; gece [0;0;0]

    sec_per_day = 86400;
    days_elapsed = floor(t_sim / sec_per_day);
    doy         = mod(start_doy - 1 + days_elapsed, 365) + 1;
    local_hour  = start_hour + mod(t_sim, sec_per_day) / 3600;

    % --- Spencer fractional year ---
    Gamma = 2*pi*(doy - 1) / 365;

    % Deklinasyon [rad]
    delta_rad = 0.006918 ...
              - 0.399912*cos(Gamma)   + 0.070257*sin(Gamma) ...
              - 0.006758*cos(2*Gamma) + 0.000907*sin(2*Gamma) ...
              - 0.002697*cos(3*Gamma) + 0.001480*sin(3*Gamma);

    % Zaman denklemi [dakika]
    EoT_min = 229.18 * ( 0.000075 ...
              + 0.001868*cos(Gamma)   - 0.032077*sin(Gamma) ...
              - 0.014615*cos(2*Gamma) - 0.040849*sin(2*Gamma) );

    % Gercek gunes zamani ve saat acisi
    time_correction_min = 4*(lon - 15*tz) + EoT_min;
    LST       = local_hour + time_correction_min/60;
    omega_rad = deg2rad(15*(LST - 12));

    % Yukseklik ve azimut
    lat_rad   = deg2rad(lat);
    sin_alpha = sin(lat_rad)*sin(delta_rad) + ...
                cos(lat_rad)*cos(delta_rad)*cos(omega_rad);
    sin_alpha = max(-1, min(1, sin_alpha));
    alpha_rad = asin(sin_alpha);

    az_rad = atan2(-sin(omega_rad)*cos(delta_rad), ...
                   cos(lat_rad)*sin(delta_rad) - ...
                   sin(lat_rad)*cos(delta_rad)*cos(omega_rad));
    phi_rad = mod(az_rad, 2*pi);

    sun_el_deg = rad2deg(alpha_rad);
    sun_az_deg = rad2deg(phi_rad);

    % ENU birim vektor (mevcut konvansiyonunla uyumlu)
    S_x = cos(alpha_rad)*sin(phi_rad);   % East
    S_y = cos(alpha_rad)*cos(phi_rad);   % North
    S_z = sin(alpha_rad);                % Up
    S_vec = [S_x; S_y; S_z];

    % Gece korumasi
    if sun_el_deg < 0
        S_vec = [0; 0; 0];
    end
end