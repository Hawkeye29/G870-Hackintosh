CASPER EXCALIBUR G870 — KURULUM VE KURULUM SONRASI REHBERİ

Bu sistemi Casper Excalibur G870.1362-BV70X-C bilgisayarıma kurdum.
İşlemcim Intel Core i7-13620H, harici ekran kartım RTX 5070 8 GB.
Kullandığım macOS sürümü Sequoia 15.8.1 (24H32).

İlk USB'yi Windows'ta NullMoth 1401 ile hazırladım. EFI'nin büyük bölümünü
1401'in oluşturduğu yapılandırmadan aldım; kendi bilgisayarımda kullandığım
düzenlemeleri ve kurulum sonrası araçları bu depoda topladım.

1. BENDEKİ DURUM

Wi-Fi, ses, uyku, ekran parlaklığı, klavye ve touchpad çalışıyor.
Kamerayı aşağıda anlattığım uygulama ve uzantı kurulumu ile kullanıyorum.
Intel dahili GPU hızlandırması bende çalışmıyor. WhateverGreen.kext EFI'de
mevcut ve etkin, ancak bu Intel GPU hızlandırmasının çalıştığı anlamına gelmiyor.
RTX 5070 için sürücü kurulumunu 1401 üzerinden yaptım.

Paketi başka bilgisayarda veya farklı bir G870 varyantında temiz kurulum
yaparak henüz test etmedim. Donanım farklılıklarını kontrol edin.

2. USB HAZIRLAMA

Windows'ta USB hazırlamak için kullandığım proje:
https://github.com/nullmoth/1401

Önce projenin Windows yönergeleriyle USB'yi oluşturun. USB'deki EFI'yi
yedekleyin. Bu depodaki EFI/OC klasörünü USB'nin EFI klasörüne kopyalayın
ve mevcut OC klasörünü değiştirin. 1401'in oluşturduğu EFI/BOOT ve
EFI/Microsoft klasörlerini koruyun. Bütün EFI klasörünü körlemesine değiştirmeyin.

EFI/OC/config.plist > PlatformInfo > Generic bölümüne kendi SMBIOS
bilgilerinizi girin. Paylaşım kopyasında SystemSerialNumber, MLB ve SystemUUID
alanlarını boş bıraktım; ROM'u sıfırladım. Bu alanları kendinize göre doldurun.
SMBIOS aracı: https://github.com/corpnewt/GenSMBIOS

Verilerinizi ve çalışan EFI'nizi yedekledikten sonra macOS kurulumuna geçin.

3. KURULUM SONRASI DOSYALAR NEREDE DURACAK?

Kurulum-Sonrasi-Uygulamalar klasörünü USB'nin erişilebilir veri bölümünde
saklayabilirsiniz. Uygulamaları EFI/OC/Kexts içine koymayın.
Kurucu çalıştırılacaksa ilgili uygulama klasörünü yazılabilir bir yere kopyalayın.
macOS yükleyicisini, 1401 uygulamasını ve NVIDIA sürücü paketini depoya eklemedim.

4. NVIDIA SÜRÜCÜSÜ

Ben sürücü kurulumunu NullMoth 1401 üzerinden yaptım.
Uygulamayı ve yönergeleri resmî projelerden edinin:
https://github.com/nullmoth/1401
https://github.com/nullmoth/nvidia-macos-driver

Uygulamanın seçtiği OpenCore/EFI konumunu kontrol edin. Kurulumda kullanılan
önyükleme USB'sini gereken işlem ve yeniden başlatmalar boyunca bağlı tutun.
Yeniden başlattıktan sonra görüntüyü ve sürücü durumunu kontrol edin.

5. KAMERA UYGULAMASI

Konum: Kurulum-Sonrasi-Uygulamalar/02-Kamera
Uygulama: G870 Kamera Prototip.app
Kaynaklar: aynı klasörde Kaynak-Kodlari/0.4

