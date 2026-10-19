import SwiftUI
struct FanCurvePoint: Codable, Equatable {
    var temperature: Int
    var duty: Int
    static let defaults = [Self(temperature:45,duty:35),Self(temperature:50,duty:35),Self(temperature:55,duty:38),Self(temperature:60,duty:42),Self(temperature:65,duty:47),Self(temperature:70,duty:53),Self(temperature:75,duty:60),Self(temperature:79,duty:70)]
    static func valid(_ points: [Self]) -> Bool {
        guard points.count == 8 else { return false }
        for i in points.indices {
            guard (20...79).contains(points[i].temperature), (35...100).contains(points[i].duty) else { return false }
            if i > 0 && (points[i].temperature < points[i-1].temperature + 3 || points[i].duty < points[i-1].duty) { return false }
        }
        return true
    }
    static func hex(_ points:[Self]) -> String {
        var parts: [UInt64] = [0,0]
        for (i,p) in points.enumerated() { parts[i/4] |= UInt64(p.temperature) << (16*(i%4)); parts[i/4] |= UInt64(p.duty) << (16*(i%4)+8) }
        return String(format:"%016llx%016llx",parts[0],parts[1])
    }
}
struct CurveEditor: View {
    @ObservedObject var monitor: Monitor
    @State private var points = FanCurvePoint.defaults
    private var valid: Bool { FanCurvePoint.valid(points) }
    private func point(_ p:FanCurvePoint,_ size:CGSize) -> CGPoint {
        CGPoint(x:CGFloat(p.temperature-20)/60*size.width,y:(1-CGFloat(p.duty)/100)*size.height)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Label("Fan eğrisi",systemImage:"slider.horizontal.3").font(.headline)
                Spacer()
                Button("Başlangıç değerleri") { points=FanCurvePoint.defaults }
            }
            Text("CPU/GPU’dan sıcak olanı iki fanı birlikte yönetir. Eğri düzenlenen moda kaydedilir.").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment:.topLeading) {
                    ForEach(0..<5) { row in
                        Path { path in
                            let y=CGFloat(row)/4*geometry.size.height
                            path.move(to:CGPoint(x:0,y:y));path.addLine(to:CGPoint(x:geometry.size.width,y:y))
                        }.stroke(.secondary.opacity(0.15),style:StrokeStyle(lineWidth:1,dash:[4,4]))
                    }
                    Path { path in
                        guard let first=points.first,let last=points.last else { return }
                        path.move(to:CGPoint(x:0,y:point(first,geometry.size).y))
                        for p in points { path.addLine(to:point(p,geometry.size)) }
                        path.addLine(to:CGPoint(x:geometry.size.width,y:point(last,geometry.size).y))
                    }.stroke(valid ? Color.green : Color.orange,style:StrokeStyle(lineWidth:2,lineJoin:.round))
                    ForEach(points.indices,id:\.self) { i in
                        Circle().fill(valid ? Color.green : Color.orange).frame(width:8,height:8).position(point(points[i],geometry.size))
                    }
                }
            }.frame(height:115)
            HStack { Text("20°C");Spacer();Text("Fan isteği · %0–100");Spacer();Text("80°C") }.font(.caption2).foregroundStyle(.secondary)
            ForEach(points.indices,id:\.self) { i in
                HStack(spacing:16) {
                    Text("\(i+1)").foregroundStyle(.secondary).frame(width:18)
                    Stepper("\(points[i].temperature)°C",value:$points[i].temperature,in:20...79).frame(width:150)
                    Slider(value:Binding(get:{Double(points[i].duty)},set:{points[i].duty=Int($0.rounded())}),in:35...100,step:1)
                        .accessibilityLabel("\(i+1). noktanın fan yüzdesi")
                    Text("%\(points[i].duty)").monospacedDigit().frame(width:42,alignment:.trailing)
                }
            }
            if !valid { Text("Sıcaklıklar en az 3°C aralıkla artmalı; fan yüzdesi sıcaklıkla azalmamalı.").font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("CPU veya GPU 80°C sınırında kontrol BIOS’a döner.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Kaydet ve uygula") { monitor.sendCurve(points) }
                    .buttonStyle(.borderedProminent).disabled(!valid || !monitor.canControl || monitor.snapshot?.curve_point_count != 8)
            }
            if monitor.snapshot?.curve_point_count != 8 {
                Text("Eğri kontrolü için USB’deki 0.5 sürücüsüyle yeniden başlatılmalı.").font(.caption).foregroundStyle(.secondary)
            } else if valid && monitor.snapshot?.curve_hex == FanCurvePoint.hex(points) && monitor.snapshot?.quiet_active == true {
                Label("Bu eğri kullanılıyor",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
        }.padding(20).background(.background,in:RoundedRectangle(cornerRadius:20))
         .onAppear { points = monitor.currentProfile.curve }
         .onChange(of:monitor.profileRevision) { _,_ in points = monitor.currentProfile.curve }
    }
}

