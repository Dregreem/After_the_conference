%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  PlotResults_AllCities.m                                            ║
%% ║  Finalized_analysis/Data klasöründeki tüm şehir sonuçlarını         ║
%% ║  okur ve istenen 3 figürü üretir.                                   ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;

%% ── AYARLAR ──────────────────────────────────────────────────────────────
script_dir  = fileparts(mfilename('fullpath'));
data_dir    = fullfile(script_dir, 'Data');
days_in_month = [31,28,31,30,31,30,31,31,30,31,30,31];
month_labels  = {'Jan','Feb','Mar','Apr','May','Jun', ...
                 'Jul','Aug','Sep','Oct','Nov','Dec'};

% Şehir → dosya eşleştirmesi
city_files = { ...
    'ANTALYA', 'ANTALYA_Results_Hourly.mat', 'Antalya, TR'; ...
    'ANKARA',  'ANKARA_Results_Hourly.mat',  'Ankara, TR';  ...
    'YTU',     'YTU_Results_Hourly.mat',     'Istanbul, TR' ...
};

nC = size(city_files, 1);

%% ── VERİ YÜKLEME ─────────────────────────────────────────────────────────
D = struct();

for c = 1:nC
    tag  = city_files{c,1};
    fmat = fullfile(data_dir, city_files{c,2});
    if ~isfile(fmat)
        warning('%s bulunamadı, atlanıyor: %s', tag, fmat);
        continue;
    end
    loaded = load(fmat);
    R = loaded.Results;

    D(c).tag       = tag;
    D(c).name      = city_files{c,3};
    D(c).gain_mo   = [R.Net_gain];
    D(c).eta_fix   = [R.eta_fix_mean] * 100;
    D(c).eta_trk   = [R.eta_trk_mean] * 100;
    D(c).T_amb     = [R.T_amb_mean];
    D(c).T_fix     = [R.T_cell_fix_mean];
    D(c).T_trk     = [R.T_cell_trk_mean];
    D(c).E_fix_mo  = [R.E_fixed];
    D(c).E_net_mo  = [R.E_net];
    D(c).E_para_mo = [R.E_para];
    D(c).gain_yr   = loaded.Gain_yr;
    D(c).T_fix_yr  = loaded.T_fix_yr;
    D(c).T_trk_yr  = loaded.T_trk_yr;
    if isfield(loaded, 'AllData')
        D(c).AllData = loaded.AllData;
    else
        D(c).AllData = [];
    end

    D(c).E_fix_kWh  = sum(D(c).E_fix_mo  .* days_in_month) / 1000;
    D(c).E_net_kWh  = sum(D(c).E_net_mo  .* days_in_month) / 1000;
    D(c).E_para_kWh = sum(D(c).E_para_mo .* days_in_month) / 1000;

    fprintf('  ✓ Yüklendi: %s (%s)\n', D(c).name, tag);
end

valid = find(arrayfun(@(s) isfield(s,'tag') && ~isempty(s.tag), D));
nV    = numel(valid);
fprintf('\n  %d şehir işlendi.\n\n', nV);

if nV == 0
    error('Hiçbir veri yüklenemedi. Data klasörünü kontrol edin: %s', data_dir);
end

%% ════════════════════════════════════════════════════════════════════════
%%  RENK PALETİ & ELSEVIER STİL AYARLARI
%% ════════════════════════════════════════════════════════════════════════
clr_fix  = [0.13 0.47 0.71];
clr_trk  = [0.84 0.19 0.15];
clr_amb  = [0.42 0.35 0.62];
clr_ref  = [0.50 0.50 0.50];

gain_cmap = @(g) interp1([-10 0 15 40 90], ...
    [0.26 0.45 0.70; 0.55 0.62 0.72; ...
     0.60 0.65 0.40; 0.82 0.71 0.18; 0.94 0.80 0.08], ...
    max(-10, min(90, g)));

