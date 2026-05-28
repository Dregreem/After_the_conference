function [LDR_Intensity, LDR_Voltage, LDR_Resistance, Normals, Debug, props] = readLDRs(S_vec, ApexAngle, ElecParams)
% READLDRS - Realistic LDR sensor model simulation
% 
% PARAMETER OWNERSHIP: Sensors module owns LDR sensor specifications
%
% Realistic Model:
% - GL5528 photodiode with datasheet parameters
% - Normalized photocurrent → 1-5V output range
% - Cosine law for directional response

    %% OWNED PARAMETERS: LDR sensor specifications
    if nargin < 2 || isempty(ApexAngle)
        ApexAngle = 120;  % LDR apex angle [degrees] (default 120°)
    end
    
    if nargin < 3 || isempty(ElecParams)
        ElecParams = struct();
    end
    
    % GL5528 datasheet parameters
    R10     = getFieldOrDefault(ElecParams, 'R10', 10000);   % 10k @ 10 lux
    gamma   = getFieldOrDefault(ElecParams, 'gamma', 0.7);  % Sensitivity exponent
    R_fixed = getFieldOrDefault(ElecParams, 'R_fixed', 3000); % Series resistance
    Vcc     = getFieldOrDefault(ElecParams, 'Vcc', 5.0);    % Supply voltage
    MaxLux  = getFieldOrDefault(ElecParams, 'MaxLux', 1000); % Maximum illuminance
    
    % Expose owned parameters via props struct
    props = struct();
    props.ApexAngle = ApexAngle;
    props.R10 = R10;
    props.Gamma = gamma;
    props.R_fixed = R_fixed;
    props.Vcc = Vcc;
    props.MaxLux = MaxLux;
    
    %% SENSOR GEOMETRY: Surface integral calculation
    slope_deg = (180 - ApexAngle) / 2;
    cs = cosd(slope_deg);
    ss = sind(slope_deg);
    
    % 4 sensor normal vectors (cardinal directions)
    N_Right = [ ss;  0;  cs];
    N_Left  = [-ss;  0;  cs];
    N_Up    = [ 0;  ss;  cs];
    N_Down  = [ 0; -ss;  cs];
    Normals = [N_Right, N_Left, N_Up, N_Down];
    
    S = S_vec(:); % Sütun vektörü
    
    %% 3. YÜZEYİ İNTEGRALİ (5 NOKTA)
    % Her sensör için merkez + 4 kenar
    delta_deg = 5.0;
    
    I_Right = calculateSurfaceIntegral(S, N_Right, delta_deg, slope_deg, 'X');
    I_Left  = calculateSurfaceIntegral(S, N_Left, delta_deg, slope_deg, 'X');
    I_Up    = calculateSurfaceIntegral(S, N_Up, delta_deg, slope_deg, 'Y');
    I_Down  = calculateSurfaceIntegral(S, N_Down, delta_deg, slope_deg, 'Y');
    
    I_raw = [I_Right, I_Left, I_Up, I_Down];
    
    %% 4. NORMALIZASYON (Burada başlıyordu işler yanlış!)
    % Sorun: Yüzey integrali 0-1 aralığında (örn: 0.03)
    %        Bunu doğrudan lux'a çevirmeden voltaj yapmış
    %
    % Çözüm: I_raw önce lux'a çevir, sonra fotocurrent, sonra dirençolarak voltaj yap
    
    % I_raw = 0.03 → Bu "görünürlük" anlamında
    % Gerçek lux ≈ I_raw * MaxLux  (0-1000 lux)
    Lux = I_raw * MaxLux;  % [0, 1000] lux
    
    % Fotocurrent (I_light) = I10 * (Lux/10)^(-gamma)
    I_light = (1e-6) * (Lux / 10) .^ (-gamma);  % Amper
    
    % Direnç: R = R10 * (10/Lux)^gamma
    R_ldr = R10 * (10 ./ max(Lux, 0.1)) .^ gamma;  % max(Lux, 0.1) sıfıra bölmeden korur
    
    %% 5. VOLTAJ HESABı (DOĞRU YÖNTEM)
    % Eğer LDR direnci biliyorsak:
    % V_out = Vcc * R_fixed / (R_ldr + R_fixed)
    LDR_Voltage = Vcc * R_fixed ./ (R_ldr + R_fixed);
    
    % Sınırla [0, Vcc]
    LDR_Voltage = max(0, min(Vcc, LDR_Voltage));
    
    %% 6. INTENSITY (Normalize 0-1 aralığında)
    LDR_Intensity = I_raw;  % Yüzey integrali (eski çıktı uyumluluğu)
    LDR_Resistance = R_ldr;
    
    %% DEBUG: Tanı bilgisi
    Debug.Lux = Lux;
    Debug.R_ldr = R_ldr;
    Debug.I_light = I_light;
    Debug.I_raw = I_raw;


end

function I_avg = calculateSurfaceIntegral(S, N_center, delta_deg, slope_deg, axis)
    % 5 nokta örneklemesi ile yüzey integrali
    I_center = max(0, dot(S, N_center));
    
    d_rad = deg2rad(delta_deg);
    
    if axis == 'X'
        N1 = rotateNormal(N_center, 'Y', d_rad);
        N2 = rotateNormal(N_center, 'Y', -d_rad);
        N3 = rotateNormal(N_center, 'Z', d_rad);
        N4 = rotateNormal(N_center, 'Z', -d_rad);
    else
        N1 = rotateNormal(N_center, 'X', d_rad);
        N2 = rotateNormal(N_center, 'X', -d_rad);
        N3 = rotateNormal(N_center, 'Z', d_rad);
        N4 = rotateNormal(N_center, 'Z', -d_rad);
    end
    
    I1 = max(0, dot(S, N1));
    I2 = max(0, dot(S, N2));
    I3 = max(0, dot(S, N3));
    I4 = max(0, dot(S, N4));
    
    I_avg = (I_center + I1 + I2 + I3 + I4) / 5;
end

function N_rot = rotateNormal(N, axis, angle_rad)
    c = cos(angle_rad);
    s = sin(angle_rad);
    
    switch axis
        case 'X'
            R = [1, 0, 0; 0, c, -s; 0, s, c];
        case 'Y'
            R = [c, 0, s; 0, 1, 0; -s, 0, c];
        case 'Z'
            R = [c, -s, 0; s, c, 0; 0, 0, 1];
    end
    N_rot = R * N;
    N_rot = N_rot / norm(N_rot);
end

function value = getFieldOrDefault(s, field, default)
    if isfield(s, field), value = s.(field); else, value = default; end
end