struct RGBEditor: View {
    @ObservedObject var monitor: Monitor
    @State private var color: Color = .blue
    @State private var regional = false
    @State private var zoneColors: [Color] = [.red,.green,.blue]
    @State private var mode = "1"
    @State private var interval = 4.0
    private var software: Bool { Int(mode) == nil }
    @State private var brightness = 2
    private func loadProfile() {
        let profile = monitor.currentProfile
        regional = profile.rgbZones != nil
        zoneColors = profile.rgbZones?.map { Color(nsColor:NSColor(srgbRed:$0.red,green:$0.green,blue:$0.blue,alpha:1)) } ?? [.red,.green,.blue]
        mode = profile.rgbMode; brightness = profile.brightness; interval = profile.interval
        color = Color(nsColor:NSColor(srgbRed:profile.red,green:profile.green,blue:profile.blue,alpha:1))
    }
    private func apply() {
        if regional {
            monitor.saveRGBZones(colors:zoneColors.map { NSColor($0) },brightness:brightness)
            return
        }
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
        monitor.saveRGB(mode:mode,color:rgb,brightness:brightness,interval:interval)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Label("Klavye RGB · \(monitor.profileName)",systemImage:"keyboard").font(.headline)
            Toggle("Bölgeleri ayrı renklendir",isOn:$regional)
            if regional {
                HStack(spacing:20) {
                    ForEach(0..<3) { i in
                        VStack {
                            RoundedRectangle(cornerRadius:8).fill(zoneColors[i]).frame(height:35)
                            ColorPicker("Bölge \(i+1)",selection:$zoneColors[i],supportsOpacity:false)
                        }
                    }
                }
                Text("Üç bölgeye ayrı sabit renk uygulanır; parlaklık ortaktır. Fiziksel bölge desteği ilk denemede doğrulanmalı.").font(.caption).foregroundStyle(.secondary)
                if monitor.snapshot?.rgb_zones_supported != true {
                    Text("Bölge kontrolü için USB’deki 0.8 sürücüsü ve RGB tablosuyla yeniden başlatılmalı.").font(.caption).foregroundStyle(.orange)
                }
            } else {
            HStack {
                ColorPicker("Renk",selection:$color,supportsOpacity:false).frame(width:160)
                Picker("Efekt",selection:$mode) {
                    Text("Sabit").tag("1")
                    Text("Nefes alma").tag("3")
                    Text("Renk döngüsü").tag("6")
                    Text("Ambilight").tag("7")
                    Text("Gökkuşağı geçişi · uygulama").tag("rainbow")
                    Text("Pastel geçiş · uygulama").tag("pastel")
                    Text("Polis ışığı · uygulama").tag("police")
                    Text("Mum · uygulama").tag("candle")
                    Text("Nabız · uygulama").tag("pulse")
                    Text("Sıcaklığa göre · uygulama").tag("thermal")
                }.frame(maxWidth:240)
                Spacer()
            }
            }
            HStack {
                Picker("Parlaklık",selection:$brightness) {
                    Text("Kapalı").tag(0)
                    Text("Düşük").tag(1)
                    Text("Yüksek").tag(2)
                }.pickerStyle(.segmented).frame(maxWidth:400)
                Spacer()
                Button("Uygula") { apply() }.buttonStyle(.borderedProminent).disabled(!monitor.canControl || (regional && monitor.snapshot?.rgb_zones_supported != true))
            }
            if software && !regional {
                HStack {
                    Text("Geçiş aralığı")
                    Slider(value:$interval,in:4...12,step:1)
                    Text("\(Int(interval)) sn").monospacedDigit().frame(width:48)
                }
                Text("Uygulama efektleri tüm klavyeye uygulanır. Geçiş aralığı komut yanıtına göre uzayabilir. Sıcaklık rengi: 40°C mavi → 80°C kırmızı.").font(.caption).foregroundStyle(.secondary)
            }
            if !monitor.rgbEffect.isEmpty {
                HStack {
                    Label("Uygulama efekti çalışıyor",systemImage:"sparkles").foregroundStyle(.green)
                    Spacer()
                    Button("Efekti durdur") { monitor.stopRGBEffect() }
                }.font(.caption)
            }
            Text("Uygulama efektleri kapatıldığında veya bağlantı kesildiğinde durur; son renk kalır. Yerleşik efektler klavyede devam eder.").font(.caption).foregroundStyle(.secondary)
            if monitor.snapshot?.rgb_supported != true {
                Text("RGB desteği henüz doğrulanmadı. Güncel başlatıcıyla açıp bağlantıyı kontrol et.").font(.caption).foregroundStyle(.secondary)
            }
            if !monitor.feedback.isEmpty { Text(monitor.feedback).font(.caption).foregroundStyle(.secondary) }
        }.padding(20).background(.background,in:RoundedRectangle(cornerRadius:20))
         .onAppear { loadProfile() }
         .onChange(of:monitor.profileRevision) { _,_ in loadProfile() }
         .disabled(!monitor.fresh || monitor.snapshot?.controls != true || monitor.snapshot?.rgb_supported != true)
    }
}