set(groot,'defaultFigureColor',              'white');
set(groot,'defaultAxesFontSize',             9);
set(groot,'defaultAxesFontName',             'Helvetica');
set(groot,'defaultTextFontName',             'Helvetica');
set(groot,'defaultAxesLineWidth',            0.75);
set(groot,'defaultAxesBox',                  'off');
set(groot,'defaultAxesTickDir',              'out');
set(groot,'defaultAxesGridLineStyle',        ':');
set(groot,'defaultAxesGridAlpha',            0.30);
set(groot,'defaultAxesGridColor',            [0.82 0.82 0.82]);
set(groot,'defaultAxesXColor',               [0 0 0]);
set(groot,'defaultAxesYColor',               [0 0 0]);
set(groot,'defaultTextInterpreter',          'tex');
set(groot,'defaultAxesTickLabelInterpreter', 'tex');
set(groot,'defaultLegendInterpreter',        'tex');

function elsevier_ax(ax)
    ax.Box        = 'off';
    ax.TickDir    = 'out';
    ax.TickLength = [0.018 0.025];
    ax.LineWidth  = 0.75;
    ax.FontSize   = 9;
    ax.GridLineStyle = ':';
    ax.GridAlpha  = 0.30;
    ax.GridColor  = [0.82 0.82 0.82];
    ax.XColor     = [0 0 0];
    ax.YColor     = [0 0 0];
    grid(ax,'on');
    hold(ax,'on');
end

%% ════════════════════════════════════════════════════════════════════════
%%  FİGÜR 1 — Aylık Net Kazanç
%% ════════════════════════════════════════════════════════════════════════
res_dir = fullfile(script_dir, 'Results');
if ~isfolder(res_dir), mkdir(res_dir); end

y_lim_gain = [-10 100];
city_tags = {'Antalya', 'Ankara', 'Istanbul'};
fig1_suffix = {'a', 'b', 'c'};

for ci = 1:nV
    c  = valid(ci);

    fig_temp = figure('Name',sprintf('Fig1%s_%s', fig1_suffix{ci}, city_tags{ci}), ...
        'NumberTitle','off', 'Color','white', 'Position',[60 60 700 450]);
    ax = axes(fig_temp,'Position',[0.12 0.12 0.85 0.80]);
    elsevier_ax(ax);

    g = D(c).gain_mo;

    for m = 1:12
        bar(ax, m, g(m), 0.72, 'FaceColor', gain_cmap(g(m)), 'EdgeColor','none');
    end

    for m = 1:12
        if g(m) >= 0
            ty     = min(g(m) + 1.2, y_lim_gain(2) - 1.0);
            valign = 'bottom';
        else
            ty     = max(g(m) - 1.2, y_lim_gain(1) + 1.0);
            valign = 'top';
        end
        text(ax, m, ty, sprintf('%+.1f%%', g(m)), ...
            'HorizontalAlignment','center','VerticalAlignment',valign, ...
            'FontSize',8,'FontWeight','bold','Color','k','Clipping','on');
    end

    ax.XLim = [0.4 12.6];
    ax.XTick = 1:12;
    ax.XTickLabel = month_labels;
    ax.YLim = y_lim_gain;
    ax.YGrid = 'on';

    ylabel(ax,'Net Efficiency Gain (%)','FontSize',9);
    xlabel(ax,'Month','FontSize',9);

    output_file = fullfile(res_dir, sprintf('Fig1%s_%s.png', fig1_suffix{ci}, city_tags{ci}));
    exportgraphics(fig_temp, output_file, 'Resolution', 300);
    fprintf('  ✓ Fig1%s_%s.png\n', fig1_suffix{ci}, city_tags{ci});
    close(fig_temp);
end

