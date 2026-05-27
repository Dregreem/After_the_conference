%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  CompareYield_Analysis_Template.m                                    ║
%% ║  EXAMPLE - Hazırlanmış Verilerle Analiz Şablonu                      ║
%% ║                                                                       ║
%% ║  Bu script hazırlanmış verilerle analiz yapan şablondur.              ║
%% ║  Uyarla: CompareYield_Hourly.m ve CompareYield_Daily.m              ║
%% ║                                                                       ║
%% ║  Adım 1: prepareData_Main.m çalıştır (veri hazırla)                 ║
%% ║  Adım 2: Bu script'i uyarla ve çalıştır                              ║
%% ║                                                                       ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc; close all;
addpath(genpath(pwd));

%% ── VERİ YÜKLEME ───────────────────────────────────────────────────────
fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  ANALIZ BAŞLANIYOR (Hazırlanmış Veriler)                     ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

% Seçenek 1: Otomatik yük
loc_name = 'ISTANBUL';
PreparedData = loadPreparedData(loc_name);

% VEYA Seçenek 2: Manuel yük
% load('prepared_data_HOURLY_ISTANBUL.mat');
% VEYA
% load('prepared_data_DAILY_ISTANBUL.mat');

%% ── VERİ İNCELEMESİ ────────────────────────────────────────────────────
printDataReport(PreparedData);

% Temel özet
solar_data = PreparedData.solar_data;
Geo = PreparedData.Geo;
T2m_lut = PreparedData.T2m_lut;
WS_lut = PreparedData.WS_lut;
season_names = PreparedData.season_names;
month_lengths = PreparedData.month_lengths;

fprintf('  GHI İstatistikleri:\n');
fprintf('    Min: %.1f W/m²\n', min(solar_data.GHI));
fprintf('    Mak: %.1f W/m²\n', max(solar_data.GHI));
fprintf('    Ort: %.1f W/m²\n', mean(solar_data.GHI));

fprintf('  T2m LUT İstatistikleri:\n');
fprintf('    Min: %.1f°C\n', min(T2m_lut(:)));
fprintf('    Mak: %.1f°C\n', max(T2m_lut(:)));
fprintf('    Ort: %.1f°C\n', mean(T2m_lut(:)));

fprintf('\n');

%% ── PANELİ AYARLARI ────────────────────────────────────────────────────
PANEL_AREA = 0.04;        % [m²]
ETA_STC    = 0.20;        % [—]
U0         = 25.0;        % [W m⁻² K⁻¹]
U1         = 6.84;        % [W m⁻² K⁻¹ s/m]
T_STC      = 25.0;        % [°C]
gamma_P    = -0.004;      % [1/°C]

%% ── HIZLI SIMULATION (1 AY ÖRNEĞİ) ─────────────────────────────────────
fprintf('Hızlı Simulasyon: Ocak Ayı (1 Temsili Gün)\n');
fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n');

d = 1;  % Ocak
month_data = solar_data(solar_data.Month == d, :);
N = height(month_data);

if N < 100
    fprintf('  ⚠ Yeterli veri yok (N=%d). Örnek 100 kayıt alınıyor.\n', N);
    sample_idx = 1:min(100, N);
else
    sample_idx = 1:min(10000, N);  % İlk 10000 saniye
end

time_vec = month_data.Time_in_Seconds(sample_idx);
GHI = month_data.GHI(sample_idx);
T_amb_vec = T2m_lut(d, min(23, floor(double(time_vec)/3600)) + 1)';
WS_vec = WS_lut(d, min(23, floor(double(time_vec)/3600)) + 1)';

% Sabit panel
T_cell_fix = T_amb_vec + GHI / (U0 + U1*WS_vec);
eta_fix = ETA_STC * (1 + gamma_P * (T_cell_fix - T_STC));
P_fixed = GHI * PANEL_AREA * eta_fix;

% Rakamlar
fprintf('  Sabit Panel Özeti:\n');
fprintf('    Ortalama GHI    : %.1f W/m²\n', mean(GHI));
fprintf('    Ortalama T_cell : %.1f°C\n', mean(T_cell_fix));
fprintf('    Ortalama η      : %.4f (%.2f%%)\n', mean(eta_fix), 100*mean(eta_fix));
fprintf('    Toplam Enerji   : %.2f Wh\n\n', trapz(time_vec, P_fixed)/3600);

%% ── GÖRSELLEŞTIRME ─────────────────────────────────────────────────────
fprintf('Grafik oluşturuluyor...\n\n');