Uygulamayı Applications / Uygulamalar klasörüne kopyalayıp oradan açın.
Kamerayı kullanan uygulamaları kapatın. Önce CMIO güncelle düğmesine basın;
işlem tamamlandıktan sonra Kamerayı eşle düğmesini kullanın.
macOS uzantı izni veya yeniden başlatma isterse tamamlayın.
Photo Booth'ta G870 Quanta — Canlı kamerasını seçip hareketli görüntüyü kontrol edin.
Uygulamayı kapattıktan ve yeniden başlattıktan sonra da tekrar deneyin.

Ben Quanta USB 0408:209d kamera modülünde kullandım. Farklı modülleri test etmedim.
Uygulama içindeki CMIO ve DriverKit uzantıları birlikte gerekli; EFI tek başına
kamerayı etkinleştirmiyor. Uzantıları kaldırmak için Eşleşmeyi kaldır düğmesini
kullanın. Ad-hoc imza temiz sistemde kabul edilmeyebilir; temiz kurulum testi
henüz tamamlanmadı.

6. G870 CONTROL CENTER KURULUMU

Konum: Kurulum-Sonrasi-Uygulamalar/03-Control-Center
Kurucu: Yerel-Kurulum.command
Kaynaklar: aynı klasörde Kaynak-Kodlari

Klasörün tamamını yazılabilir bir yere, örneğin masaüstüne kopyalayın.
Açık Control Center varsa Command+Q ile kapatın.
Kurucu /usr/bin/python3 yolunu kullanıyor; Python 3 ön koşulunu kontrol edin.
Yerel-Kurulum.command dosyasını açın ve yönetici parolasını Terminal'e girin.
Kurulum tamamlandıktan sonra yeniden başlatın; uygulama, fan/mod ve RGB
kontrollerini deneyin.

Kurucu macOS'un bulunduğu dahili diskin EFI bölümünü hedefliyor.
EFI'yi yedekliyor; G870Bridge.kext, SSDT-G870-RGB.aml ve bunların config.plist
kayıtlarını güncelliyor. USB'deki ayrı EFI'ye otomatik uygulanmıyor.
Uygulama /Applications/G870ControlCenter.app konumuna kuruluyor.
Donanım yardımcısını ve kullanıcı oturumunda başlatma servislerini de kuruyor.

EFI yedekleri:
/Library/Application Support/G870ControlCenter/Backups

Kurulum sonucu aynı klasörde yerel-kurulum-sonucu.txt dosyasına yazılıyor.
Hata durumunda bu dosyayı inceleyin; paylaşmadan önce kişisel yolları ve
tanımlayıcı bilgileri kontrol edin.

Dahili EFI hedefi sizin önyükleme düzeninize uygun değilse kurucuyu çalıştırmayın.
Çalışan USB kurtarma kopyanızı, yeniden başlatma ve USB'siz açılış testleri
tamamlanana kadar saklayın. Paketteki kurucunun temiz bilgisayarda yönetici
kurulumu ve USB'siz açılışı henüz ayrıca doğrulanmadı.

7. TEST VE UYUMLULUK SINIRLARI

Burada kendi çalışan sistemimde kullandığım EFI ve uygulamaları paylaşıyorum.
Bu durum, aynı paketle başka cihazda temiz kurulumun doğrulandığı anlamına gelmiyor.
Kamera modülü, Wi-Fi kartı, BIOS ve G870 donanım varyantı sonucu etkileyebilir.
Kişisel seri numaramı, MLB/UUID bilgilerimi ve gerçek ROM değerimi paylaşım
config.plist dosyasına koymadım.

8. ÜÇÜNCÜ TARAF PROJELER

OpenCore, kext'ler ve NullMoth projeleri kendi geliştiricilerine ait.
Kaynak depolarını THIRD-PARTY.md dosyasında belirttim. Her bileşenin kendi
lisans ve bildirim koşulları geçerli; yalnızca link vermek bütün lisans
yükümlülüklerinin tamamlandığı anlamına gelmiyor.

Kamera ve Control Center kaynaklarını ilgili Kaynak-Kodlari klasörlerine ekledim.
Kaynakların bulunması bütün pakete tek bir yeniden dağıtım lisansı vermiyor.
Apple bu donanımda macOS kurulumunu desteklemiyor.