%% ════════════════════════════════════════════════════════════════════════
%%  FİGÜR 2 — Panel Verimi
%% ════════════════════════════════════════════════════════════════════════
fig2_suffix = {'a', 'b', 'c'};
for ci = 1:nV
    c  = valid(ci);
    x  = 1:12;

    fig_temp = figure('Name',sprintf('Fig2%s_Eff_%s', fig2_suffix{ci}, city_tags{ci}), ...
        'NumberTitle','off', 'Color','white', 'Position',[60 60 700 450]);
    ax = axes(fig_temp,'Position',[0.12 0.12 0.85 0.80]);
    elsevier_ax(ax);

    ef = D(c).eta_fix;
    et = D(c).eta_trk;

    lo = min([ef et 20.0]) - 0.75;
    hi = max([ef et 20.0]) + 0.55;
    ax.XLim = [0.4 12.6];
    ax.YLim = [lo hi];

    yline(ax, 20.0, '--', 'Color', clr_ref, 'LineWidth', 0.9, 'Alpha', 0.8);
    text(ax, 0.5, 20.0, 'STC', 'VerticalAlignment','bottom', ...
        'HorizontalAlignment','left','FontSize',7.5,'Color',clr_ref,'Clipping','on');

    h1 = plot(ax, x, ef, '-o', 'Color', clr_fix, 'LineWidth', 1.5, ...
        'MarkerFaceColor', clr_fix, 'MarkerSize', 5);
    h2 = plot(ax, x, et, '-^', 'Color', clr_trk, 'LineWidth', 1.5, ...
        'MarkerFaceColor', clr_trk, 'MarkerSize', 5);

    lg = legend(ax, [h1 h2], {'\eta_{fix}', '\eta_{trk}'}, ...
        'Location','northeast','FontSize',8.5);
    lg.Box = 'off';

    ylabel(ax,'Panel Efficiency (%)','FontSize',9);
    xlabel(ax,'Month','FontSize',9);
    ax.XTick = 1:12;
    ax.XTickLabel = month_labels;

    output_file = fullfile(res_dir, sprintf('Fig2%s_Eff_%s.png', fig2_suffix{ci}, city_tags{ci}));
    exportgraphics(fig_temp, output_file, 'Resolution', 300);
    fprintf('  ✓ Fig2%s_Eff_%s.png\n', fig2_suffix{ci}, city_tags{ci});
    close(fig_temp);
end

%% ════════════════════════════════════════════════════════════════════════
%%  FİGÜR 3 — Hücre Sıcaklığı
%% ════════════════════════════════════════════════════════════════════════
fig3_suffix = {'a', 'b', 'c'};
for ci = 1:nV
    c  = valid(ci);
    x  = 1:12;

    fig_temp = figure('Name',sprintf('Fig3%s_Temp_%s', fig3_suffix{ci}, city_tags{ci}), ...
        'NumberTitle','off', 'Color','white', 'Position',[60 60 700 450]);
    ax = axes(fig_temp,'Position',[0.12 0.12 0.85 0.80]);
    elsevier_ax(ax);

    Ta = D(c).T_amb;
    Tf = D(c).T_fix;
    Tt = D(c).T_trk;

    lo = min(Ta) - 4;
    hi = max(Tt) + 7;
    ax.XLim = [0.4 12.6];
    ax.YLim = [lo hi];

    yline(ax, 25.0, '--', 'Color', clr_ref, 'LineWidth', 0.9, 'Alpha', 0.8);
    text(ax, 0.5, 25.0, '25\circC (STC)', 'VerticalAlignment','bottom', ...
        'HorizontalAlignment','left','FontSize',7.5,'Color',clr_ref,'Clipping','on');

    h1 = plot(ax, x, Ta, '-o', 'Color', clr_amb, 'LineWidth', 1.5, ...
        'MarkerFaceColor', clr_amb, 'MarkerSize', 5);
    h2 = plot(ax, x, Tf, '-s', 'Color', clr_fix, 'LineWidth', 1.5, ...
        'MarkerFaceColor', clr_fix, 'MarkerSize', 5);
    h3 = plot(ax, x, Tt, '-^', 'Color', clr_trk, 'LineWidth', 1.5, ...
        'MarkerFaceColor', clr_trk, 'MarkerSize', 5);

    lg = legend(ax, [h1 h2 h3], {'T_{amb}','T_{fix}','T_{trk}'}, ...
        'Location','northwest','FontSize',8.5);
    lg.Box = 'off';

    ylabel(ax,'Temperature (\circC)','FontSize',9);
    xlabel(ax,'Month','FontSize',9);
    ax.XTick = 1:12;
    ax.XTickLabel = month_labels;

    output_file = fullfile(res_dir, sprintf('Fig3%s_Temp_%s.png', fig3_suffix{ci}, city_tags{ci}));
    exportgraphics(fig_temp, output_file, 'Resolution', 300);
    fprintf('  ✓ Fig3%s_Temp_%s.png\n', fig3_suffix{ci}, city_tags{ci});
    close(fig_temp);
end

