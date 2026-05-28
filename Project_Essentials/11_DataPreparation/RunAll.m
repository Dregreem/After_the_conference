%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  RunAll.m                                                             ║
%% ║  ANA ÇALIŞTIRICI — Tüm pipeline tek yerden, tüm konumlar sırayla     ║
%% ║                                                                       ║
%% ║  Akış:                                                                ║
%% ║    AŞAMA 1 — Tüm konumlar için: Dönüşüm + Hazırlık + Grafik          ║
%% ║    AŞAMA 2 — Toplu onay (hangi konumlar simüle edilsin?)             ║
%% ║    AŞAMA 3 — Sadece onaylı konumlar için simülasyon                  ║
%% ║                                                                       ║
%% ║  Kullanım: Sadece AYARLAR bölümünü doldurup F5 ile çalıştır          ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

%% ── BAŞLANGIÇ KONTROLÜ ──────────────────────────────────────────────────
if exist('DataFormatSelector.m', 'file') == 0
    dp = fullfile(pwd, 'DataPreparation');
    if isfolder(dp), addpath(dp); end
end

%% ════════════════════════════════════════════════════════════════════════
%%  AYARLAR — Yalnızca bu bölümü değiştir
%% ════════════════════════════════════════════════════════════════════════

,LOCATIONS = {
%'YTU_FROM_NASA', 'YTU_NASA_Hourly.csv', 'YTU_FROM_NASA_Hourly.csv';

'YTU', 'YTU_Hourly.csv', 'YTU_FROM_PVGISHourly.csv';

%'ANTALYA', 'ANTALYA_Hourly.csv', 'ANTALYA_FROM_PVGISHourly.csv';

%'ANKARA', 'ANKARA_Hourly.csv', 'ANKARA_FROM_PVGISHourly.csv';

};

RUN_STEP1_CONVERT   = false;  % NASA CSV → YTU CSV
RUN_STEP2_PREPARE   = true;   % YTU CSV → .mat
RUN_STEP2_5_ANALYZE = true;   % Grafik + toplu onay
RUN_STEP3_SIMULATE  = true;   % Simülasyon (onaylananlar)

DATA_MODE = 'HOURLY';   % 'HOURLY' veya 'DAILY'

nasa_options.slope        = 0;
nasa_options.azimuth      = 0;
nasa_options.radiation_db = 'NASA-POWER';

SKIP_ON_ERROR = true;

%% ════════════════════════════════════════════════════════════════════════
%%  HAZIRLIK
%% ════════════════════════════════════════════════════════════════════════

RESULTS_BASE = fileparts(mfilename('fullpath'));
t_total = tic;
n_locs  = size(LOCATIONS, 1);

% Durum takibi
s_convert  = repmat({'⏭'}, n_locs, 1);
s_prepare  = repmat({'⏭'}, n_locs, 1);
s_analyze  = repmat({'⏭'}, n_locs, 1);
s_simulate = repmat({'⏭'}, n_locs, 1);
approved   = false(n_locs, 1);  % simülasyon onayı
skip_loc   = false(n_locs, 1);  % hazırlık hatası

fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  SOLAR TRACKER — BATCH ANALİZ PİPELINE                       ║\n');
fprintf('║  Konum sayısı : %-45d║\n', n_locs);
fprintf('║  Mod          : %-45s║\n', DATA_MODE);
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

%% ════════════════════════════════════════════════════════════════════════
%%  AŞAMA 1: Tüm konumlar için Dönüşüm + Hazırlık + Grafik
%% ════════════════════════════════════════════════════════════════════════

fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
fprintf('  AŞAMA 1/3 — Veri hazırlama ve grafik oluşturma (tüm konumlar) \n');
fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n');

for loc_idx = 1:n_locs

    LOC_NAME       = LOCATIONS{loc_idx, 1};
    NASA_CSV_INPUT = LOCATIONS{loc_idx, 2};
    YTU_CSV_OUTPUT = LOCATIONS{loc_idx, 3};

    fprintf('┌────────────────────────────────────────────────────────────────┐\n');
    fprintf('│  [%d/%d] %-57s│\n', loc_idx, n_locs, LOC_NAME);
    fprintf('└────────────────────────────────────────────────────────────────┘\n\n');

    %% Adım 1: Dönüşüm
    if RUN_STEP1_CONVERT && ~isempty(NASA_CSV_INPUT)
        try
            if ~isfile(NASA_CSV_INPUT)
                error('NASA CSV bulunamadı: %s', NASA_CSV_INPUT);
            end
            NASA_to_YTU(NASA_CSV_INPUT, YTU_CSV_OUTPUT, nasa_options);
            fprintf('  ✓ Dönüşüm: %s\n', YTU_CSV_OUTPUT);
            s_convert{loc_idx} = '✓';
        catch ME
            fprintf('  ✗ Dönüşüm hatası: %s\n\n', ME.message);
            s_convert{loc_idx} = '✗';
            skip_loc(loc_idx) = true;
            continue;
        end
    end

    %% Adım 2: Veri Hazırlama
    if RUN_STEP2_PREPARE
        fprintf('  ◆ Veri hazırlanıyor...\n');
        try
            if strcmpi(DATA_MODE, 'HOURLY')
                prepareDataForAnalysis_Hourly(LOC_NAME);
            else
                prepareDataForAnalysis_Daily(LOC_NAME);
            end
            fprintf('  ✓ .mat hazır\n');
            s_prepare{loc_idx} = '✓';
        catch ME
            fprintf('  ✗ Hazırlık hatası: %s\n\n', ME.message);
            s_prepare{loc_idx} = '✗';
            skip_loc(loc_idx) = true;
            continue;
        end
    end

    %% Adım 2.5: Grafik Oluştur (onay sormadan, sadece kaydet)
    if RUN_STEP2_5_ANALYZE
        fprintf('  ◆ Analiz grafikleri oluşturuluyor...\n');
        try
            AnalyzeIrradianceProfiles_NoPrompt(LOC_NAME, DATA_MODE, RESULTS_BASE);
            fprintf('  ✓ Grafikler kaydedildi\n');
            s_analyze{loc_idx} = '✓';
        catch ME
            fprintf('  ✗ Grafik hatası: %s\n', ME.message);
            s_analyze{loc_idx} = '✗';
        end
    end

    fprintf('\n');
