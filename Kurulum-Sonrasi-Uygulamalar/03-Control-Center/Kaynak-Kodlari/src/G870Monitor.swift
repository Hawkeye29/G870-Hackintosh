import SwiftUI
import AppKit

struct Status: Decodable {
    let cpu_temperature_raw: Double
    let gpu_temperature_raw: Double
    let cpu_fan_raw: Int
    let gpu_fan_raw: Int
}
struct FirmwareMode: Decodable { let firmware_mode_raw: Int }
struct Snapshot: Decodable {
    let session_id: String?
    let timestamp: Double
    let quiet_supported: Bool?
    let quiet_active: Bool?
    let quiet_duty: Int?
    let quiet_reason: Int?
    let rgb_supported: Bool?
    let rgb_zones_supported: Bool?
    let curve_all_modes: Bool?
    let curve_supported: Bool?
    let curve_point_count: Int?
    let curve_hex: String?
    let controls: Bool?
    let override: Bool?
    let restoration_pending: Bool?
    let action_result: UInt32?
    let action: String?
    let action_sequence: Int?
    let status: Status
    let mode: FirmwareMode
}
struct Sample: Identifiable {
    let id = UUID()
    let cpu: Double
    let gpu: Double
}
@MainActor final class Monitor: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var samples: [Sample] = []
    @Published var fresh = false
    @Published var pending = false
    @Published var feedback = ""
    @Published var rgbEffect = ""
    private var rgbColor = NSColor.blue
    private var rgbBrightness = 2
    private var rgbInterval: Double = 4
    private var rgbStep = 0
    private var nextRGB = Date.distantPast
    private var pendingRGB = false
    @Published var profileMode = 2
    @Published var profileRevision = 0
    @Published var restoringProfile = false
    @Published var rememberMode = true {
        didSet { defaults.set(rememberMode,forKey:"rememberMode") }
    }
    private let defaults: UserDefaults
    private var profiles: [String:ModeProfile] = [:]
    private var startupHandled = false
    private var observedSession = false
    private var lastSessionID: String?
    private var commands: [String] = []
    private var applyingProfile: ModeProfile?
    private var applyingMode: Int?
    private var pendingSequence = 0
    private var lastTimestamp: Double = 0
    private let file: URL
    private let request: URL
    init(defaults: UserDefaults = .standard, directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/G870ControlCenter")) {
        self.defaults = defaults
        file = directory.appendingPathComponent("telemetry-live.json")
        request = directory.appendingPathComponent("control-request.txt")
        rememberMode = defaults.object(forKey:"rememberMode") as? Bool ?? true
        if let data = defaults.data(forKey:"modeProfilesV1"), let saved = try? JSONDecoder().decode([String:ModeProfile].self,from:data) {
            profiles = saved.filter { ["0","1","2"].contains($0.key) && $0.value.valid }
        }
    }
    func refresh() {
        if let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(Snapshot.self, from: data) {
            if observedSession && lastSessionID != value.session_id {
                pending = false; pendingRGB = false; rgbEffect = ""
                commands.removeAll(); applyingProfile = nil; applyingMode = nil; restoringProfile = false
                startupHandled = false
            }
            observedSession = true; lastSessionID = value.session_id
            snapshot = value
            if pending && (value.action_sequence ?? 0) > pendingSequence {
                pending = false
                if value.action_result != 0 {
                    if pendingRGB { rgbEffect = "" }
                    commands.removeAll(); applyingProfile = nil; applyingMode = nil; restoringProfile = false
                }
                pendingRGB = false
                feedback = value.action_result == 0 ? "Komut BIOS’a iletildi." : "Komut başarısız (\(value.action_result ?? 0))."
            }
            fresh = Date().timeIntervalSince1970 - value.timestamp < 12
            if value.timestamp != lastTimestamp {
                samples.append(Sample(cpu: value.status.cpu_temperature_raw, gpu: value.status.gpu_temperature_raw))
                if samples.count > 60 { samples.removeFirst(samples.count - 60) }
                lastTimestamp = value.timestamp
            }
        } else { fresh = false }
        if !fresh || snapshot?.restoration_pending == true {
            rgbEffect = ""
            if restoringProfile { commands.removeAll(); applyingProfile = nil; applyingMode = nil; restoringProfile = false }
        }
        if fresh && snapshot?.controls == true && !startupHandled {
            startupHandled = true
            profileMode = min(max(snapshot?.mode.firmware_mode_raw ?? 2,0),2)
            profileRevision += 1
            if rememberMode, let last = defaults.object(forKey:"lastProfileMode") as? Int, (0...2).contains(last) {
                selectMode(last)
            }
        }
        advanceProfile()
        tickRGB()
    }
    private var canDispatch: Bool { fresh && snapshot?.controls == true && snapshot?.restoration_pending != true && !pending }
    var canControl: Bool { canDispatch && !restoringProfile }
    var profileName: String { ["Yüksek performans","Oyun","Ofis"][profileMode] }
    var currentProfile: ModeProfile { profiles[String(profileMode)] ?? ModeProfile() }
    private func saveProfile(_ profile: ModeProfile) {
        guard profile.valid else { return }
        profiles[String(profileMode)] = profile
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data,forKey:"modeProfilesV1") }
        profileRevision += 1
    }
    func selectMode(_ mode: Int) {
        guard canControl, (0...2).contains(mode) else { return }
        let profile = profiles[String(mode)] ?? ModeProfile()
        if profile.fan == "curve" && mode != 2 && snapshot?.curve_all_modes != true {
            feedback = "Bu modda fan eğrisi için USB’deki 0.7 sürücüsüyle açılış gerekiyor."
            return
        }
        if profile.fan == "curve" && snapshot?.curve_point_count != 8 {
            feedback = "Sürücü sekiz noktalı eğriyi desteklemiyor."; return
        }
        if profile.rgbEnabled && snapshot?.rgb_supported != true {
            feedback = "Profil uygulanamadı: RGB desteği doğrulanmadı."; return
        }
        if profile.rgbEnabled && profile.rgbZones != nil && snapshot?.rgb_zones_supported != true {
            feedback = "Bölge kontrolü için USB’deki 0.8 sürücüsü ve RGB tablosuyla açılış gerekiyor."; return
        }
        rgbEffect = ""
        profileMode = mode; profileRevision += 1
        applyingProfile = profile; applyingMode = mode; restoringProfile = true
        commands = ["fan auto","mode \(mode)",profile.fan == "curve" ? "curve " + FanCurvePoint.hex(profile.curve) : "fan " + profile.fan]
        if profile.rgbEnabled {
            if let zones = profile.rgbZones {
                for (index,color) in zones.enumerated() {
                    var zone = profile; zone.red = color.red; zone.green = color.green; zone.blue = color.blue
                    commands.append(String(format:"rgbzone %d %08x",[5,4,3][index],packedRGB(zone,mode:1)))
                }
            } else {
                let value = packedRGB(profile,mode:Int(profile.rgbMode) ?? 1)
                commands.append(String(format:"rgb %08x",value))
            }
        }
        advanceProfile()
    }
    private func packedRGB(_ profile:ModeProfile, mode:Int) -> UInt32 {
        UInt32(mode) << 28 | UInt32(profile.brightness) << 24 | UInt32((profile.red*255).rounded()) << 16 | UInt32((profile.green*255).rounded()) << 8 | UInt32((profile.blue*255).rounded())
    }
    private func advanceProfile() {
        guard restoringProfile, canDispatch else { return }
        if !commands.isEmpty {
            let command = commands.removeFirst()
            pendingRGB = (command.hasPrefix("rgb ") || command.hasPrefix("rgbzone "))
            submit(command)
            return
        }
        guard let profile = applyingProfile, let mode = applyingMode else { return }
        applyingProfile = nil; applyingMode = nil; restoringProfile = false
        defaults.set(mode,forKey:"lastProfileMode")
        feedback = "\(profileName) profili uygulandı."
        if profile.rgbEnabled && profile.rgbZones == nil && Int(profile.rgbMode) == nil {
            startRGBEffect(profile.rgbMode,color:NSColor(srgbRed:profile.red,green:profile.green,blue:profile.blue,alpha:1),brightness:profile.brightness,interval:profile.interval)
        }
    }
    func saveRGB(mode:String,color:NSColor,brightness:Int,interval:Double) {
        guard canControl, let rgb = color.usingColorSpace(.deviceRGB) else { return }
        var profile = currentProfile
        profile.rgbZones = nil
        profile.rgbEnabled = true; profile.rgbMode = mode
        profile.red = rgb.redComponent; profile.green = rgb.greenComponent; profile.blue = rgb.blueComponent
        profile.brightness = brightness; profile.interval = interval
        guard profile.valid else { return }
        saveProfile(profile); selectMode(profileMode)
    }
    func saveRGBZones(colors:[NSColor],brightness:Int) {
        guard canControl, snapshot?.rgb_zones_supported == true, colors.count == 3 else { return }
        let zones = colors.compactMap { color -> RGBZoneColor? in
            guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
            return RGBZoneColor(red:rgb.redComponent,green:rgb.greenComponent,blue:rgb.blueComponent)
        }
        guard zones.count == 3 else { return }
        var profile = currentProfile
        profile.rgbEnabled = true; profile.rgbMode = "1"; profile.rgbZones = zones; profile.brightness = brightness
        guard profile.valid else { return }
        saveProfile(profile); selectMode(profileMode)
    }
    func send(_ command: String) {
        guard canControl else { return }
        if command.hasPrefix("mode "), let mode = Int(command.dropFirst(5)) { selectMode(mode); return }
        var profile = currentProfile
        switch command {
        case "fan auto", "quiet off": profile.fan = "auto"
        case "fan max": profile.fan = "max"
        case "quiet on": profile.fan = "curve"
        default: return
        }
        saveProfile(profile); selectMode(profileMode)
    }
    func sendCurve(_ points:[FanCurvePoint]) {
        guard canControl, snapshot?.curve_point_count == 8, FanCurvePoint.valid(points) else { return }
        var profile = currentProfile; profile.fan = "curve"; profile.curve = points
        saveProfile(profile); selectMode(profileMode)
    }
    func sendRGB(_ value:UInt32) {
        guard canControl, snapshot?.rgb_supported == true else { return }
        pendingRGB = true
        submit(String(format:"rgb %08x",value))
    }
    func stopRGBEffect() { rgbEffect = "" }
    func startRGBEffect(_ effect: String, color: NSColor, brightness: Int, interval: Double) {
        guard canControl, snapshot?.rgb_supported == true else { return }
        rgbEffect = effect
        rgbColor = color.usingColorSpace(.deviceRGB) ?? .blue
        rgbBrightness = min(max(brightness,0),2)
        rgbInterval = min(max(interval,4),12)
        rgbStep = 0
        nextRGB = .distantPast
        tickRGB()
    }
    private func tickRGB() {
        guard !rgbEffect.isEmpty, canControl, Date() >= nextRGB else { return }
        var color = rgbColor
        switch rgbEffect {
        case "rainbow": color = NSColor(hue:Double(rgbStep % 12)/12,saturation:1,brightness:1,alpha:1)
        case "pastel": color = NSColor(hue:Double(rgbStep % 12)/12,saturation:0.35,brightness:1,alpha:1)
        case "police": color = rgbStep % 2 == 0 ? .red : .blue
        case "candle": color = NSColor(srgbRed:1,green:Double.random(in:0.18...0.48),blue:0.01,alpha:1)
        case "pulse":
            let levels: [Double] = [0.15,0.35,0.65,1,0.65,0.35]
            let level = levels[rgbStep % levels.count]
            color = NSColor(srgbRed:rgbColor.redComponent*level,green:rgbColor.greenComponent*level,blue:rgbColor.blueComponent*level,alpha:1)
        case "thermal":
            guard let status = snapshot?.status else { return }
            let temperature = max(status.cpu_temperature_raw,status.gpu_temperature_raw)
            let fraction = min(max((temperature-40)/40,0),1)
            color = NSColor(hue:(1-fraction)*0.66,saturation:1,brightness:1,alpha:1)
        default: rgbEffect = ""; return
        }
        let rgb = color.usingColorSpace(.deviceRGB) ?? rgbColor
        func channel(_ v: CGFloat) -> UInt32 { UInt32(min(max(v*255,0),255).rounded()) }
        sendRGB(1 << 28 | UInt32(rgbBrightness) << 24 | channel(rgb.redComponent) << 16 | channel(rgb.greenComponent) << 8 | channel(rgb.blueComponent))
        rgbStep = (rgbStep + 1) % 120
        nextRGB = Date().addingTimeInterval(rgbInterval)
    }
    private func submit(_ command:String) {
        do {
            try (command + "\n").write(to: request, atomically: true, encoding: .utf8)
            pendingSequence = snapshot?.action_sequence ?? 0
            pending = true
            feedback = "Komut bekleniyor…"
        } catch {
            pendingRGB = false; rgbEffect = ""; commands.removeAll()
            applyingProfile = nil; applyingMode = nil; restoringProfile = false
            feedback = "Komut dosyası yazılamadı: \(error.localizedDescription)"
        }
    }
    var mode: String {
        switch snapshot?.mode.firmware_mode_raw {
        case 0: return "Yüksek performans"
        case 1: return "Oyun"
        case 2: return "Ofis"
        default: return "Bilinmiyor"
        }
    }
}
struct SensorCard: View {
    let title: String
    let temperature: Double?
    let rpm: Int?
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: title == "CPU" ? "cpu" : "square.stack.3d.up").font(.headline).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(temperature.map { String(format: "%.0f", $0) } ?? "—").font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                Text("°C").font(.title2).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(temperature ?? 0, 0), 100), total: 100).tint(color)
            HStack {
                Label("Fan", systemImage: "fanblades")
                Spacer()
                Text(rpm.map { "\($0) RPM" } ?? "— RPM").monospacedDigit()
            }.font(.callout).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
         .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}
