function [P_faces, props] = pvSubPanelPower(G_now, S_body_norm, panel_config)
% PVSUBPANELPOWER - Computes instantaneous power for 4 lateral sub-panels
%
% Physical geometry: The tracker has 4 flat rectangular solar panels
% arranged in a cross/plus pattern, each extending outward horizontally
% from the central gimbal in the 4 cardinal directions of the body frame.
% All panels lie flat in the horizontal plane (0° tilt), so all normals
% point upward perpendicular to the plane.
%
% Input:
%   G_now         - irradiance W/m² (from PVGIS or computed from elevation)
%   S_body_norm   - sun vector in body frame (normalized or unnormalized)
%   panel_config  - struct with fields: A (m²), eta (0-1)
%                   If empty [], uses defaults: A = 0.05 m², eta = 0.18
%
% Output:
%   P_faces       - [4×1] array: [P_Right; P_Left; P_Up; P_Down]
%                   Power contribution from each lateral panel (Watts)
%   props         - struct exposing: Area, Efficiency, FaceNormals (3×4)
%
% Physics:
%   P_i = G_now × A_face × eta × max(0, dot(S_body_norm, N_i))
%
% Notes:
% - At zenith (sun overhead), all 4 panels receive equal maximum power
% - Power differentiates only when tracker misaligns
% - Passive supplementary harvest layer for off-sun-tracking conditions

    % Set default panel configuration if not provided
    if isempty(panel_config)
        panel_config.A = 0.05;    % 0.05 m² per face (secondary panels)
        panel_config.eta = 0.18;  % 18% efficiency (slightly lower than main)
    end
    
    % Ensure panel_config has the required fields
    if ~isfield(panel_config, 'A')
        panel_config.A = 0.05;
    end
    if ~isfield(panel_config, 'eta')
        panel_config.eta = 0.18;
    end
    
    % Normalize the sun vector if it's not already normalized
    S_norm = S_body_norm / (norm(S_body_norm) + 1e-10);
    
    % Face normal vectors in body frame: 15° outward cant angle (flower model)
    % This creates 4 lateral panels tilted 15° away from vertical, enabling
    % realistic power differentiation during tracking errors and misalignment
    TiltDeg = 15;                      % Outward cant angle [degrees]
    t = sind(TiltDeg);                 % sin(15°) = lateral component
    c = cosd(TiltDeg);                 % cos(15°) = vertical component
    
    % Panel normals: lateral faces tilted 15° outward, creating 3D flower pattern
    N_Right = [t; 0; c];    % Right panel: tilts right
    N_Left  = [-t; 0; c];   % Left panel: tilts left
    N_Up    = [0; t; c];    % Up panel: tilts up
    N_Down  = [0; -t; c];   % Down panel: tilts down (toward horizon)
    
    % Compute incidence angles and power for each face
    % P_i = G_now × A_face × eta × max(0, dot(S_norm, N_i))
    % With all normals at zenith, power simply depends on sun elevation
    
    cos_Right = dot(S_norm, N_Right);
    P_Right = G_now * panel_config.A * panel_config.eta * max(0, cos_Right);
    
    cos_Left = dot(S_norm, N_Left);
    P_Left = G_now * panel_config.A * panel_config.eta * max(0, cos_Left);
    
    cos_Up = dot(S_norm, N_Up);
    P_Up = G_now * panel_config.A * panel_config.eta * max(0, cos_Up);
    
    cos_Down = dot(S_norm, N_Down);
    P_Down = G_now * panel_config.A * panel_config.eta * max(0, cos_Down);
    
    % Return power array
    P_faces = [P_Right; P_Left; P_Up; P_Down];
    
    % Expose owned parameters via props struct
    props = struct();
    props.Area = panel_config.A;
    props.Efficiency = panel_config.eta;
    props.TiltDeg = TiltDeg;  % Cant angle [degrees]
    % Store all 4 normal vectors as a 3×4 matrix (15° cant angle flower pattern)
    props.FaceNormals = [N_Right, N_Left, N_Up, N_Down];
    props.FaceNames = {'Right (+X face)', 'Left (-X face)', 'Up (+Y face)', 'Down (-Y face)'};
    
end
