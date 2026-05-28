function Mech = initSystemMechanics(ax, PanDims, TiltDims, SensorParams)
% INITSYSTEMMECHANICS - 2 Axis Solar Tracker System Visualization
%
% PARAMETER OWNERSHIP: Visualization module owns servo/mechanical dimensions
%
% System Architecture:
%   1. Base: 3mm plate
%   2. Pan motor: On ground (3mm), X=10mm offset
%   3. Tilt motor: In U-bracket, tilted (Z-axis +2.5mm correction)
%   4. Platform: Tilt top disk + 30mm column
%   5. Panels: 4x oriented in + shape, 14mm below column top
%   6. Sensor: Aesthetic pyramid (12mm height), apex 210mm high

    % ══════════════════════════════════════════════════════════════════════════
    % OWNED PARAMETERS: Servo dimensions and mechanical specifications
    % ══════════════════════════════════════════════════════════════════════════
    if nargin < 2 || isempty(PanDims)
        PanDims = struct('range', 100, 'offset', 10);  % Pan ±100° range
    end
    if nargin < 3 || isempty(TiltDims)
        TiltDims = struct('range', 90, 'offset', 2.5);  % Tilt ±90° range
    end
    if nargin < 4 || isempty(SensorParams)
        SensorParams = struct('ApexAngle', 120, 'Scale', 1);  % 120° apex angle
    end

    %% Mechanical Parameters (SI - Meters)
    mm2m = 1e-3;
    
    % Base and motor specifications
    Base_H = 3 * mm2m;
    Base_R = 60 * mm2m;
    
    % Access PanDims as struct (fields: 'range', 'offset') or as array
    if isstruct(PanDims)
        Servo_L = PanDims.range;
        Servo_XOffset = PanDims.offset;
    else
        Servo_L = PanDims(1);
        Servo_XOffset = PanDims(2);
    end
    
    % Servo body physical dimensions (SI - meters)
    Servo_L = 0.040;            % Servo length [m]
    Servo_W = 0.020;            % Servo width [m]
    Servo_H = 0.042;            % Servo height [m]            
    
    % Pan motor X offset (convert from mm to m)
    X_Pan_Offset = Servo_XOffset * mm2m;   
    
    % Critical pivot calculations
    % Pan Pivot (Z): Zemin(3mm) + Motor(42mm)
    Z_Pan_Pivot = Base_H + Servo_H; 
    
    % Tilt Pivot (Y): 
    Bracket_H = 0.050; 
    % DÜZELTME: Tilt ekseni 2.5mm yukarı taşındı.
    Tilt_Z_Correction = 2.5 * mm2m; 
    Z_Tilt_Pivot = Z_Pan_Pivot + (Bracket_H * 0.75) + Tilt_Z_Correction; 
    
    % Sistem Tepesi (Sensör Ucu)
    Z_Total_Height = 0.210; 

    % --- Parça Boyutları ---
    Disk_Diam = 100 * mm2m; Disk_H = 5 * mm2m;
    Mast_Diam = 30 * mm2m;  % Boru çapı
    
    % --- PV PANEL PARAMETRELERİ ---
    Panel_W  = 80 * mm2m;
    Panel_L  = 80 * mm2m;
    Panel_Th = 6 * mm2m;
    Panel_Drop = 14 * mm2m; % Boru bitiminden aşağı mesafe

    %% 2. KÖK VE ZEMİN (RIG)
    t_rig = hgtransform('Parent', ax);
    
    % Zemin Plakası (3mm)
    drawCylinder(t_rig, Base_R, Base_H, [0.1 0.1 0.1]);

    %% 3. PAN MOTORU GÖVDESİ (SABİT)
    t_pan_body = hgtransform('Parent', t_rig);
    
    % Konum: X=10mm, Z=Taban üstü
    set(t_pan_body, 'Matrix', makehgtform('translate', [X_Pan_Offset, 0, Base_H + Servo_H/2]));
    
    drawServoBody(t_pan_body, [Servo_L, Servo_W, Servo_H], [0.2 0.2 0.2]);

    %% 4. PAN DÖNÜŞ GRUBU (Z Ekseni)
    t_pan = hgtransform('Parent', t_rig);
    set(t_pan, 'Matrix', makehgtform('translate', [X_Pan_Offset, 0, Z_Pan_Pivot]));
    
    % U-Parçası (Bracket)
    % Tilt yukarı kaydığı için braketin boyunu görsel olarak azıcık uzatalım ki motor sığsın
    Bracket_H_Visual = Bracket_H + Tilt_Z_Correction; 
    Bracket_Width_Inner = Servo_H + 0.005; 
    drawUBracket(t_pan, Bracket_Width_Inner, Servo_W+0.005, Bracket_H_Visual, 0.003);

    %% 5. TILT MOTORU GÖVDESİ (YATIK)
    t_tilt_body = hgtransform('Parent', t_pan);
    
    % Konum: U-Parçası içinde, Yatık (-90 X rotasyon)
    % Z Konumu: Hesaplanan yeni Z_Tilt_Pivot'a göre
    Z_Rel_Pan2Tilt = Z_Tilt_Pivot - Z_Pan_Pivot;
    
    M_Rot = makehgtform('xrotate', -pi/2);
    M_Trans = makehgtform('translate', [0, 0, Z_Rel_Pan2Tilt]);
    
    set(t_tilt_body, 'Matrix', M_Trans * M_Rot);
    drawServoBody(t_tilt_body, [Servo_L, Servo_W, Servo_H], [0.1 0.5 0.9]);

    %% 6. TILT DÖNÜŞ GRUBU (Y Ekseni)
    PivotOffset = [0, 0, Z_Rel_Pan2Tilt];
    t_tilt = hgtransform('Parent', t_pan);
    set(t_tilt, 'Matrix', makehgtform('translate', PivotOffset));
    
    % Horn
    drawHorn(t_tilt, 'y');

    %% 7. PLATFORM, SÜTUN VE PANELLER
    
    % --- A. Disk ve Sütun ---
    Dist_Axis_To_Top = Servo_W / 2; % Motor yarı kalınlığı
    
    % Disk Konumu
    Z_Disk_Start_Local = Dist_Axis_To_Top;
    drawDiskOffset(t_tilt, Disk_Diam/2, Disk_H, Z_Disk_Start_Local, [0.9 0.9 0.9]);
    
    % --- SÜTUN BOYU VE PİRAMİT HESABI ---
    % Sensör Geometrisi (ESTETİK AYAR)
    SensorDiam = 0.020;
    
    % Kullanıcı isteği üzerine piramit boyunu biz ayarlıyoruz:
    % 20mm taban için 12mm yükseklik çok estetik durur.
    Pyr_H_Visual = 12 * mm2m; 
    
    % LDR'ler için matematiksel açı (ApexAngle) yine de önemlidir, 
    % ama görseli Pyr_H_Visual ile çizeceğiz.
    
    % Mutlak Yüksekliklerden Sütun Boyu Hesabı:
    Abs_Tilt_H = Z_Tilt_Pivot;
    Available_H = Z_Total_Height - Abs_Tilt_H; % Pivot'tan tepeye kalan mesafe
    
    % Sütun Boyu = Kalan - Disk - MotorPayı - PiramitGörselBoyu
    Mast_H = Available_H - Dist_Axis_To_Top - Disk_H - Pyr_H_Visual;
    Z_Mast_Start = Z_Disk_Start_Local + Disk_H;
    
    % Sütunu Çiz
    drawCylinderPart(t_tilt, Mast_Diam/2, Mast_H, Z_Mast_Start, [0.8 0.8 0.8]);
    
    % --- B. PV Paneller (4 Adet, + Şeklinde) ---
    Z_Mast_Top_Local = Z_Mast_Start + Mast_H;
    
    % Panelin Üst Yüzeyi: Boru bitiminden 14mm aşağıda
    Z_Panel_Top_Surf = Z_Mast_Top_Local - Panel_Drop;
    Z_Panel_Center = Z_Panel_Top_Surf - (Panel_Th / 2);
    
    for i = 0:3
        t_panel = hgtransform('Parent', t_tilt);
        
        Radial_Dist = (Mast_Diam / 2) + (Panel_L / 2);
        
        M_Trans = makehgtform('translate', [Radial_Dist, 0, Z_Panel_Center]);
        M_RotZ  = makehgtform('zrotate', i * (pi/2)); 
        
        set(t_panel, 'Matrix', M_RotZ * M_Trans);
        
        % Panel ve Çerçeve
        drawBox(t_panel, [Panel_L, Panel_W, Panel_Th], [0.1 0.1 0.6], [0,0,0]);
        drawBoxWireframe(t_panel, [Panel_L, Panel_W, Panel_Th], [0.8 0.8 0.8]);
        
        % Alt Montaj Braketi
        Bracket_L = Panel_L * 0.4;
        Bracket_H_Part = 0.01; 
        
        Bracket_X = -(Panel_L/2) + (Bracket_L/2); 
        Bracket_Z = -(Panel_Th/2) - (Bracket_H_Part/2); 
        
        drawBox(t_panel, [Bracket_L, Panel_W*0.6, Bracket_H_Part], [0.4 0.4 0.4], [Bracket_X, 0, Bracket_Z]);
    end

    %% 8. SENSÖR PİRAMİDİ (ESTETİK MOD)
    Z_Pyr_Base = Z_Mast_Top_Local;
    
    % Tepe Noktası (Lokal)
    Apex_Local = [0, 0, Z_Pyr_Base + Pyr_H_Visual];
    
    % Piramit Geometrisi
    deg = [45, 135, 225, 315];
    bx = (SensorDiam/2) * cosd(deg); by = (SensorDiam/2) * sind(deg);
    bz = zeros(1,4) + Z_Pyr_Base;
    
    drawSensorPyramid(t_tilt, bx, by, bz, Apex_Local);
    
    % LDR Noktaları (Görsel Yüzey Üzerinde)
    % Apothem (Yan yüzey yüksekliği)
    Base_Apothem = (SensorDiam/2) * cosd(45);
    
    LDR_D = Base_Apothem * 0.6; % Merkeze biraz daha yakın olsun
    LDR_Z = Z_Pyr_Base + (Pyr_H_Visual * 0.35); % Yüzeyin biraz aşağısında
    
    LDR_Pos = [LDR_D,0,LDR_Z; -LDR_D,0,LDR_Z; 0,LDR_D,LDR_Z; 0,-LDR_D,LDR_Z];
    
    h_LDRs = scatter3(LDR_Pos(:,1), LDR_Pos(:,2), LDR_Pos(:,3), 40, ...
                      'MarkerEdgeColor','k', 'MarkerFaceColor','y', 'Parent',t_tilt);

    %% 9. ÇIKTI VE LOG
    Mech.h_Pan = t_pan;
    Mech.h_Tilt = t_tilt;
    Mech.h_LDRs = h_LDRs;
    Mech.h_Rig = t_rig;
    Mech.PivotOffset = PivotOffset;
    Mech.SensorBaseZ = Z_Pyr_Base;
    
    fprintf('Mekanik Sistem Tamamlandı (Son Revizyon):\n');
    fprintf('  -> Tilt Ekseni: +2.5mm yükseltildi.\n');
    fprintf('  -> Piramit: 12mm yükseklik ile estetik hale getirildi.\n');
    fprintf('  -> Tepe Noktası: %.1f mm (210mm Hedef)\n', (Abs_Tilt_H + Apex_Local(3))*1000);