%% ════════════════════════════════════════════════════════════════════════
%%  FİGÜR 4 — Günlük Güç Profilleri
%% ════════════════════════════════════════════════════════════════════════
peak_month   = 12;
trough_month = 6;
fig4_suffix_pairs = {'a', 'b'; 'c', 'd'; 'e', 'f'};

for ci = 1:nV
    c = valid(ci);

    try
        if ~isempty(D(c).AllData) && numel(D(c).AllData) >= peak_month && ~isempty(D(c).AllData{peak_month})
            A   = D(c).AllData{peak_month};
            t_h = A.time_vec(:) / 3600;
            if isfield(A, 't_start_s')
                t_h = (A.time_vec(:) - A.t_start_s) / 3600;
            elseif max(t_h) > 24.5
                t_h = mod(A.time_vec(:), 86400) / 3600;
            end
            out = fullfile(res_dir, sprintf('Fig4%s_Dec_%s.png', fig4_suffix_pairs{ci,1}, city_tags{ci}));
            plot_daily_profile_filled(t_h, A.P_fixed(:), A.P_tracker_gross(:), ...
                A.P_tracker_net(:), A.P_parasitic(:), out);
        end
    catch ME
        fprintf('  ✗ Error Fig4 Dec %s: %s\n', city_tags{ci}, ME.message);
    end

    try
        if ~isempty(D(c).AllData) && numel(D(c).AllData) >= trough_month && ~isempty(D(c).AllData{trough_month})
            A   = D(c).AllData{trough_month};
            t_h = A.time_vec(:) / 3600;
            if isfield(A, 't_start_s')
                t_h = (A.time_vec(:) - A.t_start_s) / 3600;
            elseif max(t_h) > 24.5
                t_h = mod(A.time_vec(:), 86400) / 3600;
            end
            out = fullfile(res_dir, sprintf('Fig4%s_Jun_%s.png', fig4_suffix_pairs{ci,2}, city_tags{ci}));
            plot_daily_profile_filled(t_h, A.P_fixed(:), A.P_tracker_gross(:), ...
                A.P_tracker_net(:), A.P_parasitic(:), out);
        end
    catch ME
        fprintf('  ✗ Error Fig4 Jun %s: %s\n', city_tags{ci}, ME.message);
    end
end

fprintf('\n  Tüm PNG dosyaları kaydedildi: %s\n\n', res_dir);

