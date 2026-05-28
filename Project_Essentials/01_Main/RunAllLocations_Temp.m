%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  RunAllLocations_Temp.m                                               ║
%% ║  Batch runner — all cities, WITH Faiman cell-temperature model        ║
%% ║                                                                       ║
%% ║  Processes ANTALYA, ISTANBUL, ANKARA sequentially using               ║
%% ║  CompareYield_TMY_Temp.m.  Per-city figures and .mat are saved        ║
%% ║  under Results/<CITY>/. A cross-city temperature comparison figure    ║
%% ║  is written to Results/Fig_CityComparison_Temp.png.                   ║
%% ║                                                                       ║
%% ║  Usage:                                                               ║
%% ║    matlab -batch "run('RunAllLocations_Temp.m')"                      ║
%% ║  or from Command Window:  run('RunAllLocations_Temp.m')               ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

%% ── Cities to process ────────────────────────────────────────────────────
locations = {'ANTALYA', 'ISTANBUL', 'ANKARA'};

%% ── Cross-city storage ───────────────────────────────────────────────────
Summary = struct();

for loc_idx = 1:numel(locations)

    loc_name = locations{loc_idx};
    fprintf('\n');
    fprintf('╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║  RUNNING LOCATION %d/%d : %-36s║\n', loc_idx, numel(locations), loc_name);
    fprintf('╚══════════════════════════════════════════════════════════════╝\n');

    % Verify irradiance CSV exists
    csv_path = fullfile(pwd, sprintf('%s_Data.csv', upper(loc_name)));
    if ~isfile(csv_path)
        warning('%s_Data.csv not found — skipping.', upper(loc_name));
        continue;
    end

    % BATCH_MODE prevents CompareYield_TMY_Temp from clearing the workspace
    BATCH_MODE = true;  %#ok<NASGU>

    % Run temperature-aware simulation
    CompareYield_TMY_Temp;

    % ── .mat already saved inside CompareYield_TMY_Temp to Results/<CITY>/ ─
    % ── Figures already saved to res_dir = Results/<CITY>/ ─────────────────
    % (no file-moving needed — temp script uses res_dir = Results/<CITY>)

    % ── Store summary for cross-city report ───────────────────────────────
    Summary(loc_idx).name          = upper(loc_name);
    Summary(loc_idx).E_fixed_yr    = E_fixed_yr;
    Summary(loc_idx).E_gross_yr    = E_gross_yr;
    Summary(loc_idx).E_para_yr     = E_para_yr;
    Summary(loc_idx).E_net_yr      = E_net_yr;
    Summary(loc_idx).Para_yr       = Para_yr;
    Summary(loc_idx).Gain_yr       = Gain_yr;
    Summary(loc_idx).T_amb_yr      = T_amb_yr;
    Summary(loc_idx).T_cell_fix_yr = T_fix_yr;
    Summary(loc_idx).T_cell_trk_yr = T_trk_yr;
    % Per-month gain for the heatmap
    Summary(loc_idx).monthly_gains  = [Results.Net_gain];
    Summary(loc_idx).monthly_T_fix  = [Results.T_cell_fix_mean];
    Summary(loc_idx).monthly_T_trk  = [Results.T_cell_trk_mean];
    Summary(loc_idx).monthly_T_amb  = [Results.T_amb_mean];

    fprintf('\n  ✓ %s complete.\n', upper(loc_name));
    clear BATCH_MODE;
end

%% ════════════════════════════════════════════════════════════════════════
%%   CROSS-CITY ANNUAL SUMMARY TABLE (with temperature)
%% ════════════════════════════════════════════════════════════════════════
if ~isfield(Summary, 'name')
    fprintf('No locations were successfully processed. Exiting.\n');
    return;
end
valid = arrayfun(@(s) ~isempty(s.name), Summary);
S     = Summary(valid);
nLoc  = numel(S);

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════════════╗\n');
fprintf('║         MULTI-CITY ANNUAL YIELD (WITH CELL TEMPERATURE MODEL)       ║\n');
fprintf('╚══════════════════════════════════════════════════════════════════════╝\n');
fprintf('  %-10s | %9s | %9s | %8s | %9s | %7s | %7s | %7s | %7s | %7s\n', ...
    'Location','Fix(kWh)','Net(kWh)','Para(kWh)','Para(%)', ...
    'Gain(%)','T_amb','T_fix','T_trk','ΔT_trk');
