function [P, V, I] = panel_iv_model(mis_pan_deg, mis_tilt_deg, GHI, T_amb, wind)
    %#codegen
    coder.extrinsic('pvSubPanelPower');
    
    P = zeros(4,1); V = zeros(4,1); I = zeros(4,1);
    P_base = zeros(4,1);
    
    S_body = [ sind(mis_pan_deg); ...
              -sind(mis_tilt_deg); ...
               cosd(mis_pan_deg)*cosd(mis_tilt_deg) ];
    panel_cfg=struct('A',0.04,'eta',0.20);
    P_base = pvSubPanelPower(GHI, S_body,panel_cfg);

    % Fallback - makale parametreleriyle uyumlu
    if isempty(P_base) || sum(P_base) == 0
        theta_mis = sqrt(mis_pan_deg^2 + mis_tilt_deg^2);
        G_eff    = GHI * max(0, cosd(theta_mis));
        P_base   = (G_eff * 0.04 * 0.20) * ones(4,1);    % A=0.04 m², eta=0.20
    end

    % Tek bir sicaklik kaynagi - Faiman, gercek ruzgarla
    T_cell = T_amb + GHI / (25.0 + 6.84 * wind);
    T_diff = T_cell - 25;

    % Guc katsayisi: makaledeki gamma_P = -0.004 /K
    P = P_base .* (1 - 0.004 * T_diff);
    P = max(0, P);

    % Voltaj: panelin Vmp~6V (paneller ~6V'da MPPT yapiyor varsayim)
    % beta_V ~ -0.23%/K -> -0.014 V/K
    V_sys = 6.0 - 0.014 * T_diff;
    V = V_sys * ones(4,1);

    I = P ./ V;
    I(~isfinite(I)) = 0;
end