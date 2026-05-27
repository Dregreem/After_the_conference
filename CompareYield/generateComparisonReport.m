function generateComparisonReport(results, output_dir)
% GENERATECOMPARISONREPORT - Write CSV summary and bar chart from benchmark results
%
% USAGE:
%   generateComparisonReport(results, output_dir)
%
% results is an (nScenario x nController) struct with fields:
%   .scenario, .controller, .Metrics, .success

if nargin < 2 || isempty(output_dir)
    output_dir = 'Results';
end

[nS, nC] = size(results);

%% ── CSV EXPORT ──────────────────────────────────────────────────────────────
csv_file = fullfile(output_dir, 'comparison_summary.csv');
fid = fopen(csv_file, 'w');
fprintf(fid, 'Scenario,Controller,Mean_Error_deg,Max_Error_deg,Lock_Pct,');
fprintf(fid, 'Motor_Energy_Wh,Tracker_Yield_Wh,Fixed_Yield_Wh,Net_Gain_Pct\n');

for s = 1:nS
    for c = 1:nC
        r = results(s,c);
        if r.success && ~isempty(fieldnames(r.Metrics))
            M = r.Metrics;
            fprintf(fid, '%s,%s,%.4f,%.4f,%.2f,%.6f,%.6f,%.6f,%.2f\n', ...
                r.scenario, upper(r.controller), ...
                safeGet(M,'mean_incidence',NaN), ...
                safeGet(M,'max_incidence',NaN), ...
                safeGet(M,'lock_percentage',NaN), ...
                safeGet(M,'total_energy_Wh',NaN), ...
                safeGet(M,'net_tracker_yield_Wh',NaN), ...
                safeGet(M,'fixed_yield_Wh',NaN), ...
                safeGet(M,'gain_vs_fixed',NaN));
        else
            fprintf(fid, '%s,%s,NaN,NaN,NaN,NaN,NaN,NaN,NaN\n', ...
                r.scenario, upper(r.controller));
        end
    end
end
fclose(fid);
fprintf('  ✓ CSV saved: %s\n', csv_file);

%% ── DATA EXTRACTION FOR PLOTTING ────────────────────────────────────────────

% Collect unique scenario and controller labels
scenarios   = unique({results(:).scenario},   'stable');
controllers = unique({results(:).controller}, 'stable');
nS2 = length(scenarios);
nC2 = length(controllers);

% Colour palette: blue for PID, orange for FLC, then cycle
palette = [0.20 0.45 0.75;   % blue
           0.93 0.51 0.15;   % orange
           0.22 0.56 0.24;   % green
           0.76 0.22 0.22];  % red
if nC2 > size(palette,1)
    palette = lines(nC2);
end

% Build matrices: rows = scenarios, cols = controllers
mat_mean   = nan(nS2, nC2);
mat_energy = nan(nS2, nC2);
mat_yield  = nan(nS2, nC2);
mat_lock   = nan(nS2, nC2);
mat_gain   = nan(nS2, nC2);

for s = 1:nS
    for c = 1:nC
        r = results(s,c);
        if ~r.success || isempty(fieldnames(r.Metrics)), continue; end
        si = find(strcmp(scenarios,   r.scenario),   1);
        ci = find(strcmp(controllers, r.controller), 1);
        if isempty(si) || isempty(ci), continue; end
        M = r.Metrics;
        mat_mean(si,ci)   = safeGet(M,'mean_incidence',     NaN);
        mat_energy(si,ci) = safeGet(M,'total_energy_Wh',    NaN);
        mat_yield(si,ci)  = safeGet(M,'net_tracker_yield_Wh',NaN);
        mat_lock(si,ci)   = safeGet(M,'lock_percentage',    NaN);
        mat_gain(si,ci)   = safeGet(M,'gain_vs_fixed',      NaN);
    end
end

ctrl_labels = upper(controllers);

%% ── FIGURE: CONTROLLER COMPARISON (3 subplots) ──────────────────────────────
fig = figure('Visible','off','Name','Controller Comparison','NumberTitle','off');
set(fig, 'Position', [100 100 1400 900]);

% ── Subplot 1: Mean incidence error ─────────────────────────────────────────
ax1 = subplot(3,1,1);
b1 = bar(ax1, mat_mean, 'grouped');
for ci = 1:nC2
    b1(ci).FaceColor = palette(ci,:);
    b1(ci).EdgeColor = 'none';
    b1(ci).FaceAlpha = 0.85;
