%% ╔══════════════════════════════════════════════════════════════════════╗
%% ║  CalculateAnnualYield.m                                              ║
%% ║  Yıllık Enerji Üretimi Hesaplayıcı                                   ║
%% ║                                                                       ║
%% ║  Sabit Panel ve Tracker için ayrı ayrı:                              ║
%% ║    - Yıllık brüt üretim  (Wh/yr ve kWh/yr)                          ║
%% ║    - Yıllık parazitik tüketim (motor)                                ║
%% ║    - Yıllık net üretim                                               ║
%% ║    - Net kazanç (%)                                                  ║
%% ║    - Spesifik verim (Wh/m²/gün)                                      ║
%% ║                                                                       ║
%% ║  GİRDİ: *_Results_Hourly.mat dosyaları (RunAll.m çıktısı)           ║
%% ║  ÇIKTI: Konsol tablosu + AnnualYield_Summary.mat                    ║
%% ╚══════════════════════════════════════════════════════════════════════╝

clear; clc;

%% ── AYARLAR ─────────────────────────────────────────────────────────────
cities = {'ANTALYA', 'ANKARA', 'YTU'};

PANEL_AREA = 0.04;          % m² — simülasyon panel alanı
EF_GRID    = 0.400;         % kgCO2-eq/kWh — Türkiye grid emisyon faktörü

% .mat dosyalarının aranacağı klasörler (script dizinine göre)
script_dir = fileparts(mfilename('fullpath'));
search_dirs = {script_dir, fullfile(script_dir,'Data'), fullfile(script_dir,'..','Data'), ...
               fullfile(script_dir,'..','12_Data','Finalized_Results')};  % FIX: added actual .mat path

%% ── SONUÇ DEPOSU ─────────────────────────────────────────────────────────
Summary = struct();

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════════════════╗\n');
fprintf('║  YILLIK ENERJİ ÜRETİMİ HESABI — SABİT vs. TRACKER                      ║\n');
fprintf('╚══════════════════════════════════════════════════════════════════════════╝\n\n');