%% ════════════════════════════════════════════════════════════════════════
%%  YARDIMCI: plot_daily_profile_filled
%%  Style B — Ribbon stili, sürekli eğriler (discrete yok)
%% ════════════════════════════════════════════════════════════════════════
%% ════════════════════════════════════════════════════════════════════════
%%  YARDIMCI: plot_daily_profile_filled (YENİ AKADEMİK VERSİYON)
%% ════════════════════════════════════════════════════════════════════════
%% ════════════════════════════════════════════════════════════════════════
%%  YARDIMCI: plot_daily_profile_filled (HİBRİT AKADEMİK VERSİYON)
%% ════════════════════════════════════════════════════════════════════════
%% ════════════════════════════════════════════════════════════════════════
%%  YARDIMCI: plot_daily_profile_filled (SUBPLOT - ALTLI ÜSTLÜ KUTU)
%% ════════════════════════════════════════════════════════════════════════
%% ════════════════════════════════════════════════════════════════════════
%%  YARDIMCI: plot_daily_profile_filled (SABİT SKALALI SUBPLOT)
%% ════════════════════════════════════════════════════════════════════════
%% ════════════════════════════════════════════════════════════════════════
%%  YARDIMCI: plot_daily_profile_filled (ESTETİK BİTİŞİK KUTU TASARIMI)
%% ════════════════════════════════════════════════════════════════════════
%% ════════════════════════════════════════════════════════════════════════
%%  YARDIMCI: plot_daily_profile_filled (TEK PANEL - 3 EĞRİ)
%%  P_fixed, P_tracker_gross, P_tracker_net — motor subplot YOK
%% ════════════════════════════════════════════════════════════════════════
function plot_daily_profile_filled(t_hours, P_fixed, P_gross, P_net, ~, out_filename)
% Tek eksen: P_fixed (mavi), P_tracker_gross (yeşil kesikli), P_tracker_net (siyah)
% Motor argümanı (~) alınır ama kullanılmaz.

    %% --- 1. Veriyi Yumuşat ---
    window_size = max(round(length(t_hours) / 150), 30);
    Pf = smoothdata(P_fixed, 'movmean', window_size);
    Pg = smoothdata(P_gross, 'movmean', window_size);
    Pn = smoothdata(P_net,   'movmean', window_size);

    %% --- 2. Renk Paleti ---
    c_fix = [0.122, 0.467, 0.706];   % Mavi
    c_gro = [0.173, 0.627, 0.173];   % Yeşil
    c_net = [0.100, 0.100, 0.100];   % Siyah
    c_shn = [0.839, 0.153, 0.157];   % Kırmızı (kayıp bölgesi için)

    %% --- 3. Figür ---
    fig = figure('Units','centimeters','Position',[0 0 16 9],'Color','white');
    ax  = axes('Parent', fig, 'Position', [0.11 0.14 0.86 0.78]);
    hold(ax, 'on');

    %% --- 4. Y Limiti (veriye göre otomatik) ---
    mask = t_hours >= 4 & t_hours <= 20;
    all_vals = [Pf(mask); Pg(mask); Pn(mask)];
    lo = floor(min(all_vals)) - 0.5;
    hi = ceil(max(all_vals))  + 0.5;
    if lo > -0.3, lo = -0.3; end

    %% --- 5. Kazanç / Kayıp Gölgesi ---
    % P_net > P_fixed → tracker kazanıyor (hafif koyu)
    fill_region(ax, t_hours, Pf, Pn, c_net,  0.06, Pn >= Pf);
    % P_net < P_fixed → tracker kaybediyor (hafif kırmızı)
    fill_region(ax, t_hours, Pf, Pn, c_shn,  0.08, Pn <  Pf);

    %% --- 6. Sıfır Referansı ---
    if lo < 0
        yline(ax, 0, ':', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
    end

    %% --- 7. Eğriler ---
    h1 = plot(ax, t_hours, Pf, '-',  'Color', c_fix, 'LineWidth', 1.8);
    h2 = plot(ax, t_hours, Pg, '--', 'Color', c_gro, 'LineWidth', 1.4);
    h3 = plot(ax, t_hours, Pn, '-',  'Color', c_net, 'LineWidth', 2.2);

    %% --- 8. Eksen Ayarları ---
    xlim(ax, [4 20]);
    ylim(ax, [lo hi]);

    step = max(1, round((hi - lo) / 5));
    yticks(ax, floor(lo):step:ceil(hi));
    xticks(ax, 4:2:20);

    set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
        'XGrid', 'on', 'YGrid', 'on', ...
        'GridColor', [0.6 0.6 0.6], 'GridAlpha', 0.25, ...
        'GridLineStyle', ':', 'Box', 'on', ...
        'TickDir', 'in', 'LineWidth', 0.9);

    ylabel(ax, 'PV Power (W)',      'Interpreter', 'latex', 'FontSize', 11);
    xlabel(ax, 'Time of Day (h)',   'Interpreter', 'latex', 'FontSize', 11);

    %% --- 9. Lejant ---
    legend(ax, [h1, h2, h3], ...
        {'$P_{\mathrm{fixed}}$', ...
         '$P_{\mathrm{tracker,gross}}$', ...
         '$P_{\mathrm{tracker,net}}$'}, ...
        'Interpreter', 'latex', 'FontSize', 10, ...
        'Location', 'northeast', 'Box', 'off');

    %% --- 10. Kaydet ---
    exportgraphics(fig, out_filename, 'Resolution', 300, 'BackgroundColor', 'white');
    fprintf('  ✓ %s\n', out_filename);
    close(fig);
end


%% ── Yardımcı: fill_region ────────────────────────────────────────────────
function fill_region(ax, x, y1, y2, color, alpha_val, condition)
    x  = x(:);
    y1 = y1(:);
    y2 = y2(:);
    if nargin >= 7
        y1c = y1; y2c = y2;
        y1c(~condition) = NaN;
        y2c(~condition) = NaN;
    else
        y1c = y1; y2c = y2;
    end
    x_p = [x;        flipud(x)];
    y_p = [y1c(:);   flipud(y2c(:))];
    fill(ax, x_p, y_p, color, 'FaceAlpha', alpha_val, 'EdgeColor', 'none');
end