end

%% --- ÇİZİM YARDIMCILARI ---

function drawDiskOffset(parent, r, h, z_start, color)
    [x,y,z] = cylinder(r, 40);
    z = (z * h) + z_start; 
    surf(x,y,z, 'Parent', parent, 'FaceColor', color, 'EdgeColor', 'none');
    patch(x(1,:), y(1,:), z(1,:), color, 'Parent', parent, 'EdgeColor', 'k');
    patch(x(2,:), y(2,:), z(2,:), color, 'Parent', parent, 'EdgeColor', 'k');
end

function drawCylinderPart(parent, r, h, z_offset, color)
    [x,y,z] = cylinder(r, 30);
    z = (z * h) + z_offset; 
    surf(x,y,z, 'Parent', parent, 'FaceColor', color, 'EdgeColor', 'none');
    patch(x(2,:), y(2,:), z(2,:), color, 'Parent', parent, 'EdgeColor', 'k');
end

function drawCylinder(parent, r, h, color)
    [x,y,z] = cylinder(r, 40); z=z*h;
    surf(x,y,z,'Parent',parent,'FaceColor',color,'EdgeColor','none');
    patch(x(2,:), y(2,:), z(2,:), color, 'Parent', parent, 'EdgeColor', 'k');
end

function drawServoBody(parent, dims, color)
    L=dims(1); W=dims(2); H=dims(3);
    v = [ -L/2 -W/2 -H/2; L/2 -W/2 -H/2; L/2 W/2 -H/2; -L/2 W/2 -H/2; ...
          -L/2 -W/2  H/2; L/2 -W/2  H/2; L/2 W/2  H/2; -L/2 W/2  H/2];
    f = [1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8; 1 2 3 4; 5 6 7 8];
    patch('Parent',parent,'Vertices',v,'Faces',f,'FaceColor',color,'EdgeColor','k');
