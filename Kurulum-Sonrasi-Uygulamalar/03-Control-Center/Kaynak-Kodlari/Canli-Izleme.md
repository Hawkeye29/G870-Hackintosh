# Excalibur G870 — macOS canlı izleme

Control-Center-Baslat.command dosyasına çift tıklayın. Yönetici parolanız Terminal'de istenir. Yerel uygulama kullanıcı yetkisiyle çalışır; yalnızca g870ctl tanılama çağrıları sudo ile yapılır. Terminal penceresi açık kalmalıdır. Uygulama kapatılınca veri okuma sona erer. Başlatıcı çalışırken aynı uygulamayı ikinci kez başlatmayın.

Bu sürüm CPU/GPU sıcaklıklarını, iki fanın RPM değerlerini, BIOS modunu ve son 60 ölçümün sıcaklık grafiğini gösterir. Üç saniyede bir sorgu yapılır. On iki saniye boyunca güncel veri gelmezse bağlantı durumu uyarıya dönüşür, son değerler soluk gösterilir. Her sorgu mevcut firmware arayüzünün özgün okuma işlemini kullanır; status sorgusu OMCC=1 el sıkışmasını içerir. Fan hızı, RGB ve performans modu ayarı bu sürümde sunulmaz. Grafik geçmişi yalnızca uygulama oturumu boyunca bellekte tutulur.

## Donanımda doğrulananlar
Kullanıcının donanim-okuma-sonucu.txt raporunda üç sorgu da başarılı: CPU 51°C, GPU 43°C, CPU fanı 3406 RPM, GPU fanı 3011 RPM, BIOS modu 2. Bunlar rapor anındaki ölçümlerdir. Birimler ve 0=yüksek performans, 1=oyun, 2=ofis eşlemesi özgün uygulamanın GetHardwareInformation, ShowCPUInformation ve Set_power_plan_immediately metotlarından doğrulandı. BIOS modu etiketi macOS güç planı değiştirmez.

Sürücü USB üzerinden açılışta GWMI'ye bağlandı. Mode/capabilities/status sorguları yönetici yetkisiyle gerçek donanımda başarılı. Arayüz SwiftUI ile x86_64 macOS 15.5+ için derlendi. Başlatıcı kabuk sözdizimi doğrulandı. Yeni GUI'nin canlı oturumu kullanıcı tarafından henüz doğrulanmadı.

Sonraki aşama: arayüzün canlı ölçümlerini doğrulayıp ardından fan, performans ve RGB kontrollerini geliştirmek. Şarj sınırı desteği hâlâ kanıtlanmış değildir.