struct TemperatureGraph: View {
    let samples: [Sample]
    private func line(_ values: [Double], in size: CGSize) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: Double(index) / Double(max(values.count - 1, 1)) * size.width, y: (1 - min(max(value, 0), 100) / 100) * size.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Sıcaklık geçmişi").font(.headline)
                Spacer()
                Text("CPU").foregroundStyle(.cyan)
                Text("GPU").foregroundStyle(.orange)
                Text("Son 60 ölçüm").foregroundStyle(.secondary)
            }.font(.caption)
            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<5) { row in
                        Path { path in
                            let y = CGFloat(row) / 4 * geometry.size.height
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }.stroke(.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    line(samples.map(\.cpu), in: geometry.size).stroke(.cyan, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    line(samples.map(\.gpu), in: geometry.size).stroke(.orange, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    if samples.count < 2 { Text("Ölçümler bekleniyor…").foregroundStyle(.secondary) }
                }
            }.frame(height: 115)
            HStack { Text("0°C"); Spacer(); Text("Ölçek: 0–100°C") }.font(.caption2).foregroundStyle(.secondary)
        }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}
struct ContentView: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("EXCALIBUR").font(.caption.weight(.semibold)).tracking(4).foregroundStyle(.secondary)
                    Text("Control Center").font(.system(size: 30, weight: .semibold))
                    Text("G870 · 1362-BV70X-C").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(monitor.fresh ? .green : .orange).frame(width: 7, height: 7)
                    Text(monitor.fresh ? "Canlı bağlantı" : "Veri akışı bekleniyor")
                }.font(.caption).padding(10).background(.background, in: Capsule())
            }
            HStack(spacing: 18) {
                SensorCard(title: "CPU", temperature: monitor.snapshot?.status.cpu_temperature_raw, rpm: monitor.snapshot?.status.cpu_fan_raw, color: .cyan)
                SensorCard(title: "GPU", temperature: monitor.snapshot?.status.gpu_temperature_raw, rpm: monitor.snapshot?.status.gpu_fan_raw, color: .orange)
            }.opacity(monitor.fresh ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Performans modu").font(.headline)
                    Spacer()
                    Button("Ofis") { monitor.send("mode 2") }.tint(monitor.snapshot?.mode.firmware_mode_raw == 2 ? .cyan : .gray)
                    Button("Oyun") { monitor.send("mode 1") }.tint(monitor.snapshot?.mode.firmware_mode_raw == 1 ? .cyan : .gray)
                    Button("Yüksek performans") { monitor.send("mode 0") }.tint(monitor.snapshot?.mode.firmware_mode_raw == 0 ? .cyan : .gray)
                }.buttonStyle(.bordered).disabled(!monitor.canControl)
                Text("Düzenlenen profil: \(monitor.profileName). Fan ve RGB için Uygula düğmeleri bu moda kaydeder.").font(.caption).foregroundStyle(.secondary)
                Toggle("Açılışta son kullandığım moda ve ayarlarına dön",isOn:$monitor.rememberMode).font(.callout)
                if monitor.restoringProfile { ProgressView("Modun ayarları uygulanıyor…").controlSize(.small) }
                Divider()
                HStack {
                    Text("Fan kontrolü").font(.headline)
                    Spacer()
                    Text(monitor.snapshot?.quiet_active == true ? "Sessiz · %\(monitor.snapshot?.quiet_duty ?? 0) istek" : monitor.snapshot?.override == true ? "Tam hız isteği etkin" : "BIOS yönetimi").font(.caption).foregroundStyle(.secondary)
                    Button("Otomatik") { monitor.send("fan auto") }
                    Button("Tam hız") { monitor.send("fan max") }
                }.buttonStyle(.bordered).disabled(!monitor.canControl)
                HStack {
                    Label("Kayıtlı fan eğrisi", systemImage: "leaf")
                    Spacer()
                    Button("Eğriyi aç") { monitor.send("quiet on") }
                    Button("Kapat") { monitor.send("quiet off") }
                }.buttonStyle(.bordered).disabled(!monitor.canControl || monitor.snapshot?.quiet_supported != true)
                if monitor.snapshot?.quiet_supported != true {
                    Text("Sessiz profil için USB’deki 0.3 sürücüsüyle yeniden başlatılmalı.").font(.caption).foregroundStyle(.secondary)
                }
                if let reason = monitor.snapshot?.quiet_reason, reason >= 2 {
                    Text(reason == 2 ? "Sıcaklık sınırı: kontrol BIOS’a bırakıldı." : reason == 4 ? "Düşük fan devri algılandı: kontrol BIOS’a bırakıldı." : "Sessiz profil durdu; kontrol BIOS’a bırakıldı.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Oturum kapanınca fanlar BIOS yönetimine, performans modu önceki ayarına döndürülür.").font(.caption).foregroundStyle(.secondary)
                if monitor.snapshot?.controls != true {
                    Text("Kontroller için USB’deki 0.2 sürücüsüyle yeniden başlatılmalı.").font(.caption).foregroundStyle(.orange)
                }
                if monitor.snapshot?.restoration_pending == true {
                    Text("BIOS ayarlarına dönüş tamamlanamadı; sürücü yeniden deniyor.").font(.caption).foregroundStyle(.orange)
                }
                if !monitor.feedback.isEmpty { Text(monitor.feedback).font(.caption).foregroundStyle(.secondary) }
            }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
            CurveEditor(monitor: monitor)
            RGBEditor(monitor: monitor)
            TemperatureGraph(samples: monitor.samples)
            HStack {
                Label("BIOS modu: \(monitor.mode)", systemImage: "speedometer")
                Spacer()
                Text("Kontrol sürümü · 0.10").foregroundStyle(.secondary)
            }.font(.callout)
            if !monitor.fresh {
                Text("Canlı ölçüm için Control-Center-Baslat.command dosyasını çalıştır. Görünen değerler son alınan ölçümlerdir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28) }.frame(minWidth: 780, minHeight: 620)
         .background(Color(nsColor: .windowBackgroundColor))

    }
}
struct MenuPanel: View {
    @ObservedObject var monitor: Monitor
    let openWindow: () -> Void
    let quit: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Label("Excalibur",systemImage:"fanblades").font(.headline)
                Spacer()
                Circle().fill(monitor.fresh ? Color.green : Color.orange).frame(width:7,height:7)
            }
            if let status = monitor.snapshot?.status {
                HStack {
                    Text(String(format:"CPU %.0f°C",status.cpu_temperature_raw))
                    Spacer()
                    Text(String(format:"GPU %.0f°C",status.gpu_temperature_raw))
                }.monospacedDigit()
                Text("Fan: \(status.cpu_fan_raw) / \(status.gpu_fan_raw) RPM").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Ofis") { monitor.selectMode(2) }
                Button("Oyun") { monitor.selectMode(1) }
                Button("Performans") { monitor.selectMode(0) }
            }.buttonStyle(.bordered).disabled(!monitor.canControl)
            Text(monitor.fresh ? "Mod: \(monitor.profileName)" : "Donanım bağlantısı bekleniyor…").font(.caption).foregroundStyle(.secondary)
            if monitor.restoringProfile { ProgressView("Ayarlar uygulanıyor…").controlSize(.small) }
            Divider()
            Button("Tam pencereyi aç",action:openWindow).buttonStyle(.borderedProminent).frame(maxWidth:.infinity)
            HStack {
                Text("Pencere kapalıyken ayarlar çalışır.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Çıkış",action:quit).buttonStyle(.borderless)
            }
        }.padding(18).frame(width:320)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let monitor = Monitor()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var fullWindow: NSWindow?
    private var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let application = NSMenuItem(); menu.addItem(application)
        let applicationMenu = NSMenu()
        let open = NSMenuItem(title:"Tam pencereyi aç",action:#selector(openFullWindow),keyEquivalent:"1");open.target = self
        applicationMenu.addItem(open)
        applicationMenu.addItem(NSMenuItem(title:"Pencereyi kapat",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"))
        applicationMenu.addItem(.separator())
        let quit = NSMenuItem(title:"Control Center’dan çık",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");quit.target = NSApp
        applicationMenu.addItem(quit);application.submenu = applicationMenu;NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName:"fanblades",accessibilityDescription:"Excalibur Control Center")
            button.image?.isTemplate = true
            button.target = self; button.action = #selector(togglePanel)
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:MenuPanel(monitor:monitor,openWindow:{ [weak self] in self?.showWindow() },quit:{ NSApp.terminate(nil) }))
        monitor.refresh()
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.monitor.refresh()
                self.statusItem.button?.toolTip = self.monitor.fresh ? "Excalibur · \(self.monitor.profileName)" : "Excalibur · bağlantı bekleniyor"
            }
        }
        if let timer = timer { RunLoop.main.add(timer,forMode:.common) }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/"),
              FileManager.default.fileExists(atPath:"/Library/LaunchDaemons/local.g870.hardware.plist") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath:"/bin/launchctl")
        process.arguments = ["kickstart","gui/\(getuid())/local.g870.control-center"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try? process.run()
    }
    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY); NSApp.activate(ignoringOtherApps:true) }
    }
    @objc private func openFullWindow() { showWindow() }
    func showWindow() {
        popover.performClose(nil)
        if fullWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:830,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title = "Excalibur Control Center"
            window.contentView = NSHostingView(rootView:ContentView(monitor:monitor))
            window.minSize = NSSize(width:800,height:650)
            window.isReleasedWhenClosed = false; window.delegate = self; window.center()
            fullWindow = window
        }
        fullWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}
@main struct G870MonitorApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