fprintf('  %s\n', repmat('-',1,105));
for k = 1:nLoc
    dT = S(k).T_cell_trk_yr - S(k).T_amb_yr;
    fprintf('  %-10s | %9.2f | %9.2f | %8.3f | %9.2f | %+7.2f | %7.1f | %7.1f | %7.1f | %+7.1f\n', ...
        S(k).name, ...
        S(k).E_fixed_yr / 1000, ...
        S(k).E_net_yr   / 1000, ...
        S(k).E_para_yr  / 1000, ...
        S(k).Para_yr, ...
        S(k).Gain_yr, ...
        S(k).T_amb_yr, ...
        S(k).T_cell_fix_yr, ...
        S(k).T_cell_trk_yr, ...
        dT);
end
fprintf('  %s\n\n', repmat('-',1,105));

%% ════════════════════════════════════════════════════════════════════════
%%   CROSS-CITY COMPARISON FIGURES
%% ════════════════════════════════════════════════════════════════════════
if nLoc < 1
    fprintf('No valid locations to plot.\n');
    return;
end

FN  = 'Times New Roman';
FSr = 11; FSl = 12; FSt = 13;
mon_labels = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};

loc_colors = {[0.13 0.29 0.53],  [0.93 0.38 0.10],  [0.22 0.56 0.24]};
if nLoc > numel(loc_colors)
    loc_colors = num2cell(lines(nLoc),2);
end

%% FIG_CMP_1 — Grouped bar: Fixed / Gross / Net (kWh/yr) ─────────────────
fig1 = figure('Color','w','NumberTitle','off','Visible','off');
fig1.Position = [50 50 1100 600];
ax1 = axes(fig1,'Color','w'); hold(ax1,'on');
set(ax1,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',1:nLoc,'XTickLabel',{S.name}, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');

cmp_mat = [[S.E_fixed_yr]; [S.E_gross_yr]; [S.E_net_yr]]' / 1000;
bh = bar(ax1, 1:nLoc, cmp_mat, 'grouped', 'FaceAlpha',1.0);
bh(1).FaceColor = [0.13 0.29 0.53]; bh(1).EdgeColor = 'none';
bh(2).FaceColor = [0.56 0.76 0.49]; bh(2).EdgeColor = 'none';
bh(3).FaceColor = [0.93 0.69 0.13]; bh(3).EdgeColor = 'none';

for k = 1:nLoc
    x_pos = k + bh(3).XOffset;
    y_pos = cmp_mat(k,3) + 0.025 * max(cmp_mat(:));
    text(ax1, x_pos, y_pos, sprintf('%+.1f%%', S(k).Gain_yr), ...
        'HorizontalAlignment','center','FontSize',FSr,'FontName',FN, ...
        'FontWeight','bold','Color',[0.45 0.25 0.00]);
end

ylabel(ax1,'Annual Energy (kWh/yr)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax1,'Location',              'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax1,'Annual Yield Comparison: Fixed vs. Dual-Axis Tracker (with Temperature Model)', ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax1, bh, {'Fixed (horizontal)','Tracker gross','Tracker net (delivered)'}, ...
    'Location','northwest','FontSize',FSr,'FontName',FN,'Box','on');
if ~isfolder('Results'), mkdir('Results'); end
exportgraphics(fig1, fullfile('Results','Fig_CityComparison_Temp.png'), 'Resolution',300);
close(fig1);
fprintf('  ✓ Fig_CityComparison_Temp.png\n');

%% FIG_CMP_2 — Cell temperature comparison (all cities, all months) ───────
fig2 = figure('Color','w','NumberTitle','off','Visible','off');
fig2.Position = [50 50 1300 560];
ax2 = axes(fig2,'Color','w'); hold(ax2,'on');
set(ax2,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',1:12,'XTickLabel',mon_labels, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');

leg_handles = gobjects(nLoc,1);
for k = 1:nLoc
    clr = loc_colors{k};
    plot(ax2, 1:12, S(k).monthly_T_trk, '-^','Color',clr,'LineWidth',2.2, ...
        'MarkerSize',7,'MarkerFaceColor',clr,'HandleVisibility','on', ...
        'DisplayName',sprintf('%s T_{cell}(trk)', S(k).name));
    plot(ax2, 1:12, S(k).monthly_T_fix, '--o','Color',clr,'LineWidth',1.2, ...
        'MarkerSize',5,'MarkerFaceColor','w','HandleVisibility','on', ...
        'DisplayName',sprintf('%s T_{cell}(fix)', S(k).name));
    plot(ax2, 1:12, S(k).monthly_T_amb, ':','Color',clr*0.7,'LineWidth',1.0, ...
        'MarkerSize',4,'HandleVisibility','on', ...
        'DisplayName',sprintf('%s T_{amb}', S(k).name));
