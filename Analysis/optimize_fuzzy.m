%% ╔════════════════════════════════════════════════════════════════════════╗
%% ║         FUZZY LOGIC CONTROLLER SCALING FACTOR OPTIMIZATION             ║
%% ║                                                                        ║
%% ║  Phase 2.5: Optimize K_e, K_de, K_out using Differential Evolution   ║
%% ║  Compares baseline (all gains = 1.0) vs optimized response            ║
%% ╚════════════════════════════════════════════════════════════════════════╝

clear; clc; close all;

%% ════════════════════════════════════════════════════════════════════════════
%% COST FUNCTION CONSTANTS (Top of script)
%% ════════════════════════════════════════════════════════════════════════════

w1_ITAE = 1.0;               % Weight: time-weighted absolute error
w2_ENERGY = 0.01;            % Weight: control energy (effort)
SS_ERROR_LIMIT = 0.5;        % Steady-state error hard limit (degrees)
SS_ERROR_PENALTY = 1e6;      % Penalty added if SS error exceeds limit
SS_WINDOW = 1.0;             % Final 1 second window for SS error averaging

addpath(genpath(pwd));

fprintf('╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║        FUZZY LOGIC CONTROLLER OPTIMIZATION (Phase 2.5)         ║\n');
fprintf('║        Cost Weights: w₁(ITAE)=%.2f, w₂(Energy)=%.4f              ║\n', w1_ITAE, w2_ENERGY);
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% LOCKED SYSTEM PARAMETERS (Identical to PID Tournament for 1:1 Comparison)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Setting locked system parameters...\n');

BaseParams.MaxTorque       = 0.35;           % N⋅m (frozen)
BaseParams.Inertia         = 0.00015;        % kg⋅m² (frozen)
BaseParams.ViscousDamping  = 0.0359;         % N⋅m⋅s/rad (frozen)
BaseParams.StaticFriction  = 0.02;           % N⋅m stiction (frozen)
BaseParams.DynamicFriction = 0.015;          % N⋅m kinetic (frozen)
BaseParams.ServoGain       = 3.8197;         % Control command gain (frozen)

% Theor physical props for simulation
PhysicsParams.Inertia         = BaseParams.Inertia;
PhysicsParams.ViscousDamping  = BaseParams.ViscousDamping;
PhysicsParams.StaticFriction  = BaseParams.StaticFriction;
PhysicsParams.DynamicFriction = BaseParams.DynamicFriction;
PhysicsParams.MaxTorque       = BaseParams.MaxTorque;
PhysicsParams.DeadbandVel     = 0.05;        % rad/s deadband
PhysicsParams.ServoGain       = BaseParams.ServoGain;

% Control parameters (fixed for FLC)
ControlParams.output_gain       = 1.0;      % Base output gain
ControlParams.defuzz_resolution = 101;      % Defuzzification grid points

%% ════════════════════════════════════════════════════════════════════════════
%% TEST PROFILE: Step Response (10 seconds total)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Defining test profile...\n');

dt = 0.01;                          % Time step: 10 ms
t_duration = 10.0;                  % Total duration: 10 seconds
t_vec = 0:dt:t_duration;
N = length(t_vec);

% Reference trajectory 
% 0-2s:   Hold at 0°
% 2-8s:   Step to 30°
% 8-10s:  Hold at 30°
ref_pan = zeros(N, 1);
ref_tilt = zeros(N, 1);

idx_step_start = find(t_vec >= 2.0, 1);
idx_step_end = find(t_vec >= 8.0, 1);

ref_pan(idx_step_start:idx_step_end) = 30.0;
ref_pan(idx_step_end:end) = 30.0;
ref_tilt(idx_step_start:idx_step_end) = 0.0;    % Tilt stays at 0
ref_tilt(idx_step_end:end) = 0.0;

fprintf('  Test profile: 0-2s (0°) → 2-8s (30°) → 8-10s (hold 30°)\n');
fprintf('  Duration: %.1f s, dt: %.3f s, samples: %d\n\n', t_duration, dt, N);

%% ════════════════════════════════════════════════════════════════════════════
%% OPTIMIZATION SETUP: Custom Differential Evolution
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Initializing custom Differential Evolution optimizer...\n');

% Search bounds for scaling factors
lb = [0.1, 0.1, 0.1];       % Lower bounds: [K_e, K_de, K_out]
ub = [5.0, 5.0, 5.0];       % Upper bounds
param_names = {'K_e', 'K_de', 'K_out'};