fig = figure('Color','w','Position',[100 100 1200 600]);

% Panel 1: İrradiance
ax1 = subplot(2,3,1);
plot(time_vec/60, GHI, 'LineWidth', 1.5, 'Color', [0.2 0.5 0.8]);
xlabel('Zaman (dakika)', 'FontSize', 10);
ylabel('GHI (W/m²)', 'FontSize', 10);
title('İrradiance Profili', 'FontSize', 11, 'FontWeight', 'bold');
grid on; grid minor;

% Panel 2: Hücre Sıcaklığı
ax2 = subplot(2,3,2);
plot(time_vec/60, T_amb_vec, 'DisplayName', 'T_amb', 'LineWidth', 1.5);
hold on;
plot(time_vec/60, T_cell_fix, 'DisplayName', 'T_cell (fixed)', 'LineWidth', 1.5);
xlabel('Zaman (dakika)', 'FontSize', 10);
ylabel('Sıcaklık (°C)', 'FontSize', 10);
title('Sıcaklık Profileri', 'FontSize', 11, 'FontWeight', 'bold');
legend('FontSize', 9);
grid on; grid minor;

% Panel 3: Efficiency
ax3 = subplot(2,3,3);
plot(time_vec/60, eta_fix*100, 'LineWidth', 1.5, 'Color', [0.8 0.2 0.2]);
xlabel('Zaman (dakika)', 'FontSize', 10);
ylabel('Verimlilik (%)', 'FontSize', 10);
title('Sıcaklık Düzeltmeli η', 'FontSize', 11, 'FontWeight', 'bold');
grid on; grid minor;

% Panel 4: Güç
ax4 = subplot(2,3,4);
plot(time_vec/60, P_fixed, 'LineWidth', 1.5, 'Color', [0.2 0.8 0.2]);
xlabel('Zaman (dakika)', 'FontSize', 10);
ylabel('Güç (W)', 'FontSize', 10);
title('Sabit Panel Gücü', 'FontSize', 11, 'FontWeight', 'bold');
grid on; grid minor;

% Panel 5: Rüzgar hızı
ax5 = subplot(2,3,5);
plot(time_vec/60, WS_vec, 'LineWidth', 1.5, 'Color', [0.8 0.5 0.2]);
xlabel('Zaman (dakika)', 'FontSize', 10);
ylabel('Rüzgar Hızı (m/s)', 'FontSize', 10);
title('Rüzgar Profili', 'FontSize', 11, 'FontWeight', 'bold');
grid on; grid minor;

% Panel 6: Kümülatif Enerji
ax6 = subplot(2,3,6);
E_cum = cumtrapz(time_vec, P_fixed) / 3600;
plot(time_vec/60, E_cum, 'LineWidth', 2, 'Color', [0.5 0.2 0.8]);
xlabel('Zaman (dakika)', 'FontSize', 10);
ylabel('Kümülatif Enerji (Wh)', 'FontSize', 10);
title('Enerji Toplama', 'FontSize', 11, 'FontWeight', 'bold');
grid on; grid minor;

sgtitle(sprintf('Tespit Analizi: %s (%s)', Geo.Name, PreparedData.data_type), ...
    'FontSize', 13, 'FontWeight', 'bold');

print(gcf, 'analysis_example.png', '-dpng', '-r150');
fprintf('  ✓ Grafik kaydedildi: analysis_example.png\n\n');

%% ── NOTLAR ─────────────────────────────────────────────────────────────
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  KULLANIM NOTLARI                                           ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

fprintf('Bu template dosyasından main analysis script''i oluştur:\n\n');
if strcmp(PreparedData.data_type, 'HOURLY_AVERAGED')
    fprintf('  → Uyarla CompareYield_Hourly.m olarak\n');
    fprintf('  → 12 ay × 86400 saniye simülasyonu\n');
else
    fprintf('  → Uyarla CompareYield_Daily.m olarak\n');
    fprintf('  → Günlük veri → saatlik interpolasyon\n');
end

fprintf('\n  Önemli: Hazırlanmış veri yapısını kontrol et:\n');
fprintf('    PreparedData.solar_data    → PVGIS tablosu\n');
fprintf('    PreparedData.T2m_lut       → [12×24] saatlik lut\n');
fprintf('    PreparedData.WS_lut        → [12×24] saatlik lut\n');
fprintf('    PreparedData.data_type     → %s\n\n', PreparedData.data_type);
