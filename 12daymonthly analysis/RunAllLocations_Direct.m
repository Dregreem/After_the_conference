%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  RunAllLocations_Direct.m                                             ║
%% ║  Batch runner — ANTALYA / ISTANBUL / ANKARA                          ║
%% ║  Uses CompareYield_Direct (direct PVGIS TMY, no pre-baked CSV)        ║
%% ║                                                                      ║
%% ║  Expects per-city file:  <CITY>_TMY.csv   (PVGIS 5.3 / SARAH3)      ║
%% ║  as returned by getGeoConfig(loc).PVGIS_File                         ║
%% ║                                                                      ║
%% ║  Outputs per city  → Results/<CITY>/                                 ║
%% ║  Cross-city figs   → Results/                                        ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

locations = {'ISTANBUL','ANTALYA',  'ANKARA'};
Summary   = struct();

for loc_idx = 1:numel(locations)

    loc_name = locations{loc_idx};
    fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║  LOCATION %d/%d : %-45s║\n', loc_idx, numel(locations), loc_name);
    fprintf('╚══════════════════════════════════════════════════════════════╝\n');

    % Resolve expected TMY filename from getGeoConfig
    try
        Geo_check = getGeoConfig(loc_name);
        pvgis_path = Geo_check.PVGIS_File;
    catch
        pvgis_path = sprintf('%s_TMY.csv', upper(loc_name));
    end

    if ~isfile(pvgis_path)
        warning('TMY file not found: %s — skipping.', pvgis_path);
        continue;
    end

    % BATCH_MODE=true prevents CompareYield_Direct from calling clear/clc
    BATCH_MODE = true;  %#ok<NASGU>
    CompareYield_Direct;

    % Harvest annual summary variables left in workspace by CompareYield_Direct
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
    Summary(loc_idx).monthly_gains = [Results.Net_gain];
    Summary(loc_idx).monthly_T_fix = [Results.T_cell_fix_mean];
    Summary(loc_idx).monthly_T_trk = [Results.T_cell_trk_mean];
    Summary(loc_idx).monthly_T_amb = [Results.T_amb_mean];
    Summary(loc_idx).monthly_E_net = [Results.E_net];
    Summary(loc_idx).monthly_E_fix = [Results.E_fixed];

    fprintf('\n  ✓ %s complete. Gain = %+.2f %%\n', upper(loc_name), Gain_yr);
    clear BATCH_MODE;
end

%% Validate
valid = arrayfun(@(s) ~isempty(s.name), Summary);
S     = Summary(valid);
nLoc  = numel(S);
if nLoc == 0
    fprintf('No locations processed.\n');
    return;
end

%% ══════════════════════════════════════════════════════════════════════════
%%  CROSS-CITY ANNUAL SUMMARY TABLE
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n╔══════════════════════════════════════════════════════════════════════╗\n');
fprintf('║         MULTI-CITY ANNUAL YIELD — DIRECT PVGIS | OPTION-A SUN      ║\n');
fprintf('╚══════════════════════════════════════════════════════════════════════╝\n');
fprintf('  %-10s | %9s | %9s | %8s | %9s | %7s | %7s | %7s | %7s\n', ...
    'Location','Fix(kWh)','Net(kWh)','Para(kWh)','Para(%)','Gain(%)','T_amb','T_fix','T_trk');
fprintf('  %s\n', repmat('-',1,95));
for k = 1:nLoc
    fprintf('  %-10s | %9.3f | %9.3f | %8.4f | %9.2f | %+7.2f | %7.1f | %7.1f | %7.1f\n', ...
        S(k).name, ...
        S(k).E_fixed_yr/1000, S(k).E_net_yr/1000, S(k).E_para_yr/1000, ...
        S(k).Para_yr, S(k).Gain_yr, ...
        S(k).T_amb_yr, S(k).T_cell_fix_yr, S(k).T_cell_trk_yr);
end
fprintf('  %s\n\n', repmat('-',1,95));

%% ══════════════════════════════════════════════════════════════════════════
%%  CROSS-CITY COMPARISON FIGURES
%% ══════════════════════════════════════════════════════════════════════════
if ~isfolder('Results'), mkdir('Results'); end

FN  = 'Times New Roman';
FSr = 11; FSl = 12; FSt = 13; FSs = 9;
mon_labels = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};

loc_colors = {[0.13 0.29 0.53], [0.93 0.38 0.10], [0.22 0.56 0.24]};
if nLoc > numel(loc_colors)
    loc_colors = num2cell(lines(nLoc), 2);
end

%% FIG_CMP_1 — Annual grouped bar: Fixed / Net (kWh/yr) ───────────────────
fig1 = figure('Color','w','NumberTitle','off','Visible','off');
fig1.Position = [50 50 1000 560];
ax1 = axes(fig1); hold(ax1,'on');
set(ax1,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',1:nLoc,'XTickLabel',{S.name}, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');

