function ldr_v = ldr_model(mis_pan_deg, mis_tilt_deg, GHI)
    %#codegen
    coder.extrinsic('readLDRs');

    % Kodgen icin tipler onceden tanimli olmali
    ldr_v       = zeros(4,1);
    ldr_v_raw   = zeros(4,1);

    % Hata acilarini govde vektorune cevir
    % (Gunes panele tam dikse S_body = [0;0;1])
    S_body = [ sind(mis_pan_deg); ...
              -sind(mis_tilt_deg); ...
               cosd(mis_pan_deg)*cosd(mis_tilt_deg) ];

    % GL5528 modelini DOGRU argumanlarla cagir:
    % ApexAngle = 120 (piramidal default), ElecParams = bos -> defaults
    [~, ldr_v_raw, ~] = readLDRs(S_body, 120, []);

    % GHI lineer olcekleme: 1000 W/m^2 referans
    % Gece (GHI=0) -> 0, ogle (GHI=1000) -> tam sinyal
    G_ref = 1000;
    scale = max(0, min(1, GHI / G_ref));

    ldr_v = ldr_v_raw .* scale;
end