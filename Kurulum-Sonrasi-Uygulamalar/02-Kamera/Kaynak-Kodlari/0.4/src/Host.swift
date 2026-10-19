import AppKit
import SystemExtensions

final class Host: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    let cmioID = "local.g870.camera.ProviderProbe"
    let driverID = "local.g870.camera.MatchProbe"
    var window: NSWindow!
    let report = NSTextView()
    var busy = false
    var buttons: [NSButton] = []
    var pendingRemoval: String?
    var providerReady = false
    var isActivation = false
    func append(_ value: String) {
        report.string += "\(ISO8601DateFormatter().string(from: Date()))  \(value)\n"
        report.scrollToEndOfDocument(nil)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 550), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "G870 — Canlı kamera denemesi 0.4"
        let root = window.contentView!
        let explanation = NSTextField(wrappingLabelWithString: "Bu deney Quanta kameradan CANLI GÖRÜNTÜ almayı dener. Yeni kareleri sürekli aktarır; donanım testi henüz yapılmadı. Kurulum fiziksel kameranın sürücü eşleşmesini değiştirir. EFI, Wi-Fi ve parlaklık ayarları korunur.")
        explanation.frame = NSRect(x: 20, y: 465, width: 780, height: 65)
        explanation.autoresizingMask = [.width,.minYMargin]
        root.addSubview(explanation)
        for (index,title,selector) in [(0,"1. CMIO güncelle",#selector(cmio)),(1,"2. Kamerayı eşle",#selector(driver)),(2,"Eşleşmeyi kaldır",#selector(remove)),(3,"Yakalama raporu",#selector(captureReport)),(4,"Raporu kaydet",#selector(save))] {
            let b = NSButton(title: title, target: self, action: selector)
            b.frame = NSRect(x: 20 + index*156, y: 415, width: 150, height: 35)
            b.autoresizingMask = [.minYMargin]
            root.addSubview(b); buttons.append(b)
        }
        let scroll = NSScrollView(frame: NSRect(x:20,y:20,width:780,height:380))
        scroll.autoresizingMask = [.width,.height]; scroll.hasVerticalScroller = true
        report.isEditable = false; report.isSelectable = true
        report.font = NSFont.monospacedSystemFont(ofSize: 12, weight:.regular)
        report.autoresizingMask = [.width]; report.isVerticallyResizable = true
        scroll.documentView = report; root.addSubview(scroll)
        append("Sürüm 0.4.0; hedef Quanta 0408:209d; canlı görüntü denemesi. Sonuç donanımda henüz doğrulanmadı.")
        append("Ad hoc imzalı geliştirme derlemesi. Sistem aktivasyonu reddedebilir. Güvenlik ayarı otomatik değiştirilmez.")
        append("Kamera uygulamalarını kapatın. Önce CMIO güncelle tamamlanmalı; sonra Kamerayı eşle. Gerekirse yeniden başlatın. Photo Booth içinden G870 Quanta — Canlı seçin; ardından Yakalama raporu düğmesini kullanın.")
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func setBusy(_ value: Bool) { busy = value; for b in buttons.prefix(3) { b.isEnabled = !value } }
    func submit(_ id: String, activate: Bool) {
        guard !busy else { return }
        if activate && !Bundle.main.bundleURL.path.hasPrefix("/Applications/") {
            append("DURDU: Uygulamayı /Applications klasörüne kopyalayıp oradan açın."); return
        }
        setBusy(true)
        isActivation = activate
        append("İstek: \(activate ? "etkinleştir" : "kaldır") \(id)")
        let request = activate ? OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier:id,queue:.main) : OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier:id,queue:.main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    @objc func cmio() { submit(cmioID, activate:true) }
    @objc func driver() {
        guard providerReady else { append("Önce CMIO güncelle isteği tamamlanmalı. Kamera eşleşmesi değiştirilmedi.");return }
        submit(driverID, activate:true)
    }
    @objc func remove() { pendingRemoval = cmioID; submit(driverID, activate:false) }
    @objc func captureReport() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:"group.local.g870.camera") else { append("Paylaşılan yakalama raporu klasörüne erişilemedi.");return }
        let url = base.appendingPathComponent("capture-0.4.txt")
        do { let data = try Data(contentsOf:url);guard data.count <= 600_000 else { append("Yakalama raporu beklenenden büyük.");return };append("--- UZANTI YAKALAMA KAYDI ---\n" + (String(data:data,encoding:.utf8) ?? "Rapor okunamadı")) }
        catch { append("Henüz yakalama kaydı okunamadı: \(error.localizedDescription). Kamera listede mi ve seçildi mi kontrol edin.") }
    }
    @objc func save() {
        captureReport()
        let panel = NSSavePanel(); panel.nameFieldStringValue = "g870-canli-0.4.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try report.string.write(to:url,atomically:true,encoding:.utf8) }
            catch { append("Rapor yazılamadı: \(error.localizedDescription)") }
        }
    }
    func finish(continueRemoval: Bool = false) {
        setBusy(false)
        if let next = pendingRemoval { pendingRemoval = nil;if continueRemoval {submit(next,activate:false)} else {append("Kamera eşleşmesinin kaldırıldığı kesinleşmedi; CMIO otomatik kaldırılmadı. Sonuca göre yeniden başlatıp Eşleşmeyi kaldır düğmesini tekrar kullanın.")} }
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        append("macOS kullanıcı onayı bekliyor: \(request.identifier). Sistem Ayarları'ndaki isteği kontrol edin.")
    }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        append("SONUÇ \(request.identifier): \(result == .completed ? "tamamlandı" : "yeniden başlatma gerekiyor"). Bu sonuç görüntü aktarımını kanıtlamaz.")
        if request.identifier == cmioID { providerReady = isActivation && result == .completed }
        finish(continueRemoval: !isActivation && request.identifier == driverID && result == .completed)
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let n = error as NSError
        append("HATA \(request.identifier): domain=\(n.domain) code=\(n.code) \(n.localizedDescription)")
        if let underlying = n.userInfo[NSUnderlyingErrorKey] as? NSError { append("Alt hata: \(underlying.domain) \(underlying.code) \(underlying.localizedDescription)") }
        // If the matcher is not installed, removing the CMIO provider is safe.
        finish(continueRemoval: !isActivation && request.identifier == driverID && n.domain == OSSystemExtensionErrorDomain && n.code == OSSystemExtensionError.extensionNotFound.rawValue)
    }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        guard existing.bundleIdentifier == request.identifier && replacement.bundleIdentifier == request.identifier && replacement.bundleVersion == "0.4.0" && ["0.1.0","0.2.0","0.3.0","0.4.0"].contains(existing.bundleVersion) else {
            append("Beklenmeyen uzantı/sürüm; değiştirme reddedildi.");return .cancel
        }
        append("Aynı yerel uzantı güncelleniyor: \(existing.bundleVersion) → \(replacement.bundleVersion)")
        return .replace
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let host = Host()
app.delegate = host
app.setActivationPolicy(.regular)
app.run()
