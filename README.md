# Casper Excalibur G870 — macOS Sequoia

Casper Excalibur G870.1362-BV70X-C bilgisayarıma macOS Sequoia 15.8.1 (24H32) kurdum. Kendi cihazımda kullandığım EFI'yi, kamera uygulamasını ve G870 Control Center dosyalarını aynı modeli kullananların da faydalanması için burada paylaşıyorum.

İlk kurulum USB'sini Windows'ta **NullMoth 1401** ile hazırladım. EFI'nin büyük bölümünü 1401'in oluşturduğu yapılandırmadan aldım; Wi-Fi, ses, parlaklık, klavye, touchpad ve kamera için kendi cihazımda kullandığım düzenlemeleri ve kurulum sonrası araçları bu depoda bir araya getirdim. Kullandığım üçüncü taraf projeleri [THIRD-PARTY.md](THIRD-PARTY.md) dosyasında belirttim.

## Kullandığım bilgisayar

| Parça | Model / sürüm |
|---|---|
| Bilgisayar | Casper Excalibur G870.1362-BV70X-C |
| İşlemci | Intel Core i7-13620H |
| Harici ekran kartı | NVIDIA GeForce RTX 5070 8 GB |
| İşletim sistemi | macOS Sequoia 15.8.1 — 24H32 |

## Bende çalışanlar

- Wi-Fi
- Ses
- Uyku
- Ekran parlaklığı
- Klavye
- Touchpad
- Kamera — aşağıdaki uygulama ve uzantı kurulumu ile

Bu liste kendi bilgisayarımda kullandığım sistemin durumunu anlatıyor. Paketi farklı bir G870 varyantında veya başka bir bilgisayarda temiz kurulum yaparak henüz test etmedim. Aynı G870 adı altında kamera, Wi-Fi kartı veya başka donanımlar farklı olabilir.

## Klavye ve touchpad için kullandığım kext'ler

Klavye ve touchpad desteğini EFI içinde yapılandırdım. Kullandığım dosyalar `EFI/OC/Kexts` altında; aşağıdaki girdiler `config.plist > Kernel > Add` bölümünde etkin.

| Aygıt / görev | Kullandığım kext'ler |
|---|---|
| PS/2 klavye | `VoodooPS2Controller.kext` ve içindeki `VoodooPS2Keyboard.kext` |
| I2C touchpad | `VoodooI2C.kext` ve `VoodooI2CHID.kext` |
| Girdi ve I2C yardımcıları | `VoodooInput.kext`, `VoodooGPIO.kext` ve `VoodooI2CServices.kext` |
| G870 I2C denetleyici eşleştirmesi | `G870-I2C-51E8.kext` |

`VoodooPS2Keyboard`, `VoodooGPIO` ve `VoodooInput` girdileri ilgili ana kext'in içindeki `Contents/PlugIns` konumlarından yüklenmek üzere ayarlı. `G870-I2C-51E8.kext` ise Intel `8086:51E8` denetleyicisini VoodooI2C ile eşleştiren, ayrı çalıştırılabilir dosyası olmayan bir yapılandırma kext'i. Kendi cihazımda klavye ve touchpad'i bu EFI ile kullanıyorum; farklı G870 donanımlarında aynı sonucu henüz doğrulamadım.

## Ekran kartı hakkında

**Intel dahili GPU hızlandırması bende çalışmıyor.** `WhateverGreen.kext` EFI'de mevcut ve etkin; ancak bu dosyanın bulunması Intel GPU hızlandırmasının çalıştığı anlamına gelmiyor.

RTX 5070 için sürücü kurulumu sırasında NullMoth 1401'i kullandım. 1401 uygulamasını ve NVIDIA sürücü paketini bu depoya eklemedim. Bunları resmî projelerden edinebilirsiniz:

- [NullMoth 1401](https://github.com/nullmoth/1401)
- [NullMoth NVIDIA macOS Driver](https://github.com/nullmoth/nvidia-macos-driver)

## Depoda neler var?

| Konum | İçerik |
|---|---|
| `EFI/` | Paylaşım için kişisel SMBIOS alanlarını temizlediğim EFI |
| `Kurulum-Sonrasi-Uygulamalar/01-NVIDIA/` | Resmî 1401 ve sürücü kaynaklarına yönlendirme |
| `Kurulum-Sonrasi-Uygulamalar/02-Kamera/` | Kamera uygulaması ve `Kaynak-Kodlari/0.4/` altında kaynakları |
| `Kurulum-Sonrasi-Uygulamalar/03-Control-Center/` | Control Center, yerel kurucu ve `Kaynak-Kodlari/` altında kaynakları |
| [README-TR.txt](README-TR.txt) | Ayrıntılı kurulum sonrası adımları |
| [THIRD-PARTY.md](THIRD-PARTY.md) | Üçüncü taraf bileşenler ve kaynak depoları |

## Windows'ta kurulum USB'si hazırlama

1. [NullMoth 1401'in resmî deposundaki](https://github.com/nullmoth/1401) Windows yönergelerini izleyerek USB'yi hazırlayın. Ben ilk kurulumu bu yöntemle yaptım.
2. USB'deki mevcut EFI'yi yedekleyin.
3. Bu depodaki `EFI/OC` klasörünü USB'nin `EFI` klasörüne kopyalayın ve mevcut `OC` klasörünü bununla değiştirin. **1401'in oluşturduğu `EFI/BOOT` ve `EFI/Microsoft` klasörlerini koruyun.** Bu depodaki `EFI/BOOT`, paylaştığım EFI kopyasının parçasıdır; 1401 USB'sini hazırlarken bütün EFI klasörünü doğrudan bununla değiştirmeyin.
4. `EFI/OC/config.plist` içindeki `PlatformInfo > Generic` bölümüne kendinize ait SMBIOS bilgilerini girin. Seri numarası, MLB ve SystemUUID alanlarını paylaşım kopyasında boş bıraktım; ROM'u sıfırladım. Bunları kendi cihazınıza göre doldurun.
5. USB'den açılıp macOS kurulumuna geçin. Disk işlemlerinden önce verilerinizi ve çalışan EFI'nizi yedekleyin.

SMBIOS bilgilerini oluşturmak için [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) kullanılabilir. Benim kişisel kimlik bilgilerim bu yapılandırmada bulunmuyor.

## Kurulum sonrası önerdiğim sıra

### 1. NVIDIA sürücüsü

1401 uygulamasını resmî kaynağından indirin ve projenin kendi kurulum yönergelerini izleyin. Ben sürücü kurulumunu 1401 üzerinden yaptım. Uygulamanın seçtiği OpenCore/EFI konumunu kontrol edin; kurulumda kullanılan önyükleme USB'sini gereken işlem ve yeniden başlatmalar boyunca bağlı tutun.

### 2. Kamera

1. `02-Kamera` içindeki `G870 Kamera Prototip.app` uygulamasını **Applications / Uygulamalar** klasörüne kopyalayıp oradan açın.
2. Kamerayı kullanan uygulamaları kapatın.
3. Önce **CMIO güncelle**, işlem tamamlanınca **Kamerayı eşle** düğmesini kullanın.
4. macOS'un istediği uzantı izinlerini ve yeniden başlatmayı tamamlayın.
5. Photo Booth'ta **G870 Quanta — Canlı** kamerasını seçip görüntüyü kontrol edin.

Kamerayı Quanta USB `0408:209d` modülünde kullandım. EFI tek başına bu kamera çözümünü kurmuyor; uygulamanın içindeki CMIO ve DriverKit uzantıları da gerekiyor. Uygulama ad-hoc imzalı olduğu için temiz sistemde ek kurulum engelleri çıkabilir; farklı kamera modüllerini henüz test etmedim.

### 3. G870 Control Center

1. `03-Control-Center` klasörünün tamamını yazılabilir bir yere, örneğin masaüstüne kopyalayın.
2. Açık Control Center varsa **Command + Q** ile kapatın.
3. Python 3'ün kurulu olduğundan emin olun; kurucu `/usr/bin/python3` yolunu kullanıyor.
4. `Yerel-Kurulum.command` dosyasını açın ve kurulum için istenen yönetici parolasını Terminal'e girin.
5. Kurulumdan sonra yeniden başlatıp uygulamayı, fan/mod ve RGB kontrollerini kontrol edin.

**Kurucu macOS'un bulunduğu dahili diskin EFI bölümünü hedefliyor.** EFI'yi yedekliyor; `G870Bridge.kext`, `SSDT-G870-RGB.aml` ve bunların OpenCore kayıtlarını güncelliyor. USB'deki ayrı bir EFI'ye otomatik uygulanmıyor. Uygulamayı `/Applications/G870ControlCenter.app` konumuna kuruyor.

EFI yedekleri: `/Library/Application Support/G870ControlCenter/Backups`

Kurulum sonucu aynı klasörde `yerel-kurulum-sonucu.txt` dosyasına yazılıyor. Çalışan USB kurtarma kopyanızı kurulum ve açılış testleri tamamlanana kadar saklayın. Paylaştığım kurucunun temiz bir bilgisayardaki yönetici kurulumu ve USB'siz açılışı henüz ayrıca doğrulanmadı.

## Kaynaklar ve lisanslar

Bu depoda kendi cihazım için bir araya getirdiğim yapılandırmayı ve araçları paylaşıyorum. OpenCore, kext'ler ve NullMoth projeleri kendi geliştiricilerine ait. Kaynak bağlantılarını [THIRD-PARTY.md](THIRD-PARTY.md) dosyasına ekledim. Her bileşenin kendi lisans ve bildirim koşulları geçerli; kaynak bağlantısı tek başına lisans metninin yerini tutmuyor.

Kamera ve Control Center kaynaklarını ilgili `Kaynak-Kodlari` klasörlerine ekledim. Kaynak kodun bulunması, depodaki bütün bileşenlerin tek bir lisans altında olduğu anlamına gelmiyor.

Apple bu donanımda macOS kurulumunu desteklemiyor. Burada paylaştığım durum, kendi G870 bilgisayarımda yaptığım kurulumun sonucu.
