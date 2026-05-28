%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  PlotParasitic_Istanbul.m                                           ║
%% ║  Reviewer Comment 3 — Motor parasitic energy consumption figure     ║
%% ║  Generates Fig_Parasitic_Istanbul.png (2-panel)                     ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;

%% ── AYARLAR ──────────────────────────────────────────────────────────────
script_dir    = fileparts(mfilename('fullpath'));
fmat          = fullfile(script_dir, 'Data', 'YTU_Results_Hourly.mat');
res_dir       = fullfile(script_dir, 'Results');
if ~isfolder(res_dir), mkdir(res_dir); end

month_labels  = {'Jan','Feb','Mar','Apr','May','Jun', ...
                 'Jul','Aug','Sep','Oct','Nov','Dec'};
days_in_month = [31,28,31,30,31,30,31,31,30,31,30,31];

%% ── VERİ YÜKLEME ─────────────────────────────────────────────────────────
loaded  = load(fmat);
R       = loaded.Results;

E_para  = [R.E_para];       % Wh / representative day
E_gross = [R.E_net] + [R.E_para];
Para_r  = [R.Para_r];       % % of gross
Net_gain= [R.Net_gain];     % %
Para_yr = loaded.Para_yr;   % annual parasitic ratio %
E_para_annual = sum(E_para .* days_in_month) / 1000;  % kWh/yr

x = 1:12;

%% ── RENK PALETİ ──────────────────────────────────────────────────────────
c_low   = [0.13 0.47 0.71];   % blue  — low parasitic
c_high  = [0.84 0.19 0.15];   % red   — high parasitic
c_grid  = [0.82 0.82 0.82];

% Bar rengi: Para_r arttıkça mavi → kırmızı geçişi
bar_colors = zeros(12, 3);
for m = 1:12
    t = min(Para_r(m) / 25.0, 1.0);
    bar_colors(m,:) = (1-t)*c_low + t*c_high;
end

% Net gain bar rengi (Fig 4 ile aynı cmap)
gain_cmap_x = [-10  0  15  40  90];
gain_cmap_c = [0.26 0.45 0.70;
               0.55 0.62 0.72;
               0.60 0.65 0.40;
               0.82 0.71 0.18;
               0.94 0.80 0.08];

gain_colors = zeros(12,3);
for m = 1:12
    g = max(-10, min(90, Net_gain(m)));
    for i = 1:4
        if g >= gain_cmap_x(i) && g <= gain_cmap_x(i+1)
            t = (g - gain_cmap_x(i)) / (gain_cmap_x(i+1) - gain_cmap_x(i));
            gain_colors(m,:) = (1-t)*gain_cmap_c(i,:) + t*gain_cmap_c(i+1,:);
            break
        end
    end
end

%% ── ELSEVIER AX HELPER ───────────────────────────────────────────────────
function elsevier_ax(ax)
    ax.Box           = 'off';
    ax.TickDir       = 'out';
    ax.TickLength    = [0.018 0.025];
    ax.LineWidth     = 0.75;
    ax.FontSize      = 9;
    ax.FontName      = 'Helvetica';
    ax.GridLineStyle = ':';
    ax.GridAlpha     = 0.35;
    ax.GridColor     = [0.82 0.82 0.82];
    ax.XColor        = [0 0 0];
    ax.YColor        = [0 0 0];
    grid(ax, 'on');
    hold(ax, 'on');
end

%% ══════════════════════════════════════════════════════════════════════════
%%  FİGÜR — 2 Panel
%% ══════════════════════════════════════════════════════════════════════════
fig = figure('Color','white','Position',[60 60 800 620],'Name','Fig_Parasitic');
ax1 = subplot(2,1,1);
elsevier_ax(ax1);

%% ─── Panel (a): Parasitic ratio bars ─────────────────────────────────────
% 1. Draw the bars FIRST
for m = 1:12
    bar(ax1, m, Para_r(m), 0.65, ...
        'FaceColor', bar_colors(m,:), 'EdgeColor', 'none');
end

% 2. Replace 'yline' with 'plot' spanning across the x-axis limits (0 to 13)
h_line = plot(ax1, [0, 13], [Para_yr, Para_yr], '--', ...
    'Color', [0.3 0.3 0.3], 'LineWidth', 1.0);

% 3. Send the plotted line to the background
uistack(h_line, 'bottom');

% 4. Draw the text (Adding a white background makes it highly readable if it crosses lines)
text(ax1, 11, Para_yr + 2, sprintf('Annual avg: %.1f%%', Para_yr), ...
    'HorizontalAlignment','right', ...
    'FontSize',7.5, ...
    'Color',[0.3 0.3 0.3], ...
    'BackgroundColor', 'w', ... % <--- Added white background for readability
    'Margin', 1);               % <--- Tightens the background box

% Ratio label on top
for m = 1:12
    text(ax1, m, Para_r(m) + 0.6, sprintf('%.1f%%', Para_r(m)), ...
        'HorizontalAlignment','center','VerticalAlignment','bottom', ...
        'FontSize',7.5,'FontWeight','bold','Color','k','Clipping','on');
