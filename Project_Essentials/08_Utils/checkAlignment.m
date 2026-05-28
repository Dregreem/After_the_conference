function [theta_error, status, Sz_body] = checkAlignment(S_body)
% checkAlignment: Geliş Açısı (Incidence Angle) Kontrolü
%
% ===== TEKNİK TASARIM RAPORU UYUMLU =====
% Referans: Bölüm 7 (Başarı Kriteri - Hizalama Kontrolü)
%
% "Ground Truth" metriği: Panelin güneşe ne kadar iyi baktığını ölçer.
%
% Formül:
%   θ_hata = arccos(Sz_body)
%
% Yorumlama:
%   θ = 0°   → Panel tam güneşe bakıyor (Sz = 1)
%   θ = 90°  → Panel güneşe dik (Sz = 0)
%   θ = 180° → Panel güneşten ters yöne bakıyor (Sz = -1)
%
% Girdiler:
%   S_body : 3x1 Güneş vektörü (Body Frame'de)
%            [Sx, Sy, Sz] formatında
%
% Çıktılar:
%   theta_error : Geliş açısı hatası (Derece)
%   status      : Durum string'i ('KİLİTLENDİ', 'YAKIN', 'TAKİP EDİYOR')
%   Sz_body     : Z bileşeni (Debug için)
%
% Yazar: Gemini - Kontrol Sistemleri Mühendisi
% Versiyon: 1.0

    %% 1. Z BİLEŞENİNİ AL
    S = S_body(:);  % Sütun vektörü garantisi
    Sz_body = S(3);
    
    %% 2. GELİŞ AÇISI HESABI
    % θ = arccos(Sz)
    % Sz değeri [-1, 1] aralığında olmalı (hata koruması)
    
    Sz_clamped = max(-1.0, min(1.0, Sz_body));
    theta_error = acosd(Sz_clamped);  % Derece cinsinden
    
    %% 3. DURUM TESPİTİ
    % Teknik Rapor Bölüm 7:
    %   θ < 0.5° → SİSTEM KİLİTLENDİ (OPTIMAL)
    %   θ > 0.5° → TAKİP DEVAM EDİYOR
    
    if theta_error < 0.5
        status = 'KİLİTLENDİ';        % Optimal pozisyon
    elseif theta_error < 2.0
        status = 'ÇOK YAKIN';         % Neredeyse kilitli
    elseif theta_error < 10.0
        status = 'YAKIN';             % Yaklaşıyor
    elseif theta_error < 45.0
        status = 'TAKİP EDİYOR';      % Normal takip
    else
        status = 'BÜYÜK SAPMA';       % Sistem geride kalmış
    end

end
