%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║   RunAllLocations.m — Batch Runner for Multi-City Yield Comparison   ║
%% ║   Loops over all configured locations and saves results per city     ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

%% ── Add your cities here — name must match <NAME>_Data.csv exactly ──────
locations = {'ANTALYA','ISTANBUL', 'ANKARA'};

%% ── Storage for cross-location comparison ────────────────────────────────
Summary = struct();

for loc_idx = 1:numel(locations)

    loc_name = locations{loc_idx};
    fprintf('\n');
    fprintf('╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║  RUNNING LOCATION %d/%d : %-36s║\n', loc_idx, numel(locations), loc_name);
    fprintf('╚══════════════════════════════════════════════════════════════╝\n');

    % Check CSV exists before attempting
    csv_path = fullfile(pwd, sprintf('%s_Data.csv', upper(loc_name)));
    if ~isfile(csv_path)
        warning('CSV not found for %s: %s — skipping.', loc_name, csv_path);
        continue;
    end

    % Set BATCH_MODE so CompareYield does not clear workspace
    BATCH_MODE = true;  %#ok

    % Run the main simulation — results land in workspace
    CompareYield_TMY;

    % ── Save per-location figures and MAT file ────────────────────────────
    loc_res_dir = fullfile('Results', upper(loc_name));
    if ~isfolder(loc_res_dir), mkdir(loc_res_dir); end

    % Move generated figures into city subfolder
    fig_files = dir(fullfile('Results', 'Fig*.png'));
    for f = 1:numel(fig_files)
        src = fullfile('Results', fig_files(f).name);
        dst = fullfile(loc_res_dir, fig_files(f).name);
        movefile(src, dst, 'f');
    end

    % Save workspace results for this location
    mat_path = fullfile(loc_res_dir, sprintf('%s_Results.mat', upper(loc_name)));
    save(mat_path, 'Results', 'AllData', 'Geo', ...
         'E_fixed_yr', 'E_gross_yr', 'E_para_yr', 'E_net_yr', ...
         'Para_yr', 'Gain_yr', 'n_track_yr', 'n_hold_yr', 'n_idle_yr');
    fprintf('\n  ✓ Results saved → %s\n', mat_path);

    % ── Store summary for cross-location comparison ───────────────────────
    Summary(loc_idx).name       = upper(loc_name);
    Summary(loc_idx).E_fixed_yr = E_fixed_yr;
    Summary(loc_idx).E_gross_yr = E_gross_yr;
    Summary(loc_idx).E_para_yr  = E_para_yr;
    Summary(loc_idx).E_net_yr   = E_net_yr;
    Summary(loc_idx).Para_yr    = Para_yr;
    Summary(loc_idx).Gain_yr    = Gain_yr;

    clear BATCH_MODE;
end

%% ── Cross-location summary table ─────────────────────────────────────────
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════════════╗\n');
fprintf('║              MULTI-CITY ANNUAL YIELD COMPARISON                     ║\n');
fprintf('╚══════════════════════════════════════════════════════════════════════╝\n');
fprintf('  %-10s | %10s | %10s | %10s | %10s | %8s | %8s\n', ...
    'Location','Fix(kWh)','Gross(kWh)','Para(kWh)','Net(kWh)','Para(%)','Gain(%)');
fprintf('  %s\n', repmat('-',1,80));
if ~isfield(Summary, 'name')
    fprintf('  (no results)\n');
else
for k = 1:numel(Summary)
    if isempty(Summary(k).name), continue; end
    fprintf('  %-10s | %10.2f | %10.2f | %10.3f | %10.2f | %8.2f | %+8.2f\n', ...
        Summary(k).name, ...
        Summary(k).E_fixed_yr/1000, ...
        Summary(k).E_gross_yr/1000, ...
        Summary(k).E_para_yr/1000, ...
        Summary(k).E_net_yr/1000, ...
        Summary(k).Para_yr, ...
        Summary(k).Gain_yr);
end
fprintf('  %s\n\n', repmat('-',1,80));
end  % isfield guard

%% ── Cross-location comparison figure ─────────────────────────────────────
if isfield(Summary,'name') && numel(Summary) > 1
    valid = ~cellfun(@isempty, {Summary.name});
    S     = Summary(valid);
    nLoc  = numel(S);

    FNc = 'Times New Roman';

    fig_cmp = figure('Name','City Comparison','Color','w', ...
                     'NumberTitle','off','Visible','off');
    fig_cmp.Position = [50 50 1100 600];
    ax_cmp = axes(fig_cmp,'Color','w'); hold(ax_cmp,'on');

    cmp_mat = [[S.E_fixed_yr]; [S.E_gross_yr]; [S.E_net_yr]]' / 1000;
    bh = bar(ax_cmp, 1:nLoc, cmp_mat, 'grouped', 'FaceAlpha',1.0);
    bh(1).FaceColor = [0.13,0.29,0.53]; bh(1).EdgeColor = 'none';
    bh(2).FaceColor = [0.56,0.76,0.49]; bh(2).EdgeColor = 'none';
    bh(3).FaceColor = [0.93,0.69,0.13]; bh(3).EdgeColor = 'none';

    set(ax_cmp,'FontName',FNc,'FontSize',12,'XTick',1:nLoc,'XTickLabel',{S.name}, ...
        'Box','on','LineWidth',1.2,'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');
    ylabel(ax_cmp,'Annual Energy (kWh/yr)','FontName',FNc,'FontSize',13,'FontWeight','bold');
    xlabel(ax_cmp,'Location','FontName',FNc,'FontSize',13,'FontWeight','bold');
    title(ax_cmp,'Annual Yield Comparison: Fixed Panel vs. Dual-Axis Tracker', ...
        'FontName',FNc,'FontSize',14,'FontWeight','bold');
    legend(ax_cmp, bh, {'Fixed (horizontal)','Tracker gross','Tracker net (delivered)'}, ...
        'Location','northwest','FontSize',12,'FontName',FNc,'Box','on');

    % Annotate net gain % above net bars
    for k = 1:nLoc
        x_pos = k + bh(3).XOffset;
        y_pos = cmp_mat(k,3) + 0.012 * max(cmp_mat(:));
        text(ax_cmp, x_pos, y_pos, sprintf('%+.1f%%', S(k).Gain_yr), ...
            'HorizontalAlignment','center','FontSize',11,'FontName',FNc, ...
            'FontWeight','bold','Color',[0.45 0.25 0.00]);
    end

    cmp_fig_path = fullfile('Results','Fig_CityComparison.png');
    exportgraphics(fig_cmp, cmp_fig_path, 'Resolution',300);
    close(fig_cmp);
    fprintf('  ✓ Comparison figure → %s\n\n', cmp_fig_path);
end

fprintf('All locations complete.\n');