end

% Absolute Wh/day inside (or above if bar too small)
for m = 1:12
    if Para_r(m) > 3
        ypos = Para_r(m) / 2;
        tcol = 'white';
        va   = 'middle';
    else
        ypos = Para_r(m) + 1.8;
        tcol = [0.3 0.3 0.3];
        va   = 'bottom';
    end
    text(ax1, m, ypos, sprintf('%.2f\nWh/d', E_para(m)), ...
        'HorizontalAlignment','center','VerticalAlignment',va, ...
        'FontSize',6.5,'Color',tcol,'Clipping','on');
end

ax1.XLim = [0.4 12.6];
ax1.YLim = [0 32];
ax1.XTick      = 1:12;
ax1.XTickLabel = month_labels;
ax1.YGrid = 'on';
ylabel(ax1, 'Parasitic / Gross Energy (%)', 'FontSize', 9);
xlabel(ax1, 'Month', 'FontSize', 9);

% Legend patches
h1 = patch(ax1, NaN,NaN, c_low,  'EdgeColor','none');
h2 = patch(ax1, NaN,NaN, c_high, 'EdgeColor','none');
lg = legend(ax1, [h1 h2], ...
    {'Low parasitic (overcast / winter days)', ...
     'High parasitic (clear / summer days)'}, ...
    'Location','northwest','FontSize',8);
lg.Box = 'off';
title(ax1, '(a)  Monthly Parasitic Motor Energy Consumption — Istanbul, TR', ...
    'FontSize',9,'FontWeight','normal','HorizontalAlignment','left', ...
    'Units','normalized','Position',[0 1.04 0]);

%% ─── Panel (b): Net gain bars + parasitic ratio overlay ──────────────────
ax2 = subplot(2,1,2);
elsevier_ax(ax2);

for m = 1:12
    bar(ax2, m, Net_gain(m), 0.65, ...
        'FaceColor', gain_colors(m,:), 'EdgeColor', 'none');
end

% Gain labels
for m = 1:12
    if Net_gain(m) >= 0
        ty = Net_gain(m) + 1.2;  va = 'bottom';
    else
        ty = Net_gain(m) - 1.2;  va = 'top';
    end
    text(ax2, m, ty, sprintf('%+.1f%%', Net_gain(m)), ...
        'HorizontalAlignment','center','VerticalAlignment',va, ...
        'FontSize',7.0,'FontWeight','bold','Color','k','Clipping','on');
end

% Zero line
yline(ax2, 0, '-', 'Color', 'k', 'LineWidth', 0.6);

ax2.XLim = [0.4 12.6];
ax2.YLim = [-12 max(Net_gain)*1.22];
ax2.XTick      = 1:12;
ax2.XTickLabel = month_labels;
ax2.YGrid = 'on';
ylabel(ax2, 'Net Efficiency Gain (%)', 'FontSize', 9);
xlabel(ax2, 'Month', 'FontSize', 9);

% Parasitic ratio overlay on right axis
ax2r = axes('Position', ax2.Position, ...
    'XAxisLocation','top','YAxisLocation','right', ...
    'Color','none','XTick',[],'Box','off');
hold(ax2r,'on');
plot(ax2r, x, Para_r, '-o', 'Color',[0.2 0.2 0.2], 'LineWidth',1.5, ...
    'MarkerFaceColor',[0.2 0.2 0.2], 'MarkerSize',4.5);
ax2r.XLim = [0.4 12.6];
ax2r.YLim = [0 32];
ax2r.YColor = [0.2 0.2 0.2];
ax2r.FontSize = 9;
ax2r.TickDir = 'out';
ax2r.GridLineStyle = 'none';
ylabel(ax2r, 'Parasitic / Gross (%)', 'FontSize',9, 'Color',[0.2 0.2 0.2]);

% Link x axes so they stay aligned
linkaxes([ax2 ax2r], 'x');

% Legend
hb = patch(ax2, NaN,NaN, [0.82 0.71 0.18], 'EdgeColor','none');
hl = plot(ax2, NaN,NaN, '-o','Color',[0.2 0.2 0.2],'MarkerFaceColor',[0.2 0.2 0.2]);
lg2 = legend(ax2, [hb hl], ...
    {'\Delta\eta_{net} (%)','Parasitic / Gross (%)'}, ...
    'Location','northwest','FontSize',8);
lg2.Box = 'off';

title(ax2, '(b)  Net Efficiency Gain vs. Parasitic Ratio — Istanbul, TR', ...
    'FontSize',9,'FontWeight','normal','HorizontalAlignment','left', ...
    'Units','normalized','Position',[0 1.04 0]);

%% ── KAYDET ───────────────────────────────────────────────────────────────
out_file = fullfile(res_dir, 'Fig_Parasitic_Istanbul.png');
exportgraphics(fig, out_file, 'Resolution', 300);
fprintf('  ✓ Kaydedildi: %s\n', out_file);
close(fig);
