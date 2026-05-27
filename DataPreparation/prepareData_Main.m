%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  prepareData_Main.m                                                  ║
%% ║  Ana Veri Hazırlama Script'i — SAATLİK + GÜNLÜK                       ║
%% ║                                                                       ║
%% ║  Bu script:                                                            ║
%% ║    1. SAATLİK veri hazırlar (1-saniyelik PVGIS)                      ║
%% ║    2. GÜNLÜK veriyi saatlik interpolasyon ile hazırlar                ║
%% ║                                                                       ║
%% ║  Tutsak : Tercih ettiğiniz veri türünü seçin                         ║
%% ║                                                                       ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

fprintf('\n\n');
fprintf('╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  VERİ HAZIRLAMA MODÜLÜ — SAATLİK + GÜNLÜK                      ║\n');
fprintf('║  Batch İşleme — Tüm Konumlar                                   ║\n');
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

%% ── Veri Türü Seçimi ───────────────────────────────────────────────────
% 'HOURLY' veya 'DAILY' seçin
DATA_TYPE = 'HOURLY';  % ← DEĞİŞTİRİN: 'HOURLY' veya 'DAILY'

%% ── Konumlar ───────────────────────────────────────────────────────────
locations = {'ISTANBUL', 'ANKARA', 'ANTALYA'};

%% ── Her konum için veri hazırla ────────────────────────────────────────
prepared_datasets = cell(length(locations), 1);

fprintf('Veri Türü: %s\n\n', upper(DATA_TYPE));

for loc_idx = 1:length(locations)
    loc = locations{loc_idx};
    fprintf('\n ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    fprintf(' KONUМİ %d/%d: %s\n', loc_idx, length(locations), loc);
    fprintf(' ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    try
        if strcmp(DATA_TYPE, 'HOURLY')
            prepared_datasets{loc_idx} = prepareDataForAnalysis_Hourly(loc);
        elseif strcmp(DATA_TYPE, 'DAILY')
            prepared_datasets{loc_idx} = prepareDataForAnalysis_Daily(loc);
        else
            error('Geçersiz DATA_TYPE: %s (HOURLY veya DAILY olmalı)', DATA_TYPE);
        end
    catch ME
        fprintf('\n  ✗ HATA: %s\n', ME.message);
        fprintf('    Konum atlanıyor: %s\n\n', loc);
    end
end

%% ── ÖZET RAPORu ────────────────────────────────────────────────────────
fprintf('\n\n');
fprintf('╔════════════════════════════════════════════════════════════════╗\n');
fprintf('║  HAZIRLIK TAMAMLANDI                                           ║\n');
fprintf('╚════════════════════════════════════════════════════════════════╝\n\n');

successful = sum(~cellfun(@isempty, prepared_datasets));
fprintf('  ✓ Başarılı: %d/%d konum\n\n', successful, length(locations));

fprintf('  Oluşturulan Dosyalar (%s):\n', upper(DATA_TYPE));
for loc_idx = 1:length(locations)
    if ~isempty(prepared_datasets{loc_idx})
        loc = locations{loc_idx};
        if strcmp(DATA_TYPE, 'HOURLY')
            outfile = sprintf('prepared_data_HOURLY_%s.mat', upper(loc));
        else
            outfile = sprintf('prepared_data_DAILY_%s.mat', upper(loc));
        end
        fprintf('    • %s\n', outfile);
    end
end

fprintf('\n  Kullanım (Analysis Script içinde):\n');
if strcmp(DATA_TYPE, 'HOURLY')
    fprintf('    load(''prepared_data_HOURLY_ISTANBUL.mat'');\n');
    fprintf('    %% Saatlik veriye dayanan analiz\n\n');
else
    fprintf('    load(''prepared_data_DAILY_ISTANBUL.mat'');\n');
    fprintf('    %% Günlük veriden interpolasyonlu analiz\n\n');
end
