"""
Project Essentials Extractor
=============================
Güneş takip sistemi projesinin kritik dosyalarını 'Project_Essentials' klasörüne kopyalar.
Gereksiz loglar, boş dosyalar, eski versiyonlar ve arşiv dosyaları dışarıda bırakılır.
"""

import shutil
import os
from pathlib import Path

# Proje kök dizini
ROOT = Path(r"c:\Users\Kerem Bayer\Desktop\Mikro_Konferans\System_march_extented_analysis")
DEST = ROOT / "Project_Essentials"

# ─────────────────────────────────────────────────────────────────────────────
# KRİTİK DOSYALAR: Proje çalışması için gerekli olan minimum dosya seti
# ─────────────────────────────────────────────────────────────────────────────

ESSENTIAL_FILES = {
    # ── ANA SİMÜLASYON ────────────────────────────────────────────────────
    "01_Main": [
        "main_easy.m",                    # Ana simülasyon döngüsü
        "runSimulation.m",                # Toplu simülasyon çalıştırıcı
        "runBenchmark.m",                 # Kıyaslama betiği
        "optimizeFSM.m",                  # FSM optimizasyonu
        "RunAllLocations_Temp.m",         # Tüm lokasyonlar için toplu çalıştırma
        "getGeoConfig.m",                 # Coğrafi konfigürasyon
        "prepareMonthlyCSV.m",            # Aylık CSV hazırlayıcı
    ],

    # ── KONTROLCÜLER ──────────────────────────────────────────────────────
    "02_Controllers": [
        "Controllers/PID_VelocityController.m",    # PID hız kontrolcüsü
        "Controllers/FuzzyLogicController.m",       # Mamdani bulanık mantık kontrolcüsü
        "Controllers/StateManagerFSM.m",            # Move-and-Sleep FSM (Durum yöneticisi)
        "Controllers/calculateAstronomicalTracking.m",  # Astronomik takip hesabı
    ],

    # ── FİZİK MODELLERİ ──────────────────────────────────────────────────
    "03_Physics": [
        "Physics/stepTheoreticalServo.m",           # 2. derece teorik servo (akademik model)
        "Physics/stepDCMotorPhysics.m",             # DC motor endüktans modeli
        "Physics/stepAdvancedServoPhysics.m",       # İdeal servo modeli
        "Physics/README_Math_Model.md",             # Matematik modeli belgesi
    ],

    # ── SENSÖRLER ─────────────────────────────────────────────────────────
    "04_Sensors": [
        "Sensors/readLDRs.m",                       # GL5528 LDR sensör modeli
        "Sensors/controlLDR.m",                     # LDR hata hesaplayıcı
    ],

    # ── GÜNEŞ POZİSYONU ──────────────────────────────────────────────────
    "05_Sun": [
        "Sun/getSunVector.m",                       # Güneş vektörü hesaplayıcı
        "Sun/loadPVGIS.m",                          # PVGIS veri yükleyici
        "Sun/filterPVGISbyDate.m",                  # PVGIS tarih filtresi
        "Sun/getPVGISatTime.m",                     # PVGIS zaman sorgulayıcı
    ],

    # ── PANEL HESAPLAMALARI ───────────────────────────────────────────────
    "06_Panel": [
        "Panel/pvPanelPower.m",                     # Sabit panel güç hesabı
        "Panel/pvTrackerPower.m",                   # Takip paneli güç hesabı
        "Panel/pvSubPanelPower.m",                  # Alt panel güç hesabı (çiçek modeli)
    ],

    # ── SENARYO TANIMLARI ─────────────────────────────────────────────────
    "07_Scenarios": [
        "Scenarios/generateScenario.m",             # Senaryo üreteci
    ],

    # ── YARDIMCI FONKSYONLAR ──────────────────────────────────────────────
    "08_Utils": [
        "Utils/applyFlipLogic.m",                   # Flip mantığı (azimut > 180°)
        "Utils/cartesian2spherical.m",              # Kartezyen → küresel koordinat
        "Utils/checkAlignment.m",                   # Panel hizalama kontrolü
        "Utils/getFieldOrDefault.m",                # Güvenli alan okuyucu
        "Utils/ternary.m",                          # Ternary operatör
    ],

    # ── GÖRSELLEŞTİRME ──────────────────────────────────────────────────
    "09_Visualization": [
        "Visualization/initSolarWorld.m",           # 3D dünya başlatıcı
        "Visualization/initSystemMechanics.m",      # Gimbal mekanik başlatıcı
        "Visualization/updateSolarWorld.m",         # 3D dünya güncelleyici
    ],

    # ── FİNALİZE EDİLMİŞ ANALİZ ─────────────────────────────────────────
    "10_Finalized_Analysis": [
        "Finalized_analysis/CalculateAnnualYield.m",     # Yıllık verim hesaplayıcı
        "Finalized_analysis/PlotParasitic_Istanbul.m",   # Parazitik enerji figürü
        "Finalized_analysis/PlotResults_AllCities.m",    # 3 şehir karşılaştırma figürleri
    ],

    # ── VERİ HAZIRLAMA ────────────────────────────────────────────────────
    "11_DataPreparation": [
        "DataPreparation/RunAll.m",                      # Tüm veri işleme ana betiği
        "DataPreparation/CompareYield_Hourly.m",         # Saatlik verim karşılaştırması
        "DataPreparation/prepareDataForAnalysis_Hourly.m",  # Saatlik veri hazırlayıcı
        "DataPreparation/getGeoConfig.m",                # Coğrafi yapılandırma
    ],

    # ── KRİTİK VERİ DOSYALARI ────────────────────────────────────────────
    "12_Data": [
        "YTU_NASA_Hourly.csv",                           # PVGIS saatlik veri (YTU)
        "AnnualYield_Summary.mat",                       # Yıllık verim özet dosyası
    ],

    # ── KARŞILAŞTIRMA ANALİZLERİ ─────────────────────────────────────────
    "13_CompareYield": [
        "CompareYield/CompareYield_TMY.m",               # TMY karşılaştırma
        "CompareYield/CompareYield.m",                   # Temel karşılaştırma
        "CompareYield/generateComparisonReport.m",       # Karşılaştırma raporu
    ],

    # ── MAKALE FİGÜRLERİ ─────────────────────────────────────────────────
    "14_PaperFigures": [
        "PaperFigures_5.m",                              # Makale figürleri betiği
    ],
}