end
set(ax1, 'XTick', 1:nS2, 'XTickLabel', scenarios, 'FontSize', 11, 'FontName', 'Arial');
ylabel(ax1, 'Mean Incidence Error [°]', 'FontSize', 11, 'FontName', 'Arial');
title(ax1, 'Tracking Accuracy — Mean Incidence Error', 'FontSize', 12, 'FontName', 'Arial', 'FontWeight', 'bold');
legend(ax1, ctrl_labels, 'Location', 'best', 'FontSize', 10);
grid(ax1, 'on'); ax1.YGrid = 'on'; ax1.XGrid = 'off';
addValueLabels(ax1, b1, '%.3f°');
subtitle(ax1, 'Lower is better — measure of average misalignment from sun', 'FontSize', 10);

% ── Subplot 2: Total motor energy ────────────────────────────────────────────
ax2 = subplot(3,1,2);
b2 = bar(ax2, mat_energy, 'grouped');
for ci = 1:nC2
    b2(ci).FaceColor = palette(ci,:);
    b2(ci).EdgeColor = 'none';
    b2(ci).FaceAlpha = 0.85;
end
set(ax2, 'XTick', 1:nS2, 'XTickLabel', scenarios, 'FontSize', 11, 'FontName', 'Arial');
ylabel(ax2, 'Motor Energy [Wh]', 'FontSize', 11, 'FontName', 'Arial');
title(ax2, 'Energy Consumption — Total Motor Energy Used', 'FontSize', 12, 'FontName', 'Arial', 'FontWeight', 'bold');
legend(ax2, ctrl_labels, 'Location', 'best', 'FontSize', 10);
grid(ax2, 'on'); ax2.YGrid = 'on'; ax2.XGrid = 'off';
addValueLabels(ax2, b2, '%.4f');
subtitle(ax2, 'Lower is better — energy cost of tracking actuation', 'FontSize', 10);

% ── Subplot 3: Net tracker yield ─────────────────────────────────────────────
ax3 = subplot(3,1,3);
b3 = bar(ax3, mat_yield, 'grouped');
for ci = 1:nC2
    b3(ci).FaceColor = palette(ci,:);
    b3(ci).EdgeColor = 'none';
    b3(ci).FaceAlpha = 0.85;
end
set(ax3, 'XTick', 1:nS2, 'XTickLabel', scenarios, 'FontSize', 11, 'FontName', 'Arial');
ylabel(ax3, 'Net Tracker Yield [Wh]', 'FontSize', 11, 'FontName', 'Arial');
xlabel(ax3, 'Scenario', 'FontSize', 11, 'FontName', 'Arial');
title(ax3, 'Energy Harvest — Net Tracker Yield (Gross − Motor Cost)', 'FontSize', 12, 'FontName', 'Arial', 'FontWeight', 'bold');
legend(ax3, ctrl_labels, 'Location', 'best', 'FontSize', 10);
grid(ax3, 'on'); ax3.YGrid = 'on'; ax3.XGrid = 'off';
addValueLabels(ax3, b3, '%.4f');
subtitle(ax3, 'Higher is better — useful energy delivered after subtracting motor overhead', 'FontSize', 10);

sgtitle('Solar Tracker Controller Comparison', 'FontSize', 14, 'FontName', 'Arial', 'FontWeight', 'bold');

try
    exportgraphics(fig, fullfile(output_dir, 'controller_comparison.png'), 'Resolution', 200);
    fprintf('  ✓ Chart saved: %s\n', fullfile(output_dir, 'controller_comparison.png'));
catch
    saveas(fig, fullfile(output_dir, 'controller_comparison.png'));
    fprintf('  ✓ Chart saved (fallback): %s\n', fullfile(output_dir, 'controller_comparison.png'));
end
close(fig);

%% ── FIGURE: EXTENDED 6-PANEL COMPARISON ────────────────────────────────────
fig2 = figure('Visible','off','Name','Extended Comparison','NumberTitle','off');
set(fig2, 'Position', [100 100 1400 1100]);

metrics_data  = {mat_mean, mat_energy, mat_yield, mat_lock, mat_gain};
metrics_labels = {'Mean Incidence Error [°]', 'Motor Energy [Wh]', ...
                  'Net Tracker Yield [Wh]', 'Lock Time [%]', 'Gain vs Fixed [%]'};