for c = 1:numel(cities)
    city = cities{c};
    
    %% ── .mat dosyasını bul ───────────────────────────────────────────────
    mat_name = sprintf('%s_Results_Hourly.mat', city);
    mat_path = '';
    for d = 1:numel(search_dirs)
        candidate = fullfile(search_dirs{d}, mat_name);
        if isfile(candidate)
            mat_path = candidate;
            break;
        end
    end
    
    if isempty(mat_path)
        fprintf('  ✗ %s bulunamadı — atlanıyor\n\n', mat_name);
        continue;
    end
    
    fprintf('  Yüklüyorum: %s\n', mat_path);
    loaded = load(mat_path);
    
    %% ── Struct alanlarını bul ────────────────────────────────────────────
    % RunAll.m farklı isimler kaydedebilir — esnek okuma
    fnames = fieldnames(loaded);
    R = loaded.(fnames{1});   % ilk değer (cell veya struct olabilir)
    
    % Eğer cell array ise, ilk elemanı çıkar
    if iscell(R) && isstruct(R{1})
        R = R{1};
    elseif iscell(R) && ~isstruct(R{1})
        % Eğer hücreler sayısal veriyse, direkt loaded kullan
        R = loaded;
    end
    
    % Alan adlarını normalize et (büyük/küçük harf toleranslı)
    rf = fieldnames(R);
    rf_lower = lower(rf);
    
    get_field = @(pattern) R.(rf{~cellfun(@isempty, ...
        regexp(rf_lower, pattern, 'once')), end});
    
    %% ── Aylık verileri çıkar ─────────────────────────────────────────────
    % Aylık üretim değerleri (Wh) — field adları farklı olabilir
    % Olası isimler: E_fixed, E_fix, Fixed_Wh, E_gross, E_net, E_para
    
    has = @(pat) any(~cellfun(@isempty, regexp(rf_lower, pat, 'once')));
    get = @(pat) R.(rf{find(~cellfun(@isempty, regexp(rf_lower, pat, 'once')), 1)});
    
    % --- Sabit panel ---
    if has('e_fix')
        E_fix_monthly = get('e_fix');   % [1×12] Wh
    elseif has('fixed')
        E_fix_monthly = get('fixed');
    else
        error('Sabit panel enerji alanı bulunamadı. Mevcut alanlar: %s', ...
            strjoin(rf, ', '));
    end
    
    % --- Tracker brüt ---
    if has('e_gross')
        E_gross_monthly = get('e_gross');
    elseif has('gross')
        E_gross_monthly = get('gross');
    else
        E_gross_monthly = E_fix_monthly * NaN;
        warning('Brüt tracker alanı bulunamadı.');
    end
    
    % --- Parazitik (motor) ---
    if has('e_para')
        E_para_monthly = get('e_para');
    elseif has('para')
        E_para_monthly = get('para');
    else
        E_para_monthly = zeros(1,12);
        warning('Parazitik enerji alanı bulunamadı — sıfır alındı.');
    end
    
    % --- Net tracker ---
    if has('e_net')
        E_net_monthly = get('e_net');
    else
        E_net_monthly = E_gross_monthly - E_para_monthly;
    end
    
    % --- Aylık net kazanç (%) ---
    if has('net_gain')
        gain_monthly = get('net_gain');
    else
        gain_monthly = (E_net_monthly - E_fix_monthly) ./ E_fix_monthly * 100;
    end
    
    %% ── Gün sayısı ağırlıklandırma ───────────────────────────────────────
    days_in_month = [31,28,31,30,31,30,31,31,30,31,30,31];
    
    % Simülasyon 12 temsili gün × 86400s → yıllık ölçekleme
    % Her ayın temsili günü → o ayın gün sayısıyla çarp
    E_fix_yr   = sum(E_fix_monthly   .* days_in_month);   % Wh/yr
    E_gross_yr = sum(E_gross_monthly .* days_in_month);
    E_para_yr  = sum(E_para_monthly  .* days_in_month);
    E_net_yr   = sum(E_net_monthly   .* days_in_month);
    
    %% ── Türetilmiş büyüklükler ───────────────────────────────────────────
    % kWh/yr
    E_fix_kWh   = E_fix_yr   / 1000;
    E_gross_kWh = E_gross_yr / 1000;
    E_para_kWh  = E_para_yr  / 1000;
    E_net_kWh   = E_net_yr   / 1000;
    
    % Net kazanç (%)
    gain_annual = (E_net_yr - E_fix_yr) / E_fix_yr * 100;
    
    % Parazitik oran (%)
    para_ratio  = E_para_yr / E_gross_yr * 100;
    
    % Spesifik verim (Wh/m²/gün)
    specific_fix = E_fix_yr  / PANEL_AREA / 365;
    specific_net = E_net_yr  / PANEL_AREA / 365;
    
    % CO2 tasarrufu (kg/yr)
    dE_kWh     = E_net_kWh - E_fix_kWh;
    CO2_saved  = dE_kWh * EF_GRID;
    
    % Alan normalize CO2 (kg/m²/yr)
    CO2_norm   = CO2_saved / PANEL_AREA;
    
    %% ── Kaydet ───────────────────────────────────────────────────────────
    Summary(c).city         = city;
    Summary(c).E_fix_Wh     = E_fix_yr;
    Summary(c).E_gross_Wh   = E_gross_yr;
    Summary(c).E_para_Wh    = E_para_yr;
    Summary(c).E_net_Wh     = E_net_yr;
    Summary(c).E_fix_kWh    = E_fix_kWh;
    Summary(c).E_gross_kWh  = E_gross_kWh;
    Summary(c).E_para_kWh   = E_para_kWh;
    Summary(c).E_net_kWh    = E_net_kWh;
    Summary(c).gain_annual  = gain_annual;
    Summary(c).para_ratio   = para_ratio;
    Summary(c).specific_fix = specific_fix;
    Summary(c).specific_net = specific_net;
    Summary(c).CO2_saved_kg = CO2_saved;
    Summary(c).CO2_norm     = CO2_norm;
    Summary(c).gain_monthly = gain_monthly;
    
end

