# Petal Solar Tracker — SIL Proje Durumu (Devir Notu)

Bu dosya, bir sohbeti kapatıp yeni bir Claude ile **aynı yerden, bilgi kaybetmeden** devam etmek içindir. Yeni Claude önce bu dosyayı, sonra ekteki diğer dosyaları okumalı ve aşağıdaki "Sıradaki adım" bölümünden sürdürmelidir.

---

## 0. Çalışma stili (önemli — buna uy)

- Türkçe konuş, aşırı formatlama yapma (gereksiz başlık/madde/bold yok).
- Yavaş git. Üretmeden önce kullanıcıdan teyit al.
- Her parçadan sonra küçük bir test koş; kullanıcı MATLAB'de koşturup çıktıyı paylaşır, sonra devam.
- Claude'un MATLAB'i yok. Matematiği Python'da birebir doğrular, `.m` dosyalarını üretir; **kullanıcı** MATLAB'de koşturur.
- **EN ÖNEMLİ DERS:** Gerçek olan tek şey dosyalardır. Sohbette yazılmış ama dosya olmayan kod "yapıldı" sayılmaz. Bu yüzden A ve B artık gerçek dosyalardır. Bu dosyada "HAZIR" denmeyen hiçbir şeyi yapılmış kabul etme.

---

## 1. 3-aşamalı plan — neredeyiz

- **Aşama 1 (MATLAB mantıksal ikiz):** ŞU AN BURADAYIZ — başında/ortasında.
- Aşama 2 (Renode sanal STM32 + Wokwi sanal ESP32, firmware SIL): sonra.
- Aşama 3 (TCP co-simulation): en son.

Aşama 1, Simulink içinde üç alt sistemden oluşur:
- **Plant_Subsystem** (güneş + panel + motor + sensör fiziği): **HAZIR**, MATLAB'de smoke test geçti.
- **STM32_Controller** (beyin: FSM + PI): yapım aşamasında (aşağıya bak).
- **ESP32_Logger** (sensör + UART parse + CSV + SD blokaj): **henüz yok.**
- Ayrıca: TMY (gerçek hava) verisi entegrasyonu, 24 saat sim, Monte Carlo: **henüz yok.**

---

## 2. Kontrolcü mimarisi (5 parça) ve durumu

Akış: `ldr_adc → [A] hata çıkarımı → [C] FSM → (MOVE'da) [B] PI → [B+] ayna → PWM; (REPORT'ta) [D] UART`

