%% Plot Daily and Average Radiation for 4 Months - ISTANBUL
% Günlük ve ortalama ışınımı üst üste çizerek karşılaştırıyor
% Daily vs Average Global Horizontal Irradiance (GHI)

clear all; close all; clc;

% Dosya yolu
resultsDir = fileparts(mfilename('fullpath')); % Bu script'in dizini (ISTANBUL/)
months = {'Month01', 'Month02', 'Month03', 'Month04'};
monthNames = {'January', 'February', 'March', 'April'};
monthNamesTR = {'Ocak', 'Şubat', 'Mart', 'Nisan'};

% Renkler
colors = [
    230, 126, 34;    % Month 1 - Naranja
    52, 152, 219;    % Month 2 - Mavi
    46, 204, 113;    % Month 3 - Yeşil
    155, 89, 182     % Month 4 - Mor
] / 255;

% Figure ayarları
fig = figure('Position', [100, 100, 1200, 800]);
fig.Name = 'Radiation Analysis - 4 Months';

% Subplot 1: Günlük Işınım (Daily)
subplot(2, 1, 1);
hold on; grid on;

% Subplot 2: Ortalama Işınım (Average)
subplot(2, 1, 2);
hold on; grid on;

% Her ay için veri işle
for m = 1:4
    filename = fullfile(resultsDir, sprintf('DetailedTimestep_ISTANBUL_%s_Temp.csv', months{m}));
    
    if ~isfile(filename)
        warning('File not found: %s', filename);
        continue;
    end
    
    % CSV dosyasını oku
    data = readtable(filename);
    
    % Zaman ve GHI verilerini al
    time = data.Time_s;
    ghi = data.GHI_W_m2;
    
    % Işınım pozitif olan (gündüz) zamanları bul
    daylight_idx = ghi > 10; % 10 W/m² threshold
    
    if sum(daylight_idx) == 0
        continue;
    end
    
    % Zaman döngüsü oluştur (saatler cinsinden)
    time_hours = time / 3600;
    
    % ------ SUBPLOT 1: Günlük Işınım ------
    subplot(2, 1, 1);
    plot(time_hours, ghi, 'Color', colors(m,:), 'LineWidth', 1.5, ...
         'DisplayName', sprintf('%s - %s', monthNames{m}, monthNamesTR{m}));
    
    % ------ SUBPLOT 2: Ortalama Işınım ------
    subplot(2, 1, 2);
    avg_ghi = mean(ghi(daylight_idx));
    plot(time_hours(daylight_idx), repmat(avg_ghi, sum(daylight_idx), 1), ...
         'Color', colors(m,:), 'LineWidth', 2.5, 'LineStyle', '--', ...
         'DisplayName', sprintf('%s = %.1f W/m²', monthNamesTR{m}, avg_ghi));
end

% Subplot 1 ayarları
subplot(2, 1, 1);
title('Daily Solar Radiation (Günlük Işınım)', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (Hours)', 'FontSize', 11);
ylabel('GHI (W/m²)', 'FontSize', 11);
legend('Location', 'best', 'FontSize', 10);
xlim([0, 24]);
grid on;
set(gca, 'GridAlpha', 0.3);
set(gca, 'FontSize', 10);

% Subplot 2 ayarları
subplot(2, 1, 2);
title('Average Solar Radiation (Ortalama Işınım)', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (Hours)', 'FontSize', 11);
ylabel('Average GHI (W/m²)', 'FontSize', 11);
legend('Location', 'best', 'FontSize', 10);
xlim([0, 24]);
grid on;
set(gca, 'GridAlpha', 0.3);
set(gca, 'FontSize', 10);

% Genişlet
set(gcf, 'Color', 'white');
set(gcf, 'Units', 'normalized');

% Kaydet
saveas(gcf, fullfile(resultsDir, 'RadiationAnalysis_4Months.png'));
fprintf('✓ Grafik kaydedildi: RadiationAnalysis_4Months.png\n');

% Özet istatistikler
fprintf('\n========================================\n');
fprintf('RADIATION SUMMARY - 4 MONTHS\n');
fprintf('========================================\n');

for m = 1:4
    filename = fullfile(resultsDir, sprintf('DetailedTimestep_ISTANBUL_%s_Temp.csv', months{m}));
    if isfile(filename)
        data = readtable(filename);
        ghi = data.GHI_W_m2;
        daylight_idx = ghi > 10;
        
        fprintf('\n%s (%s):\n', monthNames{m}, monthNamesTR{m});
        fprintf('  • Ortalama Işınım: %.2f W/m²\n', mean(ghi(daylight_idx)));
        fprintf('  • Maksimum Işınım: %.2f W/m²\n', max(ghi));
        fprintf('  • Toplam Gündüz Saati: %.2f hours\n', sum(daylight_idx)/3600);
    end
end
fprintf('\n========================================\n');