mat = [[S.E_fixed_yr]; [S.E_net_yr]]' / 1000;
bh  = bar(ax1, 1:nLoc, mat, 'grouped', 'FaceAlpha',1.0);
bh(1).FaceColor = [0.13 0.29 0.53]; bh(1).EdgeColor = 'none';
bh(2).FaceColor = [0.93 0.69 0.13]; bh(2).EdgeColor = 'none';

for k = 1:nLoc
    x_pos = k + bh(2).XOffset;
    y_pos = mat(k,2) + 0.02*max(mat(:));
    text(ax1, x_pos, y_pos, sprintf('%+.1f%%', S(k).Gain_yr), ...
        'HorizontalAlignment','center','FontSize',FSr,'FontName',FN, ...
        'FontWeight','bold','Color',[0.45 0.25 0.00]);
end

ylabel(ax1,'Annual Energy (kWh/yr)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax1,'Location',              'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax1,'Annual Yield: Fixed vs Tracker Net — All Cities (Direct PVGIS | Faiman)', ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax1, bh, {'Fixed (horizontal)','Tracker net'}, ...
    'Location','northwest','FontSize',FSr,'FontName',FN,'Box','on');
exportgraphics(fig1, fullfile('Results','Fig_Annual_Direct.png'), 'Resolution',300);
close(fig1);
fprintf('  ✓ Fig_Annual_Direct.png\n');

%% FIG_CMP_2 — Monthly net gain lines ─────────────────────────────────────
fig2 = figure('Color','w','NumberTitle','off','Visible','off');
fig2.Position = [50 50 1300 520];
ax2 = axes(fig2); hold(ax2,'on');
set(ax2,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',1:12,'XTickLabel',mon_labels, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');

for k = 1:nLoc
    clr = loc_colors{k};
    plot(ax2, 1:12, S(k).monthly_gains, '-o','Color',clr,'LineWidth',2.2, ...
        'MarkerSize',7,'MarkerFaceColor',clr, ...
        'DisplayName', sprintf('%s  (annual %+.1f%%)', S(k).name, S(k).Gain_yr));
end
yline(ax2, 0, '-k','LineWidth',0.8,'HandleVisibility','off');

ylabel(ax2,'Net Gain (%)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax2,'Month',       'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax2,'Monthly Net Gain — Tracker vs Fixed — All Cities (Direct PVGIS)', ...
    'FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax2,'Location','best','FontName',FN,'FontSize',FSr,'Box','on');
exportgraphics(fig2, fullfile('Results','Fig_MonthlyGain_Direct.png'), 'Resolution',300);
close(fig2);
fprintf('  ✓ Fig_MonthlyGain_Direct.png\n');

%% FIG_CMP_3 — Monthly cell temperature all cities ─────────────────────────
fig3 = figure('Color','w','NumberTitle','off','Visible','off');
fig3.Position = [50 50 1300 520];
ax3 = axes(fig3); hold(ax3,'on');
set(ax3,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'XTick',1:12,'XTickLabel',mon_labels, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.45,'TickDir','out');

for k = 1:nLoc
    clr = loc_colors{k};
    plot(ax3, 1:12, S(k).monthly_T_trk, '-^','Color',clr,'LineWidth',2.2, ...
        'MarkerSize',7,'MarkerFaceColor',clr, ...
        'DisplayName',sprintf('%s T_{trk}',S(k).name));
    plot(ax3, 1:12, S(k).monthly_T_fix, '--o','Color',clr,'LineWidth',1.2, ...
        'MarkerSize',5,'MarkerFaceColor','w', ...
        'DisplayName',sprintf('%s T_{fix}',S(k).name));
end
yline(ax3, 25,'--k','LineWidth',1.2,'Label','STC 25°C');

ylabel(ax3,'Cell Temperature (°C)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
xlabel(ax3,'Month',                'FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax3,'Monthly Cell Temperature — All Cities (Faiman model)','FontName',FN,'FontSize',FSt,'FontWeight','bold');
legend(ax3,'Location','northwest','FontName',FN,'FontSize',8,'Box','on','NumColumns',3);
exportgraphics(fig3, fullfile('Results','Fig_CellTemp_Direct.png'), 'Resolution',300);
close(fig3);
fprintf('  ✓ Fig_CellTemp_Direct.png\n');

%% Save summary
save(fullfile('Results','AllCities_Summary_Direct.mat'), 'S');
fprintf('  ✓ AllCities_Summary_Direct.mat\n');

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  RunAllLocations_Direct COMPLETE                              ║\n');
fprintf('║  Per-city : Results/<CITY>/                                  ║\n');
fprintf('║  Summary  : Results/AllCities_Summary_Direct.mat             ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');