end

function drawUBracket(parent, w_inner, d, h, th)
    col=[0.7 0.7 0.7];
    w_outer = w_inner + 2*th;
    drawBox(parent, [w_outer, d, th], col, [0,0, th/2]); 
    drawBox(parent, [th, d, h], col, [-w_inner/2 - th/2, 0, h/2 + th]); 
    drawBox(parent, [th, d, h], col, [ w_inner/2 + th/2, 0, h/2 + th]); 
end

function drawBox(parent, d, c, o)
    v = [ -d(1)/2 -d(2)/2 -d(3)/2; d(1)/2 -d(2)/2 -d(3)/2; d(1)/2 d(2)/2 -d(3)/2; -d(1)/2 d(2)/2 -d(3)/2; ...
          -d(1)/2 -d(2)/2  d(3)/2; d(1)/2 -d(2)/2  d(3)/2; d(1)/2 d(2)/2  d(3)/2; -d(1)/2 d(2)/2  d(3)/2];
    v = v + repmat(o,8,1);
    f = [1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8; 1 2 3 4; 5 6 7 8];
    patch('Parent',parent,'Vertices',v,'Faces',f,'FaceColor',c,'EdgeColor','none');
end

function drawBoxWireframe(parent, d, c)
    v = [ -d(1)/2 -d(2)/2 -d(3)/2; d(1)/2 -d(2)/2 -d(3)/2; d(1)/2 d(2)/2 -d(3)/2; -d(1)/2 d(2)/2 -d(3)/2; ...
          -d(1)/2 -d(2)/2  d(3)/2; d(1)/2 -d(2)/2  d(3)/2; d(1)/2 d(2)/2  d(3)/2; -d(1)/2 d(2)/2  d(3)/2];
    f = [1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8; 1 2 3 4; 5 6 7 8];
    patch('Parent',parent,'Vertices',v,'Faces',f,'FaceColor','none','EdgeColor',c);
end

function drawHorn(parent, ax)
    [x,y,z]=cylinder(0.008,15); z=z*0.003;
    h=surf(x,y,z,'Parent',parent,'FaceColor','w','EdgeColor','none');
    if ax=='y', rotate(h,[1 0 0],90); end
end

function drawSensorPyramid(parent, bx, by, bz, Apex)
    v=[bx(:), by(:), bz(:); Apex]; f=[1 2 5; 2 3 5; 3 4 5; 4 1 5];
    patch('Parent',parent,'Vertices',v,'Faces',f,'FaceColor',[0.3 0.3 0.3],'EdgeColor','w');
end