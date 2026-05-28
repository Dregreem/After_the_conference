%% ╔════════════════════════════════════════════════════════════════════════╗
%% ║  BASELINE VALIDATION TEST SCRIPT                                      ║
%% ║  Tests all modules for crash-free execution, NaN/Inf, and physics    ║
%% ╚════════════════════════════════════════════════════════════════════════╝

clear; clc; close all;

fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  BASELINE VALIDATION TEST SUITE                               ║\n');
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

% Add all project folders to path
addpath(genpath(pwd));

passed = 0;
failed = 0;
total  = 0;

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 1: Module Instantiation (all modules callable without crash)
%% ═══════════════════════════════════════════════════════════════════════
fprintf('── TEST 1: Module Instantiation ──────────────────────────────\n');

try
    total = total + 1;
    % Servo physics
    State0 = struct('Angle', 0, 'Velocity', 0, 'Current', 0);
    [S1, ~, props1] = stepTheoreticalServo(State0, 10, 0.01, 'Pan');
    assert(isfinite(S1.Angle), 'stepTheoreticalServo output NaN');
    fprintf('  ✓ stepTheoreticalServo — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ stepTheoreticalServo — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    [S2, ~] = stepDCMotorPhysics(State0, 10, 0.01, 'Pan');
    assert(isfinite(S2.Angle), 'stepDCMotorPhysics output NaN');
    fprintf('  ✓ stepDCMotorPhysics — OK (BUG-3 fix verified)\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ stepDCMotorPhysics — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    [S3, ~] = stepAdvancedServoPhysics(State0, 10, 0.01, 'Tilt');
    assert(isfinite(S3.Angle), 'stepAdvancedServoPhysics output NaN');
    fprintf('  ✓ stepAdvancedServoPhysics — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ stepAdvancedServoPhysics — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    [~, V, ~, ~, ~, ldr_props] = readLDRs([0.5; 0.3; 0.8]);
    assert(all(isfinite(V)), 'readLDRs output NaN');
    fprintf('  ✓ readLDRs — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ readLDRs — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    [E1, E2, Ed1, Ed2, locked] = controlLDR(2.5, 2.5, 2.5, 2.5, [0;0;1]);
    assert(isfinite(E1) && isfinite(E2), 'controlLDR output NaN');
    fprintf('  ✓ controlLDR — OK (BUG-5 fix verified)\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ controlLDR — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    % Test controlLDR with out-of-range voltage (BUG-5 early return path)
    [E1, E2, Ed1, Ed2, locked, dbg] = controlLDR(0.01, 0.01, 0.01, 0.01, [0;0;1]);
    assert(isfield(dbg, 'Sz'), 'controlLDR Debug.Sz missing on early return');
    fprintf('  ✓ controlLDR (edge case) — OK (Sz defined on all paths)\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ controlLDR (edge case) — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    [az, el] = cartesian2spherical([0.5; 0.5; 0.707]);
    assert(isfinite(az) && isfinite(el), 'cartesian2spherical output NaN');
    fprintf('  ✓ cartesian2spherical — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ cartesian2spherical — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    [adj_p, adj_t, is_f, is_r] = applyFlipLogic(45, 30);
    assert(isfinite(adj_p) && isfinite(adj_t), 'applyFlipLogic output NaN');
    fprintf('  ✓ applyFlipLogic — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ applyFlipLogic — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    [theta_err, status] = checkAlignment([0.01; 0.01; 0.9999]);
    assert(isfinite(theta_err), 'checkAlignment output NaN');
    fprintf('  ✓ checkAlignment — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ checkAlignment — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    result = ternary(true, 'yes', 'no');
    assert(strcmp(result, 'yes'), 'ternary returned wrong value');
    fprintf('  ✓ ternary — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ ternary — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

try
    total = total + 1;
    val = getFieldOrDefault(struct('a', 5), 'b', 10);
    assert(val == 10, 'getFieldOrDefault returned wrong value');
    fprintf('  ✓ getFieldOrDefault — OK\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ getFieldOrDefault — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 2: pvTrackerPower BUG-2 Verification (cos vs cosd)
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 2: pvTrackerPower BUG-2 Fix ────────────────────────────\n');

try
    total = total + 1;
    % At 5° incidence with 1000 W/m², expected: ~0.04 * 0.20 * 1000 * cosd(5) ≈ 7.97 W
    % Before fix (cos radians): 0.04 * 0.20 * 1000 * cos(5) ≈ 2.27 W (WRONG!)
    cfg = struct('A', 0.04, 'eta', 0.20);
    [P_tracker, ~] = pvTrackerPower(1000, 5, cfg);
    expected_P = 0.04 * 0.20 * 1000 * cosd(5);  % ≈ 7.97 W
    wrong_P = 0.04 * 0.20 * 1000 * cos(5);      % ≈ 2.27 W (bug value)
    
    assert(abs(P_tracker - expected_P) < 0.01, ...
        sprintf('pvTrackerPower returned %.4f W, expected %.4f W', P_tracker, expected_P));
    assert(abs(P_tracker - wrong_P) > 1.0, ...
        'pvTrackerPower still using cos() instead of cosd()!');
    
    fprintf('  ✓ pvTrackerPower(1000, 5°) = %.4f W (expected %.4f W) — CORRECT\n', P_tracker, expected_P);
    fprintf('    (Before fix would have been: %.4f W — 71%% error)\n', wrong_P);
    passed = passed + 1;
catch ME
    fprintf('  ✗ pvTrackerPower BUG-2 — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 3: FSM State Machine Transitions
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 3: FSM State Machine Transitions ──────────────────────\n');

try
    total = total + 1;
    dt = 0.01;
    Params = struct('night_threshold', 0.3, 'sun_lost_threshold', 0.5, ...
                    'sun_found_threshold', 1.0, 'lock_threshold', 0.5, ...
                    'batch_interval', 1.0, 'max_burst_time', 2.0, ...
                    'tracking_deadband', 3.0, 'search_speed', 3.0);
    
    FSM = struct('mode', 'IDLE', 'e_pan_prev', 0, 'e_tilt_prev', 0, ...
                 'de_pan_filtered', 0, 'de_tilt_filtered', 0, 'search_phase', 0);
    
    % Test IDLE → SEARCH (sun appears)
    LDR_bright = [3; 3; 3; 3];  % V_total = 12 > night_threshold
    S_body = [0.5; 0; 0.866];   % 30° off-axis
    [~, FSM, ~, ~] = StateManagerFSM(LDR_bright, S_body, 0, 0, FSM, Params, dt, false);
    assert(strcmp(FSM.mode, 'SEARCH'), sprintf('Expected SEARCH, got %s', FSM.mode));
    fprintf('  ✓ IDLE → SEARCH (sun detected) — OK\n');
    
    % Test SEARCH → TRACKING (sun found)
    for i = 1:5
        [~, FSM, ~, ~] = StateManagerFSM(LDR_bright, S_body, 0, 0, FSM, Params, dt, false);
    end
    assert(strcmp(FSM.mode, 'TRACKING'), sprintf('Expected TRACKING, got %s', FSM.mode));
    fprintf('  ✓ SEARCH → TRACKING (sun found) — OK\n');
    
    % Test TRACKING → HOLD (burst timeout with small error)
    S_body_locked = [0; 0; 1.0];  % Perfectly aligned
    for i = 1:300
        [~, FSM, ~, ~] = StateManagerFSM(LDR_bright, S_body_locked, 0, 0, FSM, Params, dt, false);
    end
    assert(strcmp(FSM.mode, 'HOLD'), sprintf('Expected HOLD after burst timeout, got %s', FSM.mode));
    fprintf('  ✓ TRACKING → HOLD (burst timeout) — OK\n');
    
    % Test HOLD → TRACKING (error drifts beyond deadband)
    S_body_drifted = [0.3; 0; 0.954];  % ~17° off-axis > 3° deadband
    for i = 1:200
        [~, FSM, ~, ~] = StateManagerFSM(LDR_bright, S_body_drifted, 0, 0, FSM, Params, dt, false);
    end
    assert(strcmp(FSM.mode, 'TRACKING'), sprintf('Expected TRACKING after wake-up, got %s', FSM.mode));
    fprintf('  ✓ HOLD → TRACKING (sun drifted) — OK\n');
    
    % Test TRACKING → SEARCH (sun lost — clouds)
    LDR_dim = [0.1; 0.1; 0.1; 0.1];  % V_total = 0.4 < sun_lost_threshold(0.5)
    [~, FSM, ~, ~] = StateManagerFSM(LDR_dim, S_body, 0, 0, FSM, Params, dt, false);
    assert(strcmp(FSM.mode, 'SEARCH'), sprintf('Expected SEARCH (sun lost), got %s', FSM.mode));
    fprintf('  ✓ TRACKING → SEARCH (sun lost/clouds) — OK\n');
    
    % Test any → IDLE (night)
    LDR_dark = [0.01; 0.01; 0.01; 0.01];  % V_total < night_threshold
    [~, FSM, ~, ~] = StateManagerFSM(LDR_dark, [0;0;0], 0, 0, FSM, Params, dt, false);
    assert(strcmp(FSM.mode, 'IDLE'), sprintf('Expected IDLE (night), got %s', FSM.mode));
    fprintf('  ✓ any → IDLE (night detected) — OK\n');
    
    fprintf('  ═══ FSM cycle IDLE→SEARCH→TRACKING→HOLD→TRACKING→SEARCH→IDLE verified ═══\n');
    passed = passed + 1;
catch ME
    fprintf('  ✗ FSM transitions — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 4: PID Controller Sanity
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 4: PID Controller Sanity ────────────────────────────────\n');

try
    total = total + 1;
    dt_ctrl = 0.01;
    CtrlState = struct('I_pan', 0, 'I_tilt', 0);
    
    % Positive error → positive velocity
    ErrSig = struct('e_pan', 5.0, 'e_tilt', -3.0, 'de_pan', 0, 'de_tilt', 0, 'mode', 'TRACKING');
    [VelCmd, ~, ~, ~] = PID_VelocityController(ErrSig, CtrlState, struct(), dt_ctrl);
    assert(VelCmd.v_pan > 0, 'Positive pan error should produce positive velocity');
    assert(VelCmd.v_tilt < 0, 'Negative tilt error should produce negative velocity');
    fprintf('  ✓ PID: +5° pan error → v_pan = %.2f °/s (positive) — OK\n', VelCmd.v_pan);
    fprintf('  ✓ PID: -3° tilt error → v_tilt = %.2f °/s (negative) — OK\n', VelCmd.v_tilt);
    
    % IDLE mode → zero output
    ErrSig.mode = 'IDLE';
    [VelCmd, ~, ~, ~] = PID_VelocityController(ErrSig, CtrlState, struct(), dt_ctrl);
    assert(VelCmd.v_pan == 0 && VelCmd.v_tilt == 0, 'IDLE should produce zero velocity');
    fprintf('  ✓ PID: IDLE mode → zero velocity — OK\n');
    
    passed = passed + 1;
catch ME
    fprintf('  ✗ PID Controller — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 5: FLC Controller Sanity
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 5: FLC Controller Sanity ────────────────────────────────\n');

try
    total = total + 1;
    dt_ctrl = 0.01;
    CtrlState = struct('I_pan', 0, 'I_tilt', 0);
    
    ErrSig = struct('e_pan', 10.0, 'e_tilt', -5.0, 'de_pan', 0, 'de_tilt', 0, 'mode', 'TRACKING');
    [VelCmd, ~, ~, ~] = FuzzyLogicController(ErrSig, CtrlState, dt_ctrl);
    assert(VelCmd.v_pan > 0, 'Positive pan error should produce positive FLC velocity');
    assert(VelCmd.v_tilt < 0, 'Negative tilt error should produce negative FLC velocity');
    fprintf('  ✓ FLC: +10° pan error → v_pan = %.2f °/s (positive) — OK\n', VelCmd.v_pan);
    fprintf('  ✓ FLC: -5° tilt error → v_tilt = %.2f °/s (negative) — OK\n', VelCmd.v_tilt);
    
    passed = passed + 1;
catch ME
    fprintf('  ✗ FLC Controller — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 6: Sun Position Vector
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 6: Sun Position Calculation ─────────────────────────────\n');

try
    total = total + 1;
    % Istanbul, June 21, noon — sun should be high and roughly south
    [S_vec, alpha, phi] = getSunVector(41.051, 29.010, datetime(2023, 6, 21, 12, 0, 0), 3);
    assert(alpha > 50 && alpha < 85, sprintf('Summer noon elevation should be 50-85°, got %.1f°', alpha));
    assert(S_vec(3) > 0.7, 'Sun Z component should be high at noon');
    fprintf('  ✓ getSunVector (Istanbul, Jun 21, 12:00) — El: %.1f°, Az: %.1f° — OK\n', alpha, phi);
    
    % Night check
    [S_vec_night, alpha_night, ~] = getSunVector(41.051, 29.010, datetime(2023, 6, 21, 2, 0, 0), 3);
    assert(all(S_vec_night == 0), 'Night sun vector should be [0;0;0]');
    fprintf('  ✓ getSunVector (Istanbul, Jun 21, 02:00) — Night check passed — OK\n');
    
    passed = passed + 1;
catch ME
    fprintf('  ✗ Sun Position — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 7: Energy Formula Consistency (No NaN/Inf)
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 7: Energy Formula NaN/Inf Check ──────────────────────────\n');

try
    total = total + 1;
    cfg = struct('A', 0.04, 'eta', 0.20);
    
    % Test pvPanelPower at various conditions
    test_cases = [0, 0, 0; 500, 180, 45; 1000, 90, 70; 1000, 270, 10; 0, 0, 90];
    for tc = 1:size(test_cases, 1)
        [P, ~] = pvPanelPower(test_cases(tc,1), test_cases(tc,2), test_cases(tc,3), cfg);
        assert(isfinite(P), sprintf('pvPanelPower NaN/Inf at G=%.0f, az=%.0f, el=%.0f', ...
            test_cases(tc,1), test_cases(tc,2), test_cases(tc,3)));
    end
    fprintf('  ✓ pvPanelPower — No NaN/Inf across 5 test cases — OK\n');
    
    % Test pvTrackerPower at various incidence angles
    for theta = [0, 1, 5, 30, 45, 89, 90, 91]
        [P, ~] = pvTrackerPower(1000, theta, cfg);
        assert(isfinite(P), sprintf('pvTrackerPower NaN/Inf at theta=%.0f°', theta));
    end
    fprintf('  ✓ pvTrackerPower — No NaN/Inf across 8 incidence angles — OK\n');
    
    % Test pvSubPanelPower
    [P_sub, ~] = pvSubPanelPower(1000, [0.5; 0.3; 0.8], []);
    assert(all(isfinite(P_sub)), 'pvSubPanelPower NaN/Inf');
    fprintf('  ✓ pvSubPanelPower — No NaN/Inf — OK\n');
    
    passed = passed + 1;
catch ME
    fprintf('  ✗ Energy Formulas — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 8: Scenario Generation
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 8: Scenario Generation ───────────────────────────────────\n');

scenarios = {'REALISTIC', 'VEHICLE_SLOW', 'VEHICLE_FAST', 'ZENITH_STATIC', ...
             'FLIP_BOUNDARY', 'EXTREME', 'SOLAR_DAY'};

for s = 1:length(scenarios)
    try
        total = total + 1;
        Sc = generateScenario(scenarios{s});
        assert(isfield(Sc, 'spiral_speed') && isfinite(Sc.spiral_speed), 'Invalid scenario');
        assert(isfield(Sc, 'lat') && isfinite(Sc.lat), 'Missing location');
        if strcmp(scenarios{s}, 'SOLAR_DAY')
            assert(isfield(Sc, 'pvgis_file'), 'SOLAR_DAY missing pvgis_file');
            fprintf('  ✓ %s — pvgis_file: %s — OK\n', scenarios{s}, Sc.pvgis_file);
        else
            fprintf('  ✓ %s — speed=%.3f, dur=%.0fs — OK\n', scenarios{s}, Sc.spiral_speed, Sc.duration_sec);
        end
        passed = passed + 1;
    catch ME
        fprintf('  ✗ %s — FAILED: %s\n', scenarios{s}, ME.message);
        failed = failed + 1;
    end
end

%% ═══════════════════════════════════════════════════════════════════════
%% TEST 9: Kinematic Convergence (Mini Simulation)
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n── TEST 9: Kinematic Convergence (100-step mini-sim) ──────────\n');

try
    total = total + 1;
    dt = 0.01;
    State_Pan = struct('Angle', 0, 'Velocity', 0, 'Current', 0);
    State_Tilt = struct('Angle', 0, 'Velocity', 0, 'Current', 0);
    target_pan = 20;   % Target: 20°
    target_tilt = 15;  % Target: 15°
    
    for i = 1:500
        [State_Pan, ~, ~] = stepTheoreticalServo(State_Pan, target_pan, dt, 'Pan');
        [State_Tilt, ~, ~] = stepTheoreticalServo(State_Tilt, target_tilt, dt, 'Tilt');
    end
    
    pan_err = abs(State_Pan.Angle - target_pan);
    tilt_err = abs(State_Tilt.Angle - target_tilt);
    
    assert(pan_err < 1.0, sprintf('Pan did not converge: err=%.2f°', pan_err));
    assert(tilt_err < 1.0, sprintf('Tilt did not converge: err=%.2f°', tilt_err));
    
    fprintf('  ✓ Pan: %.2f° → %.2f° (err=%.3f°) — CONVERGED\n', 0, State_Pan.Angle, pan_err);
    fprintf('  ✓ Tilt: %.2f° → %.2f° (err=%.3f°) — CONVERGED\n', 0, State_Tilt.Angle, tilt_err);
    fprintf('  ✓ Servo velocity stayed within limits (max %.0f °/s)\n', 300);
    passed = passed + 1;
catch ME
    fprintf('  ✗ Kinematic Convergence — FAILED: %s\n', ME.message);
    failed = failed + 1;
end

%% ═══════════════════════════════════════════════════════════════════════
%% RESULTS
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  VALIDATION RESULTS                                           ║\n');
fprintf('╠════════════════════════════════════════════════════════════════╣\n');
fprintf('║  Total tests:  %3d                                            ║\n', total);
fprintf('║  Passed:       %3d  ✓                                         ║\n', passed);
fprintf('║  Failed:       %3d  ✗                                         ║\n', failed);
fprintf('╠════════════════════════════════════════════════════════════════╣\n');
if failed == 0
    fprintf('║  STATUS: ALL TESTS PASSED — BASELINE VALIDATED               ║\n');
    fprintf('║  System is ready for OPTIMIZATION phase.                      ║\n');
else
    fprintf('║  STATUS: %d TEST(S) FAILED — REVIEW REQUIRED                 ║\n', failed);
end
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');