| Parça | Ne yapar | Durum |
|------|----------|-------|
| A · `error_extractor` | 4 LDR ADC → e_pan, e_tilt, e_total, V_sum (derece) | **HAZIR + MATLAB testi geçti** |
| B · `pi_step` | hata → hız komutu → PWM (tek eksen) | **Dosya HAZIR, MATLAB testi BEKLİYOR** |
| B+ · ayna/doyum | pan ±90°'yi aşınca geometrik çevrim (Eq. 8) | yok |
| C · FSM süpervizör | move-and-sleep beyni (ne zaman hareket/uyku) | yok |
| D · UART çerçeve | 22 byte durum paketi (ESP32'ye) | yok |

Yapım sırası: A ✓ → B (teyit) → **ilk closed-loop (A+B, FSM'siz)** → C → B+ → D.

---

## 3. Gerçek-dünya sözleşmesi (İHLAL ETME)

Tasarımın "sim'de çalışır ama sahada çalışmaz" tuzağına düşmemesi için kontrolcü şu kurallara uyar:

1. **Kontrolcünün gördüğü tek girişler:** `ldr_adc[4]`, zaman, `vbat`. `S_body` veya gerçek güneş açısı YOK. Çıkışı sadece `pwm`.
2. **e_total = sqrt(e_pan² + e_tilt²)** (LDR'den). `acosd(S_body(3))` KULLANMA (sahada o bilgi yok). `error_extractor` bunu zaten dürüstçe yapıyor.
3. **İşaret konvansiyonu:** pan = `(V_R − V_L)`, tilt = `(V_D − V_U)` — yani `error_extractor`'ın konvansiyonu. Bu, yüklü Plant için doğrudur (izlenip kanıtlandı: negatif geri besleme, döngü yakınsıyor). Eski `StateManagerFSM`'in tersi olan `(V_L − V_R)` konvansiyonunu KULLANMA.
4. **Pan/tilt limiti her yerde ±90°.** Yüklü `motor_step.m` zaten ±90° (`LimitMin=-pi/2`, `LimitMax=pi/2`). Tüm katmanları ±90°'de tut.
5. **Saf-LDR takip.** Eski `main_easy.m`'deki `FLIP_OVERRIDE_FACTOR` astronomik veri (enlem/boylam/saat) gerektiren bir harman hilesiydi — TAŞIMA. Ayna (B+) yalnızca cihazın kendi pan açısını kullanır, astronomi istemez.
6. **PI, PID değil** (eski tasarımda Kd=0 zaten). Tek bir back-calculation anti-windup + güvenlik clamp'i (`pi_step` bunu temiz yapıyor). FSM'de HOLD/IDLE'a girerken integratörleri sıfırla.
7. **Motor PWM girişi alır** (hedef açı değil); PI firmware'de yaşar; motorda iç P kontrolcü yok.
8. **Parazitik güç motor akımını doğrudan alır** (PWM*0.45 lineer formülü DEĞİL; makale Eq. 9).
9. **Panel parametreleri:** A=0.04 m², η_STC=0.20, γ_P=−0.004/K. Faiman ve panel_iv aynı `(25.0 + 6.84*wind)` paydasını kullanır; wind dışarıdan girer.

---

## 4. PI parametreleri

`Kp=3.188`, `Ki=10.317`, `v_max=15 °/s`, `I_max=10`, `dt=0.05` (kontrolcü 50 ms = 20 Hz).
Plant `dt=0.01` (10 ms). Kontrolcü, Simulink'te 50 ms'lik bir Triggered Subsystem + Rate Transition olur (5 fizik adımına 1 karar).

---

## 5. A ve B test beklentileri (yeniden doğrulamak için)

**error_extractor (MATLAB'de DOĞRULANDI):**
- Batı `[4.11;4.41;4.30;4.30] V` → `e_pan=-3.49`, `e_tilt=+0.00`, `Vsum=17.12`
- Dengeli `[2048;2048;2048;2048]` → hepsi `0`

**pi_step (Kp=3.188, Ki=10.317, dt=0.05, v_max=15, I_max=10) — MATLAB teyidi BEKLİYOR:**
- `e=0` → `v=0, I=0, pwm=0`
- `e=+5`: k=1 `v=+11.80 pwm=+787`; k=10 `v=+14.69 pwm=+979`; k=30 `v=+14.98 I≈+3.84 pwm=+999`
- `e=-5` → tam negatif aynası (`v=-14.98, pwm=-999`)
- NOT: 5° hata, doyum kırılma noktasının (≈ v_max/Kp = 4.7°) üstünde. O yüzden `v` daha ilk adımda ~11.8'e fırlar, hızla ~15'e (pwm~1000) yapışır; `I` ~5'te oturur, `I_max=10` clamp'ine HİÇ değmez. (Önceki sohbetin "v küçük başlar, I~10'da durur" beklentisi YANLIŞTI; bu düzeltildi.)

---

## 6. SIL-uyumluluk raporu — geçerli 4 bulgu ve durumu

(Kullanıcının kod-üzerinde-çalışan AI'sı tarafından bulundu; bazı eski bulgular geri çekildi — flip mekanizması ve in-sistem işaret konvansiyonu sorunsuz.)

- **A1 — FSM `e_total = acosd(S_body(3))` (kritik):** sahada olmayan sinyal. → `error_extractor` zaten dürüst `e_total` veriyor; FSM bunu tüketecek. **Tasarımla çözüldü.**
- **B3 — pan limiti 90 vs 180:** yüklü `motor_step` zaten ±90°. ±180° eski proje klasöründeydi. → her katmanı ±90°'de tut. **Baseline'da tamam.**
- **C3 — FLIP_OVERRIDE astronomik veri:** saf-LDR gidiyoruz, taşımıyoruz. **Çözüldü.**
- **C1 — zenith + stiction → stick-slip:** gerçek saha etkisi. Plant motor modeli stiction'ı içeriyor, o yüzden SIL'de bilinçli strese sok, gerekirse minimum-PWM tekmesi ekle. **Sonraki test maddesi (engel değil).**

---

## 7. SIRADAKİ ADIM (buradan devam et)

1. (Gerekirse) `pi_step`'in MATLAB testini koştur, beklenen değerlerle eşleştir (Bölüm 5).
2. `controller_step.m` yaz: A + B birleşik, **FSM yok**, sürekli "izle" modu (her tick MOVE gibi). Girdi `ldr_adc, dt`; çıktı `pwm_pan, pwm_tilt`. Pan ve tilt için `pi_step`'i ayrı çağır, integratör durumlarını persistent tut.
3. `build_model.m`'i güncelle: PWM sabit stub (0) yerine `controller_step` çıkışını Plant'ın PWM girişine bağla — yani döngüyü kapat (Plant → ldr_adc → controller → pwm → Plant). Cebirsel döngü çıkarsa araya bir Unit Delay koy.
4. **İlk closed-loop koşumu:** sabah birkaç saatlik senaryo. `sun_az` hareket ederken `panel_pan` onu izliyor mu? Yakınsıyorsa işaret doğru (Bölüm 3.3 kanıtı), "çalışıyor" anı bu.
5. **Dürüst FSM (C):** eski `StateManagerFSM`'in iyi parçalarını taşı (IDLE/SEARCH/HOLD/TRACKING, gece algısı = `V_sum` ile, hold/burst sayaçları) AMA `e_total`'ı `error_extractor`'dan al, `S_body`'yi at, HOLD/IDLE'a girerken integratörleri sıfırla. KARAR NOKTASI: SIL planı 7-durum (INIT/SLEEP/WAKE/DECIDE/MOVE/REPORT/SAFE) öneriyor; kullanıcının eski kodu 5-durum. Build ederken kullanıcıyla hangisini netleştir.
6. Sonra B+ (ayna, Eq. 8), sonra D (UART 22-byte: STX/CMD/LEN/payload/CRC16/ETX, 0x10 durum).
7. Sonra ESP32_Logger, sonra TMY/24h/Monte Carlo.

---

## 8. Dosya envanteri

**Bu devir dosyası:** `PROJECT_STATE.md` (bu dosya).

**Yeni kontrolcü dosyaları (önceki sohbette üretildi):**
- `error_extractor.m` — A, HAZIR + test geçti.
- `pi_step.m` — B, dosya HAZIR, MATLAB testi bekliyor.

**Plant dosyaları (çalışıyor, smoke test geçti):**
- `plant_step.m` (entegrasyon glue, persistent motor state)
- `solar_ephemeris_local.m`, `ldr_model.m`, `readLDRs.m`
- `panel_iv_model.m`, `pvSubPanelPower.m`, `faiman_temp.m`
- `parasitic_power_model.m`, `motor_step.m` (stepTheoreticalServo, PWM girişli, ±90°)
- `build_model.m` (Simulink modelini programatik kurar; şu an Plant'ı sabit PWM stub ile sarıyor)
- `solar_tracker_SIL.slx` (+ `solar_tracker_SIL_V1.slx`)

**Referans (mimari gerekçe):**
- `MICRO_3-20.pdf` (akademik makale: Eq. 5-9, 14, 18-19; Tablo 1)
- `SIL_Plan_Solar_Tracker.pdf` (SIL implementasyon planı)

**Eski kontrolcü tasarımları (FSM kurarken iyi parçaları taşımak için referans — OLDUĞU GİBİ KULLANMA, S_body hilesi var):**
- `StateManagerFSM.m` (5-durum FSM + hata hesabı)
- `PID_VelocityController.m` (PID, Kd=0)
- (varsa) SIL uyumluluk hata raporu (yukarıdaki Bölüm 6'nın kaynağı)
