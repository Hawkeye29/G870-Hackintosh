# Yerel kurulum — uygulama 0.9

Önce Control Center'ı Command+Q ile kapatın. Yerel-Kurulum.command dosyasını Terminal'de çalıştırın; macOS yönetici parolanızı yalnızca bu kurulum için girin. Parola ekranda görünmez. Kurulum tamamlandığında uygulama açılır. Sonrasında uygulamayı Applications klasöründen açabilirsiniz; kullanıcı oturumuna girişte de otomatik başlar. Eski Terminal başlatıcısını kullanmanız gerekmez.

Bu paket hazırlanmış ve test edilmiştir; yönetici kurulumu bu sohbet ortamından çalıştırılamadığı için henüz sisteme kurulmamıştır. Kurucu sonucu aynı klasörde yerel-kurulum-sonucu.txt dosyasına kaydedilir. Hata verirse bu dosyayı paylaşın.

Kurucu çalışan macOS'un APFS fiziksel diskini bulur ve yalnız dahili diskteki tek EFI bölümünü hedefler. EFI/OC/config.plist ve OpenCore.efi bulunmazsa durur. EFI'nin tamamını /Library/Application Support/G870ControlCenter/Backups/tarih-saat/EFI altında yedekler. Ardından yalnız G870Bridge.kext, SSDT-G870-RGB.aml ve bu iki dosyanın OpenCore kayıtlarını ekler/günceller. Diğer OpenCore ayarlarını ve Microsoft klasörünü korur. Diski biçimlendirmez ve firmware önyükleme sırasını değiştirmez. EFI dosyası kopyalama/yapılandırma hatasında ilgili dosyaları yedekten geri getirir.

Uygulama /Applications/G870ControlCenter.app konumuna; donanım yardımcısı ve oturum betiği root sahipli /Library/Application Support/G870ControlCenter konumuna kurulur. /Library/LaunchDaemons/local.g870.hardware.plist donanım yardımcısını talep üzerine açar. Mevcut kullanıcı LaunchAgent'ı, Terminal açan eski kayıt yerine sessiz kullanıcı oturumunu başlatır. Sudoers değiştirilmez; parola saklanmaz.

Root yardımcı /var/run/g870-control.sock adlı yerel Unix soketini kullanır. Soket yalnız kurulum yapan kullanıcıya açıktır; yardımcı ayrıca bağlantının kullanıcı kimliğini kontrol eder. Kullanıcı bağlantısı da sunucunun root olduğunu doğrular. Yardımcı yalnız sınırlı mode/fan/curve/rgb/rgbzone/sample/quit protokolünü işler; kabuk komutu veya kullanıcı tarafından verilen program çalıştırmaz. Uygulama kapanınca bağlantı kapanır; veri akışı kesilirse 10 saniyelik bağlantı zaman aşımı ve sürücü kiralama koruması devreye girer.

Profil tercihleri aynı uygulama kimliğinde korunur. Canlı telemetri ve komut dosyaları artık ~/Library/Application Support/G870ControlCenter altında tutulur; uygulama klasörüne yazılmaz. Uygulamayı klasörden tek başına açmak, kurulu kullanıcı oturumunu yeniden başlatır.

İlk başarılı kurulumdan sonra bilgisayarı kapatıp USB olmadan dahili OpenCore üzerinden açılışı deneyin. USB kurtarma yolunu test tamamlanana kadar saklayın. Dahili firmware menüsü Windows'u seçerse mevcut dahili OpenCore/macOS önyükleme seçeneğini kullanın; bu kurucu boot sırasını değiştirmez.

Doğrulama: uygulama derlemesi ve imzası, sınırlı komut ayrıştırıcısı, profil kalıcılığı/sıralaması, Unix kullanıcı denetimi, çift yönlü bağlantı/EOF ve EFI birleştirme/yedek/geri dönüş testleri geçti. LaunchDaemon'ın gerçek yönetici kurulumu, oturum açılışı ve USB'siz önyükleme kullanıcı ortamında henüz doğrulanmadı. Root kurulumu gerektiği için bunlar kurucunun çalıştırılmasından sonra kontrol edilmelidir.
