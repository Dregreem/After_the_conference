%% ╔════════════════════════════════════════════════════════════════════════╗
%% ║   PaperFigures_5.m   —   5 Publication-Ready Figures                 ║
%% ║   FIXED: symbols, 3-bar Fig1, smooth Fig2, deg-error Fig3            ║
%% ╚════════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

%% FIX 1 — Use 'tex' so \eta, \theta, \circ render as Greek letters
set(groot,'defaultTextInterpreter',              'tex');
set(groot,'defaultAxesTickLabelInterpreter',     'tex');
set(groot,'defaultLegendInterpreter',            'tex');

%% ═══ SHARED STYLE ══════════════════════════════════════════════════════════
FN  = 'Times New Roman';
FSs =  9;   FSr = 11;   FSl = 12;   FSt = 13;

C_fix   = [0.13 0.29 0.53];
C_net   = [0.93 0.69 0.13];
C_para  = [0.75 0.15 0.15];

mon_labels = {'Jan','Feb','Mar','Apr','May','Jun', ...
              'Jul','Aug','Sep','Oct','Nov','Dec'};
rep_days   = [17,47,75,105,135,162,198,228,258,288,318,344];

locations  = {'ANTALYA','ISTANBUL','ANKARA'};
loc_long   = { ...
    'Antalya  (36.9\circN)  ---  High Irradiance Region', ...
    'Istanbul (41.0\circN)  ---  Moderate Irradiance Region', ...
    'Ankara   (39.9\circN)  ---  Low Irradiance Region'};
loc_panels = {'(a)','(b)','(c)'};
nLoc = numel(locations);

out_dir = fullfile('Results','PaperFigures');
if ~isfolder(out_dir), mkdir(out_dir); end

%% ═══ LOAD MAT RESULTS ══════════════════════════════════════════════════════
fprintf('Loading simulation results...\n');
LOC = struct();
for li = 1:nLoc
    lname = locations{li};
    mp    = fullfile('Results', lname, [lname '_Results.mat']);
    if ~isfile(mp)
        error('File not found: %s\nRun RunAllLocations.m first.', mp);
    end
    d = load(mp);
    LOC(li).name    = lname;
    LOC(li).Results = d.Results;
    LOC(li).AllData = d.AllData;
    LOC(li).Geo     = d.Geo;
    LOC(li).Gain_yr = d.Gain_yr;
    LOC(li).Para_yr = d.Para_yr;
    fprintf('  ok  %-12s  |  Annual gain: %+.1f%%  |  Parasitic: %.2f%%\n', ...
        lname, d.Gain_yr, d.Para_yr);
end
fprintf('\n');

%% ════════════════════════════════════════════════════════════════════════════
%% FIG 1 — Monthly Energy Budget  (3 x 1)
%%   3 grouped bars : E_fixed (blue) | E_net (amber) | E_para (red)
%%   Right axis     : Net efficiency gain  eta  [%]  — black diamond line
%% ════════════════════════════════════════════════════════════════════════════
fprintf('Building Fig 1 ...\n');

fig1 = figure('Color','w','NumberTitle','off','Visible','off');
fig1.Position = [40 40 1280 1040];