%% ════════════════════════════════════════════════════════════════════════
%%  KONSOL TABLOSU
%% ════════════════════════════════════════════════════════════════════════

valid = find(arrayfun(@(s) isfield(s, 'city') && ~isempty(s.city), Summary));

if isempty(valid)
    fprintf('  Hiçbir şehir işlenemedi.\n');
    return;
end

fprintf('\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  SABİT PANEL — Yıllık Üretim\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  %-10s  %10s  %14s  %14s\n', ...
    'Şehir', 'Wh/yr', 'kWh/yr', 'Wh/m²/gün');
fprintf('  %s\n', repmat('-',1,55));
for i = valid
    fprintf('  %-10s  %10.1f  %14.4f  %14.2f\n', ...
        Summary(i).city, ...
        Summary(i).E_fix_Wh, ...
        Summary(i).E_fix_kWh, ...
        Summary(i).specific_fix);
end

fprintf('\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  TRACKER — Yıllık Net Üretim\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  %-10s  %10s  %14s  %14s\n', ...
    'Şehir', 'Wh/yr', 'kWh/yr', 'Wh/m²/gün');
fprintf('  %s\n', repmat('-',1,55));
for i = valid
    fprintf('  %-10s  %10.1f  %14.4f  %14.2f\n', ...
        Summary(i).city, ...
        Summary(i).E_net_Wh, ...
        Summary(i).E_net_kWh, ...
        Summary(i).specific_net);
end

fprintf('\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  KARŞILAŞTIRMA ÖZETİ\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  %-10s  %9s  %9s  %9s  %9s  %8s  %10s\n', ...
    'Şehir', 'Fix(kWh)', 'Gross(kWh)', 'Para(kWh)', 'Net(kWh)', ...
    'Gain(%)', 'Para(%)');
fprintf('  %s\n', repmat('-',1,75));
for i = valid
    fprintf('  %-10s  %9.3f  %10.3f  %9.3f  %9.3f  %+8.2f  %9.2f\n', ...
        Summary(i).city, ...
        Summary(i).E_fix_kWh, ...
        Summary(i).E_gross_kWh, ...
        Summary(i).E_para_kWh, ...
        Summary(i).E_net_kWh, ...
        Summary(i).gain_annual, ...
        Summary(i).para_ratio);
end

fprintf('\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  ÇEVRESEL FAYDA (EF = %.3f kgCO2-eq/kWh)\n', EF_GRID);
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  %-10s  %12s  %18s  %22s\n', ...
    'Şehir', 'ΔE (kWh/yr)', 'CO2 tasarrufu (kg/yr)', ...
    'CO2 norm (kg/m²/yr)');
fprintf('  %s\n', repmat('-',1,70));
for i = valid
    fprintf('  %-10s  %12.3f  %20.2f  %22.1f\n', ...
        Summary(i).city, ...
        Summary(i).E_net_kWh - Summary(i).E_fix_kWh, ...
        Summary(i).CO2_saved_kg, ...
        Summary(i).CO2_norm);
end

fprintf('\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  MAKALE TABLOSU (Section 5.2 için — yuvarlak değerler)\n');
fprintf('────────────────────────────────────────────────────────────────────────────\n');
fprintf('  %-10s  %12s  %16s  %14s  %20s\n', ...
    'City', 'Fixed(kWh/yr)', 'Tracker(kWh/yr)', 'Gain(kWh/yr)', ...
    'Avoided CO2(kgCO2/yr)');
fprintf('  %s\n', repmat('-',1,80));
for i = valid
    dE = Summary(i).E_net_kWh - Summary(i).E_fix_kWh;
    fprintf('  %-10s  %12.1f  %16.1f  %14.1f  %20.1f\n', ...
        Summary(i).city, ...
        Summary(i).E_fix_kWh, ...
        Summary(i).E_net_kWh, ...
        dE, ...
        Summary(i).CO2_saved_kg);
end

%% ── Kaydet ───────────────────────────────────────────────────────────────
save('AnnualYield_Summary.mat', 'Summary');
fprintf('\n  ✓ AnnualYield_Summary.mat kaydedildi\n\n');