# ─────────────────────────────────────────────────────────────────────────────
# DIŞARIDA BIRAKILAN DOSYALAR (Exclude List)
# ─────────────────────────────────────────────────────────────────────────────
EXCLUDE_PATTERNS = [
    "ARCHIVE/",           # Eski versiyonlar
    "TEMP_analysis/",     # Geçici analiz dosyaları
    ".git/",              # Versiyon kontrol
    ".vscode/",           # IDE ayarları
    ".qodo/",             # IDE eklentileri
    "_copy.m",            # Kopyalar (ör: StateManagerFSM_copy.m)
    ".asv",               # MATLAB otomatik kayıt dosyaları
    ".7z",                # Sıkıştırılmış arşivler
]


def main():
    """Kritik dosyaları Project_Essentials klasörüne kopyalar."""
    
    print("=" * 70)
    print("  PROJECT ESSENTIALS EXTRACTOR")
    print("  Solar Tracker - Move-and-Sleep Energy-Optimal System")
    print("=" * 70)
    
    copied = 0
    skipped = 0
    missing = 0
    
    for category, files in ESSENTIAL_FILES.items():
        dest_category = DEST / category
        dest_category.mkdir(parents=True, exist_ok=True)
        
        print(f"\n[DIR] {category}")
        print("-" * 50)
        
        for rel_path in files:
            src = ROOT / rel_path
            # Preserve only the filename (flatten into category folder)
            dst = dest_category / Path(rel_path).name
            
            if src.exists():
                shutil.copy2(str(src), str(dst))
                size_kb = src.stat().st_size / 1024
                print(f"  + {Path(rel_path).name:45s} ({size_kb:.1f} KB)")
                copied += 1
            else:
                print(f"  x {Path(rel_path).name:45s} (BULUNAMADI)")
                missing += 1
    
    # ── MAT veri dosyalarını kopyala ──────────────────────────────────
    data_dir = DEST / "12_Data" / "Finalized_Results"
    data_dir.mkdir(parents=True, exist_ok=True)
    
    fin_data = ROOT / "Finalized_analysis" / "Data"
    if fin_data.exists():
        print(f"\n[DIR] Finalized_analysis/Data (Sonuc .mat Dosyalari)")
        print("-" * 50)
        for mat_file in fin_data.glob("*.mat"):
            dst = data_dir / mat_file.name
            shutil.copy2(str(mat_file), str(dst))
            size_mb = mat_file.stat().st_size / (1024 * 1024)
            print(f"  + {mat_file.name:45s} ({size_mb:.1f} MB)")
            copied += 1
    
    # ── Hazır veri (.mat) dosyalarını kopyala ─────────────────────────
    prepared_data_dir = DEST / "12_Data" / "Prepared_Data"
    prepared_data_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"\n[DIR] Prepared Data (.mat dosyalari)")
    print("-" * 50)
    for mat_file in ROOT.glob("prepared_data_*.mat"):
        dst = prepared_data_dir / mat_file.name
        shutil.copy2(str(mat_file), str(dst))
        size_mb = mat_file.stat().st_size / (1024 * 1024)
        print(f"  + {mat_file.name:45s} ({size_mb:.1f} MB)")
        copied += 1
    
    # ── CSV veri dosyalarını kopyala ──────────────────────────────────
    csv_dir = DEST / "12_Data" / "CSV_Input"
    csv_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"\n[DIR] CSV Girdi Dosyalari")
    print("-" * 50)
    for csv_src_dir in [ROOT / "DataPreparation"]:
        for csv_file in csv_src_dir.glob("*_Hourly.csv"):
            dst = csv_dir / csv_file.name
            if not dst.exists():
                shutil.copy2(str(csv_file), str(dst))
                size_kb = csv_file.stat().st_size / 1024
                print(f"  + {csv_file.name:45s} ({size_kb:.1f} KB)")
                copied += 1
    
    # ── ÖZET ─────────────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print(f"  SONUC:")
    print(f"    + Kopyalanan: {copied} dosya")
    print(f"    x Bulunamayan: {missing} dosya")
    
    # Calculate total size
    total_size = 0
    for f in DEST.rglob("*"):
        if f.is_file() and f.name != "extract_essentials.py":
            total_size += f.stat().st_size
    print(f"    Toplam boyut: {total_size / (1024*1024):.1f} MB")
    print("=" * 70)
    
    # Create README
    readme_path = DEST / "README.md"
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write("# Project Essentials\n\n")
        f.write("Bu klasör, **Move-and-Sleep Güneş Takip Sistemi** projesinin tüm kritik dosyalarını içerir.\n\n")
        f.write("## Klasör Yapısı\n\n")
        f.write("| Klasör | Açıklama |\n")
        f.write("|--------|----------|\n")
        f.write("| `01_Main` | Ana simülasyon betiği (main_easy.m) ve yardımcı betikler |\n")
        f.write("| `02_Controllers` | PID, FLC ve FSM kontrolcüleri |\n")
        f.write("| `03_Physics` | Servo motor fizik modelleri (Teorik, DC Motor, İdeal) |\n")
        f.write("| `04_Sensors` | GL5528 LDR sensör modeli |\n")
        f.write("| `05_Sun` | Güneş pozisyonu ve PVGIS veri işleme |\n")
        f.write("| `06_Panel` | PV panel güç hesaplamaları |\n")
        f.write("| `07_Scenarios` | Senaryo üreteci |\n")
        f.write("| `08_Utils` | Yardımcı fonksiyonlar |\n")
        f.write("| `09_Visualization` | 3D görselleştirme |\n")
        f.write("| `10_Finalized_Analysis` | Yıllık verim ve makale figürleri |\n")
        f.write("| `11_DataPreparation` | Veri hazırlama betikleri |\n")
        f.write("| `12_Data` | CSV, MAT veri dosyaları |\n")
        f.write("| `13_CompareYield` | Karşılaştırma analizleri |\n")
        f.write("| `14_PaperFigures` | Makale figür betiği |\n\n")
        f.write(f"**Toplam: {copied} dosya | {total_size / (1024*1024):.1f} MB**\n")
    
    print(f"\n  README.md olusturuldu: {readme_path}")
    print("\n  Islem tamamlandi!\n")


if __name__ == "__main__":
    main()