% DE parameters (custom implementation)
de_population = 15;         % Population size
de_generations = 40;         % Number of generations
de_F = 0.7;                 % Differential weight
de_CR = 0.8;                % Crossover probability

fprintf('  Search dimension: 3 (K_e, K_de, K_out)\n');
fprintf('  Bounds: [%.1f, %.1f, %.1f] to [%.1f, %.1f, %.1f]\n', lb(1), lb(2), lb(3), ub(1), ub(2), ub(3));
fprintf('  Population: %d, Generations: %d (Custom DE)\n\n', de_population, de_generations);

%% ════════════════════════════════════════════════════════════════════════════
%% OBJECTIVE FUNCTION (Cost Evaluator)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Starting optimization (this may take 3-5 minutes)...\n\n');

[best_gains, best_cost] = customDifferentialEvolution(...
    @(gains) evaluateMdCost(gains, t_vec, ref_pan, ref_tilt, ...
                            BaseParams, PhysicsParams, ControlParams, ...
                            w1_ITAE, w2_ENERGY, SS_ERROR_PENALTY, SS_ERROR_LIMIT, SS_WINDOW), ...
    lb, ub, de_population, de_generations, de_F, de_CR);

fprintf('\n✓ Optimization complete.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% EXTRACT BEST GAINS
%% ════════════════════════════════════════════════════════════════════════════

K_e_opt   = best_gains(1);
K_de_opt  = best_gains(2);
K_out_opt = best_gains(3);

%% ════════════════════════════════════════════════════════════════════════════
%% BASELINE SIMULATION (All Gains = 1.0)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Running baseline simulation (K_e=1.0, K_de=1.0, K_out=1.0)...\n');

BaselineParams = ControlParams;
BaselineParams.K_e = 1.0;
BaselineParams.K_de = 1.0;
BaselineParams.K_out = 1.0;

[t_baseline, ...
 pan_baseline, tilt_baseline, ...
 panvel_baseline, tiltvel_baseline, ...
 cmd_pan_baseline, cmd_tilt_baseline, ...
 error_pan_baseline, error_tilt_baseline] = ...
    simulateFLC(t_vec, ref_pan, ref_tilt, BaselineParams, PhysicsParams);

% Compute baseline cost
[J_baseline, ITAE_baseline, Energy_baseline, SS_err_baseline] = ...
    computeCostMetrics(t_vec, error_pan_baseline, error_tilt_baseline, ...
                       cmd_pan_baseline, cmd_tilt_baseline, ...
                       w1_ITAE, w2_ENERGY, SS_ERROR_LIMIT, SS_ERROR_PENALTY, SS_WINDOW);

%% ════════════════════════════════════════════════════════════════════════════
%% OPTIMIZED SIMULATION (Best Gains)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Running optimized simulation (K_e=%.4f, K_de=%.4f, K_out=%.4f)...\n', K_e_opt, K_de_opt, K_out_opt);

OptimParams = ControlParams;
OptimParams.K_e = K_e_opt;
OptimParams.K_de = K_de_opt;
OptimParams.K_out = K_out_opt;

[t_optim, ...
 pan_optim, tilt_optim, ...
 panvel_optim, tiltvel_optim, ...
 cmd_pan_optim, cmd_tilt_optim, ...
 error_pan_optim, error_tilt_optim] = ...
    simulateFLC(t_vec, ref_pan, ref_tilt, OptimParams, PhysicsParams);

% Compute optimized cost
[J_optim, ITAE_optim, Energy_optim, SS_err_optim] = ...
    computeCostMetrics(t_vec, error_pan_optim, error_tilt_optim, ...
                       cmd_pan_optim, cmd_tilt_optim, ...
                       w1_ITAE, w2_ENERGY, SS_ERROR_LIMIT, SS_ERROR_PENALTY, SS_WINDOW);

%% ════════════════════════════════════════════════════════════════════════════
%% CONSOLE REPORT
%% ════════════════════════════════════════════════════════════════════════════

fprintf('\n');
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('         === FUZZY OPTIMIZATION RESULTS ===\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

fprintf('OPTIMIZED PARAMETERS:\n');
fprintf('  Best K_e       : %.4f\n', K_e_opt);
fprintf('  Best K_de      : %.4f\n', K_de_opt);
fprintf('  Best K_out     : %.4f\n\n', K_out_opt);

fprintf('PERFORMANCE METRICS:\n');
fprintf('  Baseline:\n');
fprintf('    ITAE Score   : %.4f\n', ITAE_baseline);
fprintf('    Energy Cost  : %.4f\n', Energy_baseline);
fprintf('    Total J      : %.4f\n', J_baseline);
fprintf('    SS Error (°) : %.4f\n\n', SS_err_baseline);

fprintf('  Optimized:\n');
fprintf('    ITAE Score   : %.4f\n', ITAE_optim);
fprintf('    Energy Cost  : %.4f\n', Energy_optim);
fprintf('    Total J      : %.4f\n', J_optim);
fprintf('    SS Error (°) : %.4f\n\n', SS_err_optim);

fprintf('IMPROVEMENT:\n');
improvement_pct = (J_baseline - J_optim) / J_baseline * 100;
itae_improvement_pct = (ITAE_baseline - ITAE_optim) / ITAE_baseline * 100;
fprintf('  Total Cost Change : %.2f%% (value reduced)\n', improvement_pct);
fprintf('  ITAE Improvement  : %.2f%%\n', itae_improvement_pct);
fprintf('═══════════════════════════════════════════════════════════════\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% PLOTTING: Comparison Figure
%% ════════════════════════════════════════════════════════════════════════════

fprintf('Generating comparison plots...\n\n');

fig = figure('Name', 'FLC Scaling Factor Optimization - Baseline vs Optimized', ...
             'NumberTitle', 'off', 'Position', [100, 100, 1400, 600]);

% Subplot 1: Pan Axis Response
ax1 = subplot(2, 2, 1);
hold on; grid on;
plot(t_baseline, ref_pan, 'k--', 'LineWidth', 2.0, 'DisplayName', 'Reference Setpoint');
plot(t_baseline, pan_baseline, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Baseline (K=1.0)');
plot(t_optim, pan_optim, 'r-', 'LineWidth', 1.5, 'DisplayName', sprintf('Optimized (K_e=%.2f, K_de=%.2f, K_out=%.2f)', K_e_opt, K_de_opt, K_out_opt));
xlabel('Time (s)', 'FontSize', 11);
ylabel('Pan Position (°)', 'FontSize', 11);
title('Pan Axis - Position Response', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 10);
set(ax1, 'FontSize', 10);

% Subplot 2: Pan Axis Error
ax2 = subplot(2, 2, 2);
hold on; grid on;
plot(t_baseline, error_pan_baseline, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Baseline Error');
plot(t_optim, error_pan_optim, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Optimized Error');
axline([8, 0], 'Color', 'gray', 'LineStyle', ':', 'Alpha', 0.5);
text(8.2, max(error_pan_baseline)*0.8, 'SS window', 'FontSize', 9, 'Color', 'gray');
xlabel('Time (s)', 'FontSize', 11);
ylabel('Pan Error (°)', 'FontSize', 11);
title('Pan Axis - Tracking Error', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 10);
set(ax2, 'FontSize', 10);

% Subplot 3: Pan Velocity Command
ax3 = subplot(2, 2, 3);
hold on; grid on;
plot(t_baseline, cmd_pan_baseline, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Baseline Command');
plot(t_optim, cmd_pan_optim, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Optimized Command');
xlabel('Time (s)', 'FontSize', 11);
ylabel('Pan Velocity Command (°/s)', 'FontSize', 11);
title('Pan Axis - Control Command', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 10);
set(ax3, 'FontSize', 10);

% Subplot 4: Cost Metrics Comparison
ax4 = subplot(2, 2, 4);
hold on; grid on;
categories = {'ITAE', 'Energy', 'Total J'};
baseline_metrics = [ITAE_baseline, Energy_baseline, J_baseline];
optim_metrics = [ITAE_optim, Energy_optim, J_optim];

x_pos = 1:3;
bar_width = 0.35;

bars1 = bar(x_pos - bar_width/2, baseline_metrics, bar_width, 'FaceColor', 'b', 'EdgeColor', 'b', 'Alpha', 0.7);
bars2 = bar(x_pos + bar_width/2, optim_metrics, bar_width, 'FaceColor', 'r', 'EdgeColor', 'r', 'Alpha', 0.7);

set(ax4, 'XTick', x_pos, 'XTickLabel', categories);
ylabel('Cost Value', 'FontSize', 11);
title('Cost Metrics Comparison', 'FontSize', 12, 'FontWeight', 'bold');
legend([bars1, bars2], {'Baseline', 'Optimized'}, 'Location', 'best', 'FontSize', 10);
set(ax4, 'FontSize', 10);

% Add improvement text
textstr = sprintf('Improvement: %.1f%%', improvement_pct);
annotation('textbox', [0.65, 0.15, 0.25, 0.1], 'String', textstr, ...
           'EdgeColor', 'green', 'BackgroundColor', 'lightyellow', ...
           'FontSize', 11, 'FontWeight', 'bold');

% Main title
sgtitle(['Fuzzy Logic Controller Scaling Optimization - Pan Axis Response', newline, ...
         sprintf('w₁=%.2f (ITAE), w₂=%.4f (Energy)', w1_ITAE, w2_ENERGY)], ...
        'FontSize', 13, 'FontWeight', 'bold');

drawnow;

% Save figure
fig_path = sprintf('Results/fuzzy_optimization_%s.fig', datestr(now, 'yyyy-mm-dd_HH-MM-SS'));
if ~isfolder('Results')
    mkdir('Results');
end
savefig(fig, fig_path);
fprintf('✓ Comparison figure saved: %s\n', fig_path);

fprintf('\n✓ Optimization complete. Results are ready.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% NESTED FUNCTIONS
%% ════════════════════════════════════════════════════════════════════════════

function [J, ITAE, Energy, SS_err] = evaluateMdCost(gains, t_vec, ref_pan, ref_tilt, ...
                                                     BaseParams, PhysicsParams, ControlParams, ...
                                                     w1, w2, penalty, ss_limit, ss_window)
    % Evaluate cost function for given gains
    
    K_e = gains(1);
    K_de = gains(2);
    K_out = gains(3);
    
    % Set gains in control parameters
    params = ControlParams;
    params.K_e = K_e;
    params.K_de = K_de;
    params.K_out = K_out;
    
    % Run simulation
    [t, pan, tilt, panvel, tiltvel, cmd_pan, cmd_tilt, error_pan, error_tilt] = ...
        simulateFLC(t_vec, ref_pan, ref_tilt, params, PhysicsParams);
    
    % Compute metrics
    [J, ITAE, Energy, SS_err] = computeCostMetrics(t, error_pan, error_tilt, ...
                                                    cmd_pan, cmd_tilt, ...
                                                    w1, w2, ss_limit, penalty, ss_window);
end

function [t, pan, tilt, panvel, tiltvel, cmd_pan, cmd_tilt, error_pan, error_tilt] = ...
    simulateFLC(t_vec, ref_pan, ref_tilt, ControlParams, PhysicsParams)
    % Simulate FLC with given parameters
    
    N = length(t_vec);
    dt = t_vec(2) - t_vec(1);
    
    % Initialize state (with extra space for k+1 indexing)
    pan = zeros(N+1, 1);
    tilt = zeros(N+1, 1);
    panvel = zeros(N+1, 1);
    tiltvel = zeros(N+1, 1);
    cmd_pan = zeros(N, 1);
    cmd_tilt = zeros(N, 1);
    error_pan = zeros(N, 1);
    error_tilt = zeros(N, 1);
    
    % Derivative filtering for error rate (low-pass)
    filter_alpha = 0.3;
    pan_error_filt = 0;
    tilt_error_filt = 0;
    pan_error_prev = 0;
    tilt_error_prev = 0;
    
    for k = 1:N
        % Current errors
        error_pan(k) = ref_pan(k) - pan(k);
        error_tilt(k) = ref_tilt(k) - tilt(k);
        
        % Filtered error rates (numerical derivative + low-pass)
        if k > 1
            pan_error_rate_raw = (error_pan(k) - pan_error_prev) / dt;
            tilt_error_rate_raw = (error_tilt(k) - tilt_error_prev) / dt;
            
            pan_error_filt = filter_alpha * pan_error_rate_raw + (1 - filter_alpha) * pan_error_filt;
            tilt_error_filt = filter_alpha * tilt_error_rate_raw + (1 - filter_alpha) * tilt_error_filt;
        end
        
        pan_error_prev = error_pan(k);
        tilt_error_prev = error_tilt(k);
        
        % Create error signal for FLC
        ErrorSignal = struct('e_pan', error_pan(k), 'e_tilt', error_tilt(k), ...
                            'de_pan', pan_error_filt, 'de_tilt', tilt_error_filt, ...
                            'mode', 'TRACKING');
        
        % FLC evaluation
        ControlState = struct('placeholder', 0);
        [VelCmd, ~, ~] = FuzzyLogicController(ErrorSignal, ControlState, ControlParams, dt);
        
        cmd_pan(k) = VelCmd.v_pan;
        cmd_tilt(k) = VelCmd.v_tilt;
        
        % Simple integrator dynamics (pan axis only for simplicity)
        % Velocity command → Position update with friction compensation
        tau_cmd = ControlParams.K_e; % Use K_e as placeholder for control authority
        
        % Simulate motor/servo response (1st order approximation)
        tau_motor = 0.05; % 50 ms servo response time
        panvel(k+1) = panvel(k) + (cmd_pan(k) - panvel(k)) * (dt / tau_motor);
        
        % Limit velocity
        panvel(k+1) = max(min(panvel(k+1), 40), -40); % ±40 deg/s limit
        
        % Update position
        if k < N
            pan(k+1) = pan(k) + panvel(k+1) * dt;
            
            % Add simple deadzone to simulate friction
            if abs(panvel(k+1)) < 0.5
                pan(k+1) = pan(k); % Friction stops motion for very small velocities
            end
        end
    end
    
    % Ensure t vector is a column vector
    t = t_vec(:);
    
    % Trim outputs to match t vector length
    pan = pan(1:N);
    tilt = tilt(1:N);
    panvel = panvel(1:N);
    tiltvel = tiltvel(1:N);
end

function [J, ITAE, Energy, SS_err] = computeCostMetrics(t, error_pan, error_tilt, ...
                                                         cmd_pan, cmd_tilt, ...
                                                         w1, w2, ss_limit, penalty, ss_window)
    % Compute cost function metrics
    
    dt = t(2) - t(1);
    
    % ITAE: Integral Time-weighted Absolute Error
    itae_pan = sum(t .* abs(error_pan) * dt);
    itae_tilt = sum(t .* abs(error_tilt) * dt);
    ITAE = itae_pan + itae_tilt;
    
    % Energy: Integral of control effort squared
    energy_pan = sum(cmd_pan.^2) * dt;
    energy_tilt = sum(cmd_tilt.^2) * dt;
    Energy = energy_pan + energy_tilt;
    
    % Steady-state error (average of final ss_window seconds)
    idx_ss_start = find(t >= (max(t) - ss_window), 1);
    SS_err = mean(abs(error_pan(idx_ss_start:end)));
    
    % Total cost
    J = w1 * ITAE + w2 * Energy;
    
    % Hard penalty for excessive steady-state error
    if SS_err > ss_limit
        J = J + penalty;
    end
end

function [best_x, best_f] = customDifferentialEvolution(fun, lb, ub, pop_size, generations, F, CR)
    % Custom Differential Evolution optimizer
    % fun: objective function handle
    % lb, ub: lower and upper bounds (vectors)
    % pop_size: population size
    % generations: number of generations
    % F: scaling factor (0.7 typical)
    % CR: crossover rate (0.8 typical)
    
    n_vars = length(lb);
    
    % Initialize population randomly within bounds
    population = zeros(pop_size, n_vars);
    for i = 1:pop_size
        population(i, :) = lb + rand(1, n_vars) .* (ub - lb);
    end
    
    % Evaluate initial population
    fitness = zeros(pop_size, 1);
    for i = 1:pop_size
        fitness(i) = fun(population(i, :));
    end
    
    % Main DE loop
    for gen = 1:generations
        fprintf('  Generation %d/%d\n', gen, generations);
        
        for i = 1:pop_size
            % Select three random individuals (different from current)
            indices = setdiff(1:pop_size, i);
            selected = indices(randperm(length(indices), 3));
            a = selected(1);
            b = selected(2);
            c = selected(3);
            
            % Mutation: DE/rand/1 strategy
            mutant = population(a, :) + F * (population(b, :) - population(c, :));
            
            % Boundary handling: clip to bounds
            mutant = max(min(mutant, ub), lb);
            
            % Crossover: binomial (uniform)
            trial = population(i, :);
            r_j = randi(n_vars); % Ensure at least one dimension from mutant
            for j = 1:n_vars
                if rand < CR || j == r_j
                    trial(j) = mutant(j);
                end
            end
            
            % Selection
            trial_fitness = fun(trial);
            if trial_fitness < fitness(i)
                population(i, :) = trial;
                fitness(i) = trial_fitness;
            end
        end
        
        % Track best
        [best_f, best_idx] = min(fitness);
        best_x = population(best_idx, :);
        
        fprintf('    Best fitness: %.6f (K_e=%.4f, K_de=%.4f, K_out=%.4f)\n', ...
                best_f, best_x(1), best_x(2), best_x(3));
    end
    
    % Final best solution
    [best_f, best_idx] = min(fitness);
    best_x = population(best_idx, :);
end