end

%% ════════════════════════════════════════════════════════════════════════
%%  AŞAMA 2: Toplu Onay
%% ════════════════════════════════════════════════════════════════════════

if RUN_STEP2_5_ANALYZE && RUN_STEP3_SIMULATE

    fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    fprintf('  AŞAMA 2/3 — Grafikleri incele, simüle edilecek konumları seç  \n');
    fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n');
    fprintf('  Grafikler burada: %s\n\n', fullfile(RESULTS_BASE, 'Results'));

    for loc_idx = 1:n_locs
        if skip_loc(loc_idx)
            fprintf('  %-20s → Atlandı (hazırlık hatası)\n', LOCATIONS{loc_idx,1});
            continue;
        end
        LOC_NAME = LOCATIONS{loc_idx, 1};
        res_analysis = fullfile(RESULTS_BASE, 'Results', upper(LOC_NAME), 'Analysis');
        fprintf('  %-20s → %s\n', LOC_NAME, res_analysis);
    end

    fprintf('\n');
    fprintf('  ┌──────────────────────────────────────────────────────────┐\n');
    fprintf('  │  Grafikleri inceledikten sonra onay ver                   │\n');
    fprintf('  │  Her konum için: 1=Simüle et  0=Atla                     │\n');
    fprintf('  └──────────────────────────────────────────────────────────┘\n\n');

    for loc_idx = 1:n_locs
        if skip_loc(loc_idx)
            approved(loc_idx) = false;
            s_simulate{loc_idx} = '⏭ hata';
            continue;
        end
        LOC_NAME = LOCATIONS{loc_idx, 1};
        ans_val  = input(sprintf('  %-20s simüle edilsin mi? [1=Evet / 0=Hayır]: ', LOC_NAME));
        if isequal(ans_val, 1)
            approved(loc_idx) = true;
            fprintf('    ✓ Onaylandı\n\n');
        else
            approved(loc_idx) = false;
            s_simulate{loc_idx} = '✗ iptal';
            fprintf('    ✗ Atlandı\n\n');
        end
    end
else
    % Analiz kapalıysa hepsini onayla
    approved(:) = true;
end

%% ════════════════════════════════════════════════════════════════════════
%%  AŞAMA 3: Simülasyon (sadece onaylı konumlar)
%% ════════════════════════════════════════════════════════════════════════

if RUN_STEP3_SIMULATE

    n_approved = sum(approved);
    fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    fprintf('  AŞAMA 3/3 — Simülasyon (%d/%d konum onaylandı)               \n', n_approved, n_locs);
    fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n');

    for loc_idx = 1:n_locs
        if ~approved(loc_idx), continue; end

        LOC_NAME = LOCATIONS{loc_idx, 1};
        fprintf('┌────────────────────────────────────────────────────────────────┐\n');
        fprintf('│  Simülasyon: %-50s│\n', LOC_NAME);
        fprintf('└────────────────────────────────────────────────────────────────┘\n\n');

        try
            BATCH_MODE = true;
            loc_name   = LOC_NAME;
            if strcmpi(DATA_MODE, 'HOURLY')
                CompareYield_Hourly;
            else
                CompareYield_Daily;
            end
            fprintf('  ✓ Simülasyon tamamlandı\n\n');
            s_simulate{loc_idx} = '✓';
        catch ME
            fprintf('  ✗ Simülasyon hatası: %s\n', ME.message);
            fprintf('    %s satır %d\n\n', ME.stack(1).file, ME.stack(1).line);
            s_simulate{loc_idx} = '✗';
        end
    end
end

%% ── GENEL ÖZET ──────────────────────────────────────────────────────────
t_elapsed = toc(t_total);

fprintf('\n╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  BATCH TAMAMLANDI — Toplam %.0f saniye (%.1f dk)\n', t_elapsed, t_elapsed/60);
fprintf('╠══════════════════╦══════════╦══════════╦══════════╦══════════╣\n');
fprintf('║  Konum           ║ Hazırlık ║ Grafik   ║ Onay     ║ Sim.     ║\n');
fprintf('╠══════════════════╬══════════╬══════════╬══════════╬══════════╣\n');
for i = 1:n_locs
    onay_str = iif(approved(i), '✓', '✗');
    fprintf('║  %-16s║ %-8s ║ %-8s ║ %-8s ║ %-8s ║\n', ...
        LOCATIONS{i,1}, s_prepare{i}, s_analyze{i}, onay_str, s_simulate{i});
end
fprintf('╚══════════════════╩══════════╩══════════╩══════════╩══════════╝\n\n');
fprintf('  Çıktılar: %s\n\n', fullfile(RESULTS_BASE, 'Results'));

%% ── Yardımcı ─────────────────────────────────────────────────────────────
function y = iif(cond, a, b)
    if cond, y = a; else, y = b; end
end