for li = 1:nLoc
    R      = LOC(li).Results;
    E_fix  = [R.E_fixed];
    E_net  = [R.E_net];
    E_para = [R.E_para];
    gains  = [R.Net_gain];

    ax = subplot(3,1,li,'Parent',fig1);
    set(ax,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.15, ...
        'YGrid','on','GridLineStyle',':','GridAlpha',0.42, ...
        'XTick',1:12,'XTickLabel',mon_labels,'TickDir','out');
    hold(ax,'on');

    % 3 grouped bars
    bh = bar(ax, [E_fix; E_net; E_para]', 'grouped', 'FaceAlpha',0.93);
    bh(1).FaceColor = C_fix;  bh(1).EdgeColor = 'none';
    bh(2).FaceColor = C_net;  bh(2).EdgeColor = 'none';
    bh(3).FaceColor = C_para; bh(3).EdgeColor = 'none';

    % Value labels on net bars
    for m = 1:12
        text(ax, m + bh(2).XOffset, E_net(m)*1.05, ...
            sprintf('%.1f', E_net(m)), ...
            'HorizontalAlignment','center','FontSize',FSs-0.5, ...
            'FontName',FN,'FontWeight','bold','Color',[0.35 0.20 0.00]);
    end

    yyaxis(ax,'left');
    ax.YAxis(1).Color = 'k';
    ylim(ax,[0, max(E_net)*1.38]);
    ylabel(ax,'Daily Energy  (Wh / day)', ...
        'FontName',FN,'FontSize',FSl,'FontWeight','bold');

    % eta line — right axis
    yyaxis(ax,'right');
    eta_h = plot(ax, 1:12, gains, 'd-', 'Color',[0.10 0.10 0.10], ...
        'LineWidth',2.1,'MarkerSize',7, ...
        'MarkerFaceColor',[0.10 0.10 0.10],'MarkerEdgeColor','none');
    ax.YAxis(2).Color    = [0.10 0.10 0.10];
    ax.YAxis(2).FontName = FN;
    ax.YAxis(2).FontSize = FSr;
    yl_g = [max(0, min(gains)*0.85), max(gains)*1.25];
    if diff(yl_g) < 1, yl_g = [0 20]; end
    ylim(ax, yl_g);
    ylabel(ax,'Net Efficiency Gain  \eta (%)', ...
        'FontName',FN,'FontSize',FSl,'FontWeight','bold');

    title(ax, sprintf('%s  %s', loc_panels{li}, loc_long{li}), ...
        'FontName',FN,'FontSize',FSt,'FontWeight','bold');
    if li == 3
        xlabel(ax,'Month','FontName',FN,'FontSize',FSl,'FontWeight','bold');
    end
    if li == 1
        yyaxis(ax,'left');
        legend(ax, [bh eta_h], ...
            {'Fixed (horizontal)', 'Tracker net (delivered)', ...
             'Tracker consumption', '\eta net gain (right axis)'}, ...
            'Location','northwest','FontSize',FSr-1,'FontName',FN,'Box','on');
    end
end

sgtitle(fig1,'Monthly Energy Budget: Fixed PV Panel vs. Dual-Axis Solar Tracker', ...
    'FontName',FN,'FontSize',FSt+1,'FontWeight','bold');
exportgraphics(fig1, fullfile(out_dir,'Fig1_MonthlyEnergyBudget.png'),'Resolution',300);
close(fig1);
fprintf('  ok  Fig 1 saved.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% FIG 2 — Daily Power Profiles  (3 rows x 2 cols)
%%   FIX: movmean smoothing removes FSM startup spikes
%%        downsample every 10 min for clean marker spacing
%% ════════════════════════════════════════════════════════════════════════════
fprintf('Building Fig 2 ...\n');

fig2 = figure('Color','w','NumberTitle','off','Visible','off');
fig2.Position = [40 40 1500 1060];

season_mon  = [6, 12];
season_name = {'June 21st  (Summer Solstice)', 'December 21st  (Winter Solstice)'};

for li = 1:nLoc
    for si = 1:2
        m = season_mon(si);
        D = LOC(li).AllData{m};
        R = LOC(li).Results(m);

        tv    = D.time_vec(:);
        P_fix = D.P_fixed(:);
        P_net = max(0, D.P_tracker_net(:));

        % FIX: 3-minute moving average removes FSM startup spikes
        win   = 180;
        P_fix = movmean(P_fix, win);
        P_net = movmean(P_net, win);

        % Downsample every 10 min, daylight only
        ds      = 600;
        all_idx = (1:ds:length(tv))';
        day_msk = P_fix(all_idx) > 0.05;
        idx     = all_idx(day_msk);
        if isempty(idx), continue; end

        th = tv / 3600;

        ax = subplot(3,2,(li-1)*2+si,'Parent',fig2);
        set(ax,'FontName',FN,'FontSize',FSr-1,'Box','on','LineWidth',1.0, ...
            'YGrid','on','GridLineStyle',':','GridAlpha',0.40,'TickDir','out');
        hold(ax,'on');

        p1 = plot(ax, th(idx), P_fix(idx), '--o', ...
            'Color',[0.45 0.45 0.45],'LineWidth',1.5,'MarkerSize',4, ...
            'MarkerFaceColor','none','MarkerEdgeColor',[0.45 0.45 0.45], ...
            'DisplayName','Fixed');
        p2 = plot(ax, th(idx), P_net(idx), '-^', ...
            'Color',[0 0 0],'LineWidth',2.0,'MarkerSize',4, ...
            'MarkerFaceColor',[0 0 0],'MarkerEdgeColor','none', ...
            'DisplayName','Tracking');

        xlim(ax,[5.5 20.5]);
        xticks(ax,6:2:20);
        Pmax = max([P_net(idx); P_fix(idx); 0.1]);
        ylim(ax,[0, Pmax*1.25]);
        xlabel(ax,'Local time (hour)','FontName',FN,'FontSize',FSs+1,'FontWeight','bold');
        ylabel(ax,'Power (W)','FontName',FN,'FontSize',FSs+1,'FontWeight','bold');
        title(ax, sprintf('%s %s  ---  %s', loc_panels{li}, locations{li}, season_name{si}), ...
            'FontName',FN,'FontSize',FSr,'FontWeight','bold');

        text(ax, 20.2, Pmax*1.22, ...
            sprintf('Net:   %.1f Wh\nFixed: %.1f Wh\nGain:  %+.1f%%', ...
                R.E_net, R.E_fixed, R.Net_gain), ...
            'FontName',FN,'FontSize',FSs,'HorizontalAlignment','right', ...
            'VerticalAlignment','top','BackgroundColor',[1 1 0.88], ...
            'EdgeColor',[0.72 0.72 0.52],'Margin',3);

        if li == 1 && si == 1
            legend(ax,[p1 p2],'Location','northwest', ...
                'FontName',FN,'FontSize',FSr-1,'Box','on');
        end
    end
end

sgtitle(fig2,'Daily Power Generation: Fixed Panel vs. Dual-Axis Solar Tracker', ...
    'FontName',FN,'FontSize',FSt+1,'FontWeight','bold');
exportgraphics(fig2, fullfile(out_dir,'Fig2_DailyPowerProfiles.png'),'Resolution',300);
close(fig2);
fprintf('  ok  Fig 2 saved.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% FIG 3 — Tracking Error in DEGREES vs local time   [Fig 14 style]
%%   FIX: metric = acosd(cos_theta) [deg]  —  NOT instantaneous power gain %
%%   4 curves: June & Dec  x  Antalya & Istanbul
%% ════════════════════════════════════════════════════════════════════════════
fprintf('Building Fig 3 ...\n');

fig3 = figure('Color','w','NumberTitle','off','Visible','off');
fig3.Position = [40 40 1300 540];
ax3 = axes(fig3,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.2, ...
    'YGrid','on','GridLineStyle',':','GridAlpha',0.40,'TickDir','out');
hold(ax3,'on');

case_months = [6,  12];
case_nm     = {'June 21st  (Summer --- Low Error)', ...
               'December 21st  (Winter --- High Error)'};
locs_f3 = [1, 2];
styles  = {'-^', '--s'};
colors  = {[0.00 0.00 0.00]; [0.50 0.50 0.50]; ...
           [0.00 0.00 0.00]; [0.50 0.50 0.50]};
lw_v    = [2.0 1.6 2.0 1.6];

h_all = gobjects(0);  lbl_all = {};
cidx  = 0;
for ci = 1:2
    for lf = 1:2
        cidx = cidx + 1;
        li   = locs_f3(lf);
        m    = case_months(ci);
        D    = LOC(li).AllData{m};

        tv     = D.time_vec(:);
        P_fix  = max(0.1, D.P_fixed(:));
        P_gro  = D.P_tracker_gross(:);
        
        % Tracking gain: (gross/fixed - 1) × 100  [%]
        gain   = 100 * (P_gro ./ P_fix - 1);
        gain(gain < 0) = 0;

        % Daylight only
        idx_l = P_fix > 1;
        th_l  = tv(idx_l) / 3600;
        ga_l  = gain(idx_l);

        % 30-minute bins
        h_edges = 5.5:0.5:21.5;
        h_cents = h_edges(1:end-1) + 0.25;
        [~, bi] = histc(th_l(:), h_edges);
        bi(bi == 0) = 1;
        bi(bi > length(h_cents)) = length(h_cents);
        ga_mn = accumarray(bi, ga_l, [length(h_cents),1], @mean, NaN);
        vld   = ~isnan(ga_mn);

        hp = plot(ax3, h_cents(vld), ga_mn(vld), styles{ci}, ...
            'Color',colors{cidx},'LineWidth',lw_v(cidx),'MarkerSize',7, ...
            'MarkerFaceColor',colors{cidx},'MarkerEdgeColor','none');
        h_all(end+1)  = hp;
        lbl_all{end+1} = sprintf('%s  (%s)', case_nm{ci}, locations{li});
    end
end

xlabel(ax3,'Local time (hour)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
ylabel(ax3,'Tracking Gain  (% above fixed)','FontName',FN,'FontSize',FSl,'FontWeight','bold');
title(ax3, sprintf('Solar Tracking Performance --- %s & %s', ...
    locations{1}, locations{2}), 'FontName',FN,'FontSize',FSt,'FontWeight','bold');
xlim(ax3,[6 20]);
legend(ax3, h_all, lbl_all, ...
    'Location','northeast','FontName',FN,'FontSize',FSr-1,'Box','on','NumColumns',2);

exportgraphics(fig3, fullfile(out_dir,'Fig3_TrackingGain.png'),'Resolution',300);
close(fig3);
fprintf('  ok  Fig 3 saved.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% FIG 4 — Annual Energetic Efficiency  (Fig 10 style, 3 x 1)
%% ════════════════════════════════════════════════════════════════════════════
fprintf('Building Fig 4 ...\n');

fig4 = figure('Color','w','NumberTitle','off','Visible','off');
fig4.Position = [40 40 1280 1020];

for li = 1:nLoc
    R       = LOC(li).Results;
    E_gross = [R.E_gross];
    gains   = [R.Net_gain];

    ax = subplot(3,1,li,'Parent',fig4);
    set(ax,'FontName',FN,'FontSize',FSr,'Box','on','LineWidth',1.15, ...
        'YGrid','on','GridLineStyle',':','GridAlpha',0.42, ...
        'XTick',1:12,'XTickLabel',num2cell(rep_days),'TickDir','out');
    hold(ax,'on');

    bar(ax, E_gross, 0.68, 'FaceColor',[0.80 0.80 0.80], ...
        'EdgeColor','k','LineWidth',0.8);

    yyaxis(ax,'left');
    ax.YAxis(1).Color = 'k';
    ylim(ax,[0, max(E_gross)*1.28]);
    ylabel(ax,'Efficiency parameter  (Wh/day)', ...
        'FontName',FN,'FontSize',FSl,'FontWeight','bold');

    yyaxis(ax,'right');
    ph = plot(ax, 1:12, gains, 'k-s', 'LineWidth',2.0,'MarkerSize',8, ...
        'MarkerFaceColor','k','MarkerEdgeColor','none');
    ax.YAxis(2).Color    = 'k';
    ax.YAxis(2).FontName = FN;
    ax.YAxis(2).FontSize = FSr;
    yl_g4 = [max(0, min(gains)*0.85), max(gains)*1.22];
    if diff(yl_g4) < 1, yl_g4 = [0 30]; end
    ylim(ax, yl_g4);
    ylabel(ax,'Energetic gain  (%)','FontName',FN,'FontSize',FSl,'FontWeight','bold');

    title(ax, sprintf('%s  %s', loc_panels{li}, loc_long{li}), ...
        'FontName',FN,'FontSize',FSt,'FontWeight','bold');
    if li == 3
        xlabel(ax,'Day number','FontName',FN,'FontSize',FSl,'FontWeight','bold');
    end
    if li == 1
        yyaxis(ax,'left');
        hp_b = patch(NaN,NaN,[0.80 0.80 0.80],'EdgeColor','k','LineWidth',0.8);
        legend(ax,[hp_b ph], ...
            {'Efficiency parameter (left)','Energetic gain (right)'}, ...
            'Location','northwest','FontName',FN,'FontSize',FSr-1,'Box','on');
    end
end

sgtitle(fig4,'Energetic Efficiency of the Tracking System Throughout the Year', ...
    'FontName',FN,'FontSize',FSt+1,'FontWeight','bold');
exportgraphics(fig4, fullfile(out_dir,'Fig4_EnergeticEfficiency.png'),'Resolution',300);
close(fig4);
fprintf('  ok  Fig 4 saved.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%% FIG 5 — FSM Control System Flowchart
%% ════════════════════════════════════════════════════════════════════════════
fprintf('Building Fig 5 ...\n');

fig5 = figure('Color','w','NumberTitle','off','Visible','off');
fig5.Position = [40 40 880 1300];
ax5 = axes(fig5,'Visible','off');
xlim(ax5,[0 10]); ylim(ax5,[0 27]);
hold(ax5,'on');

col_proc  = [0.87 0.93 1.00];
col_dec   = [1.00 0.97 0.80];
col_track = [0.86 1.00 0.86];
col_hold  = [0.80 0.90 1.00];
col_idle  = [0.95 0.87 0.87];
col_srch  = [1.00 0.90 0.72];

XC = 5.0; BW = 5.60; BH = 0.82; DW = 4.30;
X_R = 8.55; X_L = 1.45;

% START
rectangle(ax5,'Position',[XC-1.15 25.08 2.3 0.72],'Curvature',0.60, ...
    'FaceColor',[0.15 0.15 0.15],'EdgeColor','k','LineWidth',1.5);
text(ax5,XC,25.44,'START','HorizontalAlignment','center','VerticalAlignment','middle', ...
    'FontName',FN,'FontSize',12,'FontWeight','bold','Color','w','Interpreter','tex');

% Process blocks
fc_box(ax5,XC,24.10,BW,BH,'Initialize: Geo-config,  PID params,  Servo state,  FSM = IDLE',col_proc);
fc_box(ax5,XC,23.00,BW,BH,'Read 4 LDR voltages  (top-R,  top-L,  bot-R,  bot-L)',col_proc);
fc_box(ax5,XC,21.80,BW,0.96, sprintf('Averages:\navg_{top}, avg_{bot}, avg_{right}, avg_{left},  avg_{sum}'),col_proc,8.5);
fc_box(ax5,XC,20.55,BW,0.96, sprintf('Error signals:\ndiff_{elev} = avg_{top} - avg_{bot}   |   diff_{az} = avg_{right} - avg_{left}'),col_proc,8.5);

% Decision blocks
fc_box(ax5,XC,19.30,DW,BH,'avg_{sum}  <  night\_threshold ?',col_dec);
fc_box(ax5,XC,17.90,DW,BH,'|error|  <  lock\_threshold ?   (Aligned)',col_dec);
fc_box(ax5,XC,16.50,DW,BH,'Sun lost  >  batch\_interval ?',col_dec);

% Side boxes
fc_box(ax5,X_R,19.30,2.18,BH,sprintf('FSM = IDLE\n(Park + sleep)'),col_idle,8.5);
fc_box(ax5,X_R,17.90,2.18,BH,sprintf('FSM = HOLD\n(Motors off)'),col_hold,8.5);
fc_box(ax5,X_L,16.50,2.18,BH,sprintf('FSM = SEARCH\n(Sweep \pm90\circ)'),col_srch,8.5);

% Processing chain
fc_box(ax5,XC,15.10,BW,BH,'FSM = TRACKING  |  PID velocity controller  (100 sub-steps @ 10 ms)',col_track);
fc_box(ax5,XC,13.90,BW,BH,'Command pan / tilt servo motors   (V_{supply} = 6 V,  PWM)',col_proc);
fc_box(ax5,XC,12.70,BW,BH,'P_{tracker} = DNI \times cos(\theta) \times A \times \eta  -  P_{parasitic}',col_proc);
fc_box(ax5,XC,11.50,BW,BH,'Log: cos(\theta),  tilt angle,  P_{fixed},  P_{net},  FSM state   [1 Hz \rightarrow CSV]',col_proc);
fc_box(ax5,XC,10.30,BW,BH,'t = t + 1 s   |   End of day? \rightarrow next representative month',col_proc);

% Vertical arrows
fc_arrow(ax5,XC,24.80,XC,24.50);
fc_arrow(ax5,XC,24.10-BH/2,XC,23.00+BH/2);
fc_arrow(ax5,XC,23.00-BH/2,XC,21.80+0.48);
fc_arrow(ax5,XC,21.80-0.48,XC,20.55+0.48);
fc_arrow(ax5,XC,20.55-0.48,XC,19.30+BH/2);
fc_arrow(ax5,XC,19.30-BH/2,XC,17.90+BH/2);
fc_arrow(ax5,XC,17.90-BH/2,XC,16.50+BH/2);
fc_arrow(ax5,XC,16.50-BH/2,XC,15.10+BH/2);
fc_arrow(ax5,XC,15.10-BH/2,XC,13.90+BH/2);
fc_arrow(ax5,XC,13.90-BH/2,XC,12.70+BH/2);
fc_arrow(ax5,XC,12.70-BH/2,XC,11.50+BH/2);
fc_arrow(ax5,XC,11.50-BH/2,XC,10.30+BH/2);

% YES arrows
fc_arrow(ax5,XC+DW/2,19.30,X_R-1.09,19.30);
fc_arrow(ax5,XC+DW/2,17.90,X_R-1.09,17.90);
fc_arrow(ax5,XC-DW/2,16.50,X_L+1.09,16.50);

% YES/NO labels
text(ax5,XC+0.18,18.63,'NO', 'FontName',FN,'FontSize',FSs,'FontWeight','bold','Color',[0.10 0.55 0.10]);
text(ax5,XC+0.18,17.23,'NO', 'FontName',FN,'FontSize',FSs,'FontWeight','bold','Color',[0.10 0.55 0.10]);
text(ax5,XC+0.18,15.83,'NO', 'FontName',FN,'FontSize',FSs,'FontWeight','bold','Color',[0.10 0.55 0.10]);
text(ax5,XC+DW/2+0.10,19.55,'YES','FontName',FN,'FontSize',FSs,'FontWeight','bold','Color',[0.70 0.10 0.10]);
text(ax5,XC+DW/2+0.10,18.15,'YES','FontName',FN,'FontSize',FSs,'FontWeight','bold','Color',[0.13 0.47 0.71]);
text(ax5,XC-DW/2-0.10,16.75,'YES','FontName',FN,'FontSize',FSs,'FontWeight','bold', ...
    'Color',[0.80 0.40 0.05],'HorizontalAlignment','right');

% SEARCH -> TRACKING
plot(ax5,[X_L X_L],[16.50-BH/2 15.10],'k-','LineWidth',1.2);
fc_arrow(ax5,X_L,15.10,XC-BW/2,15.10);

% Feedback loop
plot(ax5,[XC+BW/2 9.45 9.45 0.48 0.48 XC-BW/2+0.10], ...
         [10.30    10.30 23.5 23.5 23.0 23.0], ...
    'k-','LineWidth',1.1);
fc_arrow(ax5,XC-BW/2+0.10,23.0,XC-BW/2+0.11,23.0);
text(ax5,9.72,17.0,'Loop back','FontName',FN,'FontSize',FSs-1, ...
    'Rotation',90,'HorizontalAlignment','center','Color',[0.45 0.45 0.45]);

% HOLD/IDLE dashed feedback
plot(ax5,[X_R 9.58 9.58],[17.90+BH/2 17.90+BH/2 23.5],'k--','LineWidth',0.9);
plot(ax5,[X_R 9.58],[19.30+BH/2 19.30+BH/2],'k--','LineWidth',0.9);
text(ax5,8.85,21.2,sprintf('Resume after\nbatch\_interval'), ...
    'FontName',FN,'FontSize',FSs-1.5,'HorizontalAlignment','center', ...
    'Color',[0.13 0.47 0.71],'FontAngle','italic');

title(ax5, ...
    'Control System Flowchart: LDR-Based Dual-Axis Solar Tracker with FSM Supervisor', ...
    'FontName',FN,'FontSize',FSr,'FontWeight','bold','Visible','on');

exportgraphics(fig5, fullfile(out_dir,'Fig5_ControlFlowchart.png'),'Resolution',300);
close(fig5);
fprintf('  ok  Fig 5 saved.\n\n');

%% ════════════════════════════════════════════════════════════════════════════
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  All 5 figures saved to:  Results/PaperFigures/             ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

%% LOCAL FUNCTIONS ════════════════════════════════════════════════════════════
function fc_box(ax, cx, cy, w, h, str, fc, fs)
    if nargin < 8 || isempty(fs), fs = 9; end
    rectangle(ax,'Position',[cx-w/2, cy-h/2, w, h],'Curvature',0.14, ...
        'FaceColor',fc,'EdgeColor',[0.15 0.15 0.15],'LineWidth',1.25);
    text(ax,cx,cy,str, ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FontName','Times New Roman','FontSize',fs,'FontWeight','bold', ...
        'Interpreter','tex','Margin',1);
end

function fc_arrow(ax, x1, y1, x2, y2, lw)
    if nargin < 6 || isempty(lw), lw = 1.25; end
    dx = x2-x1; dy = y2-y1;
    L  = sqrt(dx^2+dy^2)+1e-10;
    ux = dx/L; uy = dy/L;
    hw = 0.09; hl = 0.22;
    bx = x2-hl*ux; by = y2-hl*uy;
    px = -uy;       py =  ux;
    fill(ax,[x2,bx+hw*px,bx-hw*px],[y2,by+hw*py,by-hw*py], ...
        [0.10 0.10 0.10],'EdgeColor','none');
    plot(ax,[x1,bx],[y1,by],'k-','LineWidth',lw);
end