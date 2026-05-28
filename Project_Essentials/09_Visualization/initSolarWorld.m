function handles = initSolarWorld(R_dome)
% INITSOLNARWORLD - Initialize 3D solar tracker visualization
%
% PARAMETER OWNERSHIP: Visualization module owns dome and camera parameters
%
% Inputs:
%   R_dome (optional) - Dome radius [meters] (default: 1.5)
%
% Outputs:
%   handles - Structure with graphics object handles
%
% Turkish comments preserved from original implementation
% İz Yolları ve Pointer Eklendi

    % OWNED PARAMETERS: Visualization configuration
    if nargin < 1 || isempty(R_dome)
        R_dome = 1.5;  % Default dome radius [meters]
    end
    
    f = figure('Name', 'Solar Tracker Digital Twin (Trajectory)', 'Color', 'w', ...
               'Position', [50 50 1200 800], 'Renderer', 'opengl');
    ax = axes('Parent', f);
    axis equal; grid on; hold on;
    xlabel('Doğu (X)'); ylabel('Kuzey (Y)'); zlabel('Zenith (Z)');
    
    % Kamera 1.0m mesafeye uygun
    ViewLimit = 1.3; 
    xlim([-ViewLimit ViewLimit]); ylim([-ViewLimit ViewLimit]); zlim([0 ViewLimit]);
    view(135, 25);
    
    % Gökyüzü (Kısaltıldı)
    SkyRadius = R_dome * 1.5; 
    [sx, sy, sz] = sphere(30); half_idx = sz>=0;
    % Basit gökyüzü renklendirme
    zenithColor = [0.0, 0.4, 0.8]; horizonColor = [0.7, 0.85, 1.0];
    normZ = sz(half_idx);
    CData = zeros(sum(half_idx(:)), 3);
    for i=1:size(CData,1), CData(i,:) = horizonColor*(1-normZ(i)) + zenithColor*normZ(i); end
    skyX=sx(half_idx)*SkyRadius; skyY=sy(half_idx)*SkyRadius; skyZ=sz(half_idx)*SkyRadius;
    % surface(skyX, skyY, skyZ, CData, 'EdgeColor', 'none', 'FaceLighting', 'none'); 
    % (Performans için gökyüzünü kapattım, istersen açabilirsin)

    % Zemin
    patch(SkyRadius*cos(0:0.1:2*pi), SkyRadius*sin(0:0.1:2*pi), zeros(1,63)-0.02, ...
          [0.3 0.35 0.4], 'EdgeColor', 'none', 'FaceAlpha', 0.5);

    % --- GÜNEŞ ---
    SunRadius = 0.06; 
    [sx, sy, sz] = sphere(15); 
    handles.h_Sun = surface(sx*SunRadius, sy*SunRadius, sz*SunRadius, ...
                            'FaceColor', '#FFD700', 'EdgeColor', 'none', ...
                            'AmbientStrength', 1.0);
    handles.SunRadius = SunRadius; 
    handles.h_SunLight = light('Position', [0 0 5], 'Style', 'local', 'Color', [1 1 0.95]);
    light('Position', [0 -5 2], 'Style', 'infinite', 'Color', [0.3 0.3 0.4]); 
    material shiny;
    
    % --- YENİ GÖRSELLER ---
    
    % 1. Güneş Hedef Çizgisi (Turuncu)
    handles.h_SunLine = plot3([0 0], [0 0], [0 0], 'Color', '#FFD700', 'LineWidth', 1, 'LineStyle', '--');
    
    % 2. Tracker Pointer (Kırmızı - Lazer gibi nereye baktığını gösterir)
    handles.h_TrackerLine = plot3([0 0], [0 0], [0 0], 'Color', 'r', 'LineWidth', 2);
    
    % 3. İZ YOLLARI (Animated Lines)
    % Güneşin geçtiği yol (Sarı)
    handles.h_PathSun = animatedline('Color', '#FFC000', 'LineWidth', 1.5, 'LineStyle', ':');
    
    % Tracker'ın baktığı yol (Kırmızı)
    handles.h_PathTracker = animatedline('Color', 'r', 'LineWidth', 2);

    handles.h_Title = title('Sistem Başlatılıyor...', 'FontSize', 12);
    
    % Eksenler
    quiver3(0,0,0, 0.2,0,0, 'r', 'LineWidth',2);
    quiver3(0,0,0, 0,0.2,0, 'g', 'LineWidth',2);
    quiver3(0,0,0, 0,0,0.2, 'b', 'LineWidth',2);
end