function updateSolarWorld(handles, S_vec, SunDist, currentTime, alpha, phi)
    % updateSolarWorld: Güneşin ve ışığın konumunu günceller.
    % DÜZELTME: 'h_Line' hatası giderildi, 'h_SunLine' kullanılıyor.
    
    % Güneş Pozisyonu (Küre üzerinde)
    P_sun = S_vec * SunDist; 
    
    % 1. Güneşi Yeniden Konumlandır
    r = handles.SunRadius; 
    [sx, sy, sz] = sphere(15); % initSolarWorld ile aynı çözünürlük
    
    % Küreyi orijinde oluştur, sonra P_sun kadar ötele
    new_X = sx * r + P_sun(1);
    new_Y = sy * r + P_sun(2);
    new_Z = sz * r + P_sun(3);
    
    set(handles.h_Sun, 'XData', new_X, 'YData', new_Y, 'ZData', new_Z);
    
    % 2. Işığı Taşı
    set(handles.h_SunLight, 'Position', P_sun);
    
    % 3. Çizgiyi Güncelle (HATA BURADAYDI, DÜZELDİ)
    % initSolarWorld'de tanımladığımız 'h_SunLine'ı kullanıyoruz.
    if isfield(handles, 'h_SunLine')
        set(handles.h_SunLine, 'XData', [0 P_sun(1)], ...
                               'YData', [0 P_sun(2)], ...
                               'ZData', [0 P_sun(3)]);
    elseif isfield(handles, 'h_Line')
        % Eski versiyonla uyumluluk (Gerekirse)
        set(handles.h_Line, 'XData', [0 P_sun(1)], ...
                            'YData', [0 P_sun(2)], ...
                            'ZData', [0 P_sun(3)]);
    end
                    
    % 4. Başlık
    set(handles.h_Title, 'String', sprintf('Saat: %s | Alt: %.1f | Az: %.1f', ...
        datestr(currentTime,'HH:MM'), alpha, phi));
    
    drawnow limitrate;
end