end
yline(ax2, 25,'--k','LineWidth',1.2,'Label','STC 25°C','FontSize',9,'FontName',FN);

ylabel(ax2,'Temperature (°C)',   'FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax2,'Month',              'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax2, 'Monthly Cell Temperature: Ambient / Fixed / Tracker — All Cities (Faiman model)', ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax2,'Location','northwest','FontName',FN,'FontSize',8,'Box','on','NumColumns',3);
exportgraphics(fig2, fullfile('Results','Fig_CellTemp_AllCities.png'), 'Resolution',300);
close(fig2);
fprintf('  ✓ Fig_CellTemp_AllCities.png\n');

%% FIG_CMP_3 — Net gain bars per city overlaid by month ───────────────────
fig3 = figure('Color','w','NumberTitle','off','Visible','off');
fig3.Position = [50 50 1300 560];
ax3 = axes(fig3,'Color','w'); hold(ax3,'on');
set(ax3,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',1:12,'XTickLabel',mon_labels, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');

for k = 1:nLoc
    clr = loc_colors{k};
    plot(ax3, 1:12, S(k).monthly_gains, '-o','Color',clr,'LineWidth',2.2, ...
        'MarkerSize',7,'MarkerFaceColor',clr, ...
        'DisplayName', sprintf('%s (annual=%+.1f%%)', S(k).name, S(k).Gain_yr));
end
yline(ax3, 0,'-k','LineWidth',0.8,'HandleVisibility','off');

ylabel(ax3,'Net Efficiency Gain (%)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax3,'Month',                  'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax3, 'Monthly Net Gain — Tracker vs Fixed (Temperature-Corrected) — All Cities', ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax3,'Location','best','FontName',FN,'FontSize',FSr,'Box','on');
exportgraphics(fig3, fullfile('Results','Fig_NetGain_AllCities_Temp.png'), 'Resolution',300);
close(fig3);
fprintf('  ✓ Fig_NetGain_AllCities_Temp.png\n');

%% FIG_CMP_4 — ΔT_cell (tracker − ambient) per city, all months ──────────
fig4 = figure('Color','w','NumberTitle','off','Visible','off');
fig4.Position = [50 50 1300 560];
ax4 = axes(fig4,'Color','w'); hold(ax4,'on');
set(ax4,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',1:12,'XTickLabel',mon_labels, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');

for k = 1:nLoc
    clr  = loc_colors{k};
    dT_v = S(k).monthly_T_trk - S(k).monthly_T_amb;
    plot(ax4, 1:12, dT_v, '-s','Color',clr,'LineWidth',2.2, ...
        'MarkerSize',7,'MarkerFaceColor',clr, ...
        'DisplayName', sprintf('%s  ΔT_{trk}', S(k).name));
    dT_fix = S(k).monthly_T_fix - S(k).monthly_T_amb;
    plot(ax4, 1:12, dT_fix, '--','Color',clr,'LineWidth',1.0, ...
        'DisplayName', sprintf('%s  ΔT_{fix}', S(k).name));
end

ylabel(ax4,'ΔT_{cell} = T_{cell} − T_{amb}  (°C)', ...
    'FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax4,'Month','FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax4, 'Cell Heating Above Ambient (Faiman model) — All Cities', ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax4,'Location','best','FontName',FN,'FontSize',8,'Box','on','NumColumns',2);
exportgraphics(fig4, fullfile('Results','Fig_DeltaTemp_AllCities.png'), 'Resolution',300);
close(fig4);
fprintf('  ✓ Fig_DeltaTemp_AllCities.png\n');

%% ── Save cross-city summary struct ──────────────────────────────────────
save(fullfile('Results','AllCities_Summary_Temp.mat'), 'S');
fprintf('  ✓ AllCities_Summary_Temp.mat\n');

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  RunAllLocations_Temp COMPLETE                                ║\n');
fprintf('║  Per-city data : Results/<CITY>/                             ║\n');
fprintf('║  Cross-city    : Results/Fig_City*.png                       ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');
