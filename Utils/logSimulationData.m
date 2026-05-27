function logSimulationData(Log, filename, PID_Params)
% LOGSIMULATIONDATA - Simülasyon Verilerini Dosyaya Kaydet
%
% Tüm log verilerini okunabilir formatta bir dosyaya yazar.
% Analiz ve debug için kullanılır.
%
% Girdiler:
%   Log      : MAIN_Simulation'dan gelen Log struct
%   filename : Çıktı dosyası adı (opsiyonel, varsayılan: 'sim_log.txt')
%   PID_Params: PID parametreleri (opsiyonel)
%
% Yazar: Gemini - Kontrol Sistemleri Mühendisi
% Versiyon: 1.0

    if nargin < 2 || isempty(filename)
        filename = 'sim_log.txt';
    end
    
    fid = fopen(filename, 'w');
    if fid == -1
        error('Dosya açılamadı: %s', filename);
    end
    
    %% BAŞLIK
    fprintf(fid, '================================================================\n');
    fprintf(fid, '         GÜNEŞ TAKİP SİSTEMİ - SİMÜLASYON LOG RAPORU\n');
    fprintf(fid, '================================================================\n');
    fprintf(fid, 'Oluşturulma Zamanı: %s\n', datestr(now));
    fprintf(fid, 'Toplam Adım Sayısı: %d\n', length(Log.Time));
    fprintf(fid, 'Simülasyon Süresi: %.1f saniye\n', Log.Time(end));
    fprintf(fid, '\n');
    
    %% PID PARAMETRELERİ
    if nargin >= 3 && ~isempty(PID_Params)
        fprintf(fid, '--- PID PARAMETRELERİ ---\n');
        if isfield(PID_Params, 'Kp'), fprintf(fid, 'Kp = %.4f\n', PID_Params.Kp); end
        if isfield(PID_Params, 'Ki'), fprintf(fid, 'Ki = %.4f\n', PID_Params.Ki); end
        if isfield(PID_Params, 'Kd'), fprintf(fid, 'Kd = %.4f\n', PID_Params.Kd); end
        if isfield(PID_Params, 'deadzone'), fprintf(fid, 'Deadzone = %.2f derece\n', PID_Params.deadzone); end
        if isfield(PID_Params, 'max_output'), fprintf(fid, 'Max Output = %.2f derece/adım\n', PID_Params.max_output); end
        fprintf(fid, '\n');
    end
    
    %% ÖZET İSTATİSTİKLER
    fprintf(fid, '--- ÖZET İSTATİSTİKLER ---\n');
    
    % Hata istatistikleri
    if isfield(Log, 'E_deg_Pan')
        fprintf(fid, 'Pan Hata (E_deg_Pan):\n');
        fprintf(fid, '  Min: %+.4f  Max: %+.4f  Ort: %+.4f  Std: %.4f\n', ...
            min(Log.E_deg_Pan), max(Log.E_deg_Pan), mean(Log.E_deg_Pan), std(Log.E_deg_Pan));
    end
    
    if isfield(Log, 'E_deg_Tilt')
        fprintf(fid, 'Tilt Hata (E_deg_Tilt):\n');
        fprintf(fid, '  Min: %+.4f  Max: %+.4f  Ort: %+.4f  Std: %.4f\n', ...
            min(Log.E_deg_Tilt), max(Log.E_deg_Tilt), mean(Log.E_deg_Tilt), std(Log.E_deg_Tilt));
    end
    
    if isfield(Log, 'Incidence')
        fprintf(fid, 'Geliş Açısı (Incidence):\n');
        fprintf(fid, '  Min: %.4f  Max: %.4f  Ort: %.4f\n', ...
            min(Log.Incidence), max(Log.Incidence), mean(Log.Incidence));
    end
    
    % Kilitleme oranı
    if isfield(Log, 'IsLocked')
        lock_ratio = sum(Log.IsLocked) / length(Log.IsLocked) * 100;
        fprintf(fid, 'Kilitleme Oranı: %.1f%%\n', lock_ratio);
    end
    
    fprintf(fid, '\n');
    
    %% MOTOR POZİSYONLARI
    fprintf(fid, '--- MOTOR POZİSYONLARI ---\n');
    if isfield(Log, 'ActualPan')
        fprintf(fid, 'Pan Açısı:\n');
        fprintf(fid, '  Başlangıç: %.2f  Bitiş: %.2f\n', Log.ActualPan(1), Log.ActualPan(end));
        fprintf(fid, '  Min: %.2f  Max: %.2f\n', min(Log.ActualPan), max(Log.ActualPan));
    end
    if isfield(Log, 'ActualTilt')
        fprintf(fid, 'Tilt Açısı:\n');
        fprintf(fid, '  Başlangıç: %.2f  Bitiş: %.2f\n', Log.ActualTilt(1), Log.ActualTilt(end));
        fprintf(fid, '  Min: %.2f  Max: %.2f\n', min(Log.ActualTilt), max(Log.ActualTilt));
    end
    fprintf(fid, '\n');
    
    %% LDR VOLTAJLARI
    fprintf(fid, '--- LDR VOLTAJLARI ---\n');
    if isfield(Log, 'LDR_Voltage')
        fprintf(fid, 'V_Right: Min=%.3f Max=%.3f Ort=%.3f\n', ...
            min(Log.LDR_Voltage(:,1)), max(Log.LDR_Voltage(:,1)), mean(Log.LDR_Voltage(:,1)));
        fprintf(fid, 'V_Left:  Min=%.3f Max=%.3f Ort=%.3f\n', ...
            min(Log.LDR_Voltage(:,2)), max(Log.LDR_Voltage(:,2)), mean(Log.LDR_Voltage(:,2)));
        fprintf(fid, 'V_Up:    Min=%.3f Max=%.3f Ort=%.3f\n', ...
            min(Log.LDR_Voltage(:,3)), max(Log.LDR_Voltage(:,3)), mean(Log.LDR_Voltage(:,3)));
        fprintf(fid, 'V_Down:  Min=%.3f Max=%.3f Ort=%.3f\n', ...
            min(Log.LDR_Voltage(:,4)), max(Log.LDR_Voltage(:,4)), mean(Log.LDR_Voltage(:,4)));
    end
    fprintf(fid, '\n');
    
    %% PID TERİMLERİ
    fprintf(fid, '--- PID TERİMLERİ (ORTALAMA) ---\n');
    if isfield(Log, 'PID_P_Pan')
        fprintf(fid, 'Pan: P=%.4f I=%.4f D=%.4f\n', ...
            mean(Log.PID_P_Pan), mean(Log.PID_I_Pan), mean(Log.PID_D_Pan));
    end
    if isfield(Log, 'PID_P_Tilt')
        fprintf(fid, 'Tilt: P=%.4f I=%.4f D=%.4f\n', ...
            mean(Log.PID_P_Tilt), mean(Log.PID_I_Tilt), mean(Log.PID_D_Tilt));
    end
    fprintf(fid, '\n');
    
    %% DETAYLI VERİ TABLOSU (İlk ve Son 20 Adım)
    fprintf(fid, '================================================================\n');
    fprintf(fid, '             DETAYLI VERİ (İLK 20 ADIM)\n');
    fprintf(fid, '================================================================\n');
    fprintf(fid, '%8s %8s %8s %8s %8s %8s %8s %8s\n', ...
        'Zaman', 'ActPan', 'ActTilt', 'TgtPan', 'TgtTilt', 'E_Pan', 'E_Tilt', 'Inc');
    fprintf(fid, '%8s %8s %8s %8s %8s %8s %8s %8s\n', ...
        '(s)', '(deg)', '(deg)', '(deg)', '(deg)', '(deg)', '(deg)', '(deg)');
    fprintf(fid, '-------- -------- -------- -------- -------- -------- -------- --------\n');
    
    num_show = min(20, length(Log.Time));
    for i = 1:num_show
        fprintf(fid, '%8.2f %+8.2f %+8.2f %+8.2f %+8.2f %+8.4f %+8.4f %8.4f\n', ...
            Log.Time(i), Log.ActualPan(i), Log.ActualTilt(i), ...
            Log.TargetPan(i), Log.TargetTilt(i), ...
            Log.E_deg_Pan(i), Log.E_deg_Tilt(i), Log.Incidence(i));
    end
    
    fprintf(fid, '\n');
    fprintf(fid, '================================================================\n');
    fprintf(fid, '             DETAYLI VERİ (SON 20 ADIM)\n');
    fprintf(fid, '================================================================\n');
    fprintf(fid, '%8s %8s %8s %8s %8s %8s %8s %8s\n', ...
        'Zaman', 'ActPan', 'ActTilt', 'TgtPan', 'TgtTilt', 'E_Pan', 'E_Tilt', 'Inc');
    fprintf(fid, '-------- -------- -------- -------- -------- -------- -------- --------\n');
    
    start_idx = max(1, length(Log.Time) - 19);
    for i = start_idx:length(Log.Time)
        fprintf(fid, '%8.2f %+8.2f %+8.2f %+8.2f %+8.2f %+8.4f %+8.4f %8.4f\n', ...
            Log.Time(i), Log.ActualPan(i), Log.ActualTilt(i), ...
            Log.TargetPan(i), Log.TargetTilt(i), ...
            Log.E_deg_Pan(i), Log.E_deg_Tilt(i), Log.Incidence(i));
    end
    
    fprintf(fid, '\n');
    fprintf(fid, '================================================================\n');
    fprintf(fid, '                         RAPOR SONU\n');
    fprintf(fid, '================================================================\n');
    
    fclose(fid);
    fprintf('Log kaydedildi: %s\n', filename);
    
    %% KONSOLA KISA ÖZET
    fprintf('\n=== HIZLI ÖZET ===\n');
    fprintf('Pan Hata Ort: %+.4f°  Tilt Hata Ort: %+.4f°\n', mean(Log.E_deg_Pan), mean(Log.E_deg_Tilt));
    fprintf('Geliş Açısı Ort: %.4f°\n', mean(Log.Incidence));
    fprintf('Kilitleme Oranı: %.1f%%\n', sum(Log.IsLocked)/length(Log.IsLocked)*100);
    fprintf('Son Pozisyon: Pan=%.2f° Tilt=%.2f°\n', Log.ActualPan(end), Log.ActualTilt(end));
    
end
