function T_panel = faiman_temp(GHI, T_amb, wind, ~)
    %#codegen
    % SIL Faiman Termal Isınma Modeli
    % U0 (Sabit isı transferi) = 25.0 W/m2K
    % U1 (Rüzgar destekli ısı transferi) = 6.84 W/m3Ks
    
    T_panel_deg = T_amb + GHI / (25.0 + 6.84 * wind);
    
    % 4 panel icin ayni sicakligi (vektor olarak) dondur
    T_panel = T_panel_deg * ones(4,1);
end