metrics_titles = {'Tracking Accuracy', 'Motor Energy Consumption', ...
                  'Net Tracker Yield', 'Alignment Lock Percentage', 'Gain over Fixed Panel'};
metrics_fmts   = {'%.3f°','%.4f','%.4f','%.1f%%','%+.1f%%'};
metrics_better = {'lower','lower','higher','higher','higher'};

for m = 1:5
    ax = subplot(3,2,m);
    bh = bar(ax, metrics_data{m}, 'grouped');
    for ci = 1:nC2
        bh(ci).FaceColor = palette(ci,:);
        bh(ci).EdgeColor = 'none';
        bh(ci).FaceAlpha = 0.85;
    end
    set(ax, 'XTick', 1:nS2, 'XTickLabel', scenarios, 'FontSize', 10, 'FontName', 'Arial');
    ylabel(ax, metrics_labels{m}, 'FontSize', 10, 'FontName', 'Arial');
    title(ax, metrics_titles{m}, 'FontSize', 11, 'FontName', 'Arial', 'FontWeight', 'bold');
    legend(ax, ctrl_labels, 'Location', 'best', 'FontSize', 9);
    grid(ax, 'on'); ax.YGrid = 'on'; ax.XGrid = 'off';
    addValueLabels(ax, bh, metrics_fmts{m});
    subtitle(ax, sprintf('%s is better', metrics_better{m}), 'FontSize', 9);
end

% Subplot 6: text summary table
ax6 = subplot(3,2,6);
axis(ax6, 'off');
summary_lines = {'BENCHMARK SUMMARY', ' '};
for s = 1:nS2
    for c = 1:nC2
        r_match = [];
        for rs = 1:nS
            for rc = 1:nC
                if strcmp(results(rs,rc).scenario, scenarios{s}) && ...
                   strcmp(results(rs,rc).controller, controllers{c})
                    r_match = results(rs,rc); break;
                end
            end
            if ~isempty(r_match), break; end
        end
        if ~isempty(r_match) && r_match.success
            M = r_match.Metrics;
            summary_lines{end+1} = sprintf('%s | %s:', upper(scenarios{s}), upper(controllers{c})); %#ok
            summary_lines{end+1} = sprintf('  Err=%.3f°  Lock=%.1f%%  Net=%.4fWh', ...
                safeGet(M,'mean_incidence',NaN), safeGet(M,'lock_percentage',NaN), ...
                safeGet(M,'net_tracker_yield_Wh',NaN)); %#ok
        end
    end
end
text(ax6, 0.05, 0.95, summary_lines, 'Units','normalized', ...
    'FontSize', 9, 'FontName', 'Courier', 'VerticalAlignment','top', ...
    'BackgroundColor', [0.95 0.95 0.95]);

sgtitle('Extended Controller Comparison Dashboard', 'FontSize', 13, 'FontName', 'Arial', 'FontWeight', 'bold');

try
    exportgraphics(fig2, fullfile(output_dir, 'extended_comparison.png'), 'Resolution', 200);
    fprintf('  ✓ Extended chart saved: %s\n', fullfile(output_dir, 'extended_comparison.png'));
catch
    saveas(fig2, fullfile(output_dir, 'extended_comparison.png'));
end
close(fig2);

fprintf('  ✓ Report generation complete.\n');

end

%% ── LOCAL HELPERS ────────────────────────────────────────────────────────────
function v = safeGet(s, field, default)
    if isfield(s, field) && ~isempty(s.(field)) && ~isnan(s.(field))
        v = s.(field);
    else
        v = default;
    end
end

function addValueLabels(ax, bar_handles, fmt)
% Add numeric labels on top of each bar
    hold(ax, 'on');
    for bi = 1:length(bar_handles)
        xdata = bar_handles(bi).XEndPoints;
        ydata = bar_handles(bi).YEndPoints;
        for k = 1:length(xdata)
            if ~isnan(ydata(k))
                yoffset = max(abs(ydata(k))*0.02, diff(ylim(ax))*0.01);
                text(ax, xdata(k), ydata(k) + yoffset, ...
                    sprintf(fmt, ydata(k)), ...
                    'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom', ...
                    'FontSize', 8, 'FontName', 'Arial');
            end
        end
    end
end
