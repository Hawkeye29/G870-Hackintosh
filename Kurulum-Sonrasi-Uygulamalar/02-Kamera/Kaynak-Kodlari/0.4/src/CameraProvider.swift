import Foundation
import CoreMediaIO
import CoreVideo
import CoreGraphics
import ImageIO
import IOKit.audio
import os.log

final class TestLog {
    static let shared = TestLog()
    private let lock = NSLock()
    private var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.local.g870.camera")?.appendingPathComponent("capture-0.4.txt")
    }
    func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let line = "\(ISO8601DateFormatter().string(from:Date()))  \(message.trimmingCharacters(in:.whitespacesAndNewlines))\n"
        os_log("%{public}@", log: .default, type: .default, line)
        guard let url = url, let data = line.data(using:.utf8) else { return }
        do {
            if !FileManager.default.fileExists(atPath:url.path) { try Data().write(to:url) }
            let h = try FileHandle(forWritingTo:url); defer { try? h.close() }
            let size = try h.seekToEnd()
            if size > 512_000 { try h.truncate(atOffset:0); try h.seek(toOffset:0) }
            try h.write(contentsOf:data)
        } catch { os_log("G870 log write failed: %{public}@", type:.error,error.localizedDescription) }
    }
}
private let captureLogger: @convention(c) (UnsafePointer<CChar>) -> Void = { TestLog.shared.write(String(cString:$0)) }

final class LiveSession {
    weak var device:CameraDevice?
    let generation:UInt64
    private let lock = NSLock()
    private var cancelled = false
    private var running = false
    init(device:CameraDevice,generation:UInt64){self.device=device;self.generation=generation}
    func begin()->Bool {lock.lock();defer{lock.unlock()};guard !cancelled else{return false};g870_prepare();running=true;return true}
    func end(){lock.lock();running=false;lock.unlock()}
    func cancel(){lock.lock();cancelled=true;if running{g870_cancel()};lock.unlock()}
}
private let liveFrameHandler: @convention(c) (CFData,UnsafeMutableRawPointer)->Void = { data,context in
    let session = Unmanaged<LiveSession>.fromOpaque(context).takeUnretainedValue()
    session.device?.receive(data,session:session)
}

final class CameraDevice: NSObject, CMIOExtensionDeviceSource {
    var device: CMIOExtensionDevice!
    var video: CameraStream!
    let state = DispatchQueue(label:"local.g870.camera.state")
    let worker = DispatchQueue(label:"local.g870.camera.usb",qos:.userInitiated)
    var clients = 0
    var generation: UInt64 = 0
    let decodeQueue = DispatchQueue(label:"local.g870.camera.decode",qos:.userInitiated)
    let decodeSlots = DispatchSemaphore(value:2)
    var session:LiveSession?
    var sentFrames:UInt64 = 0
    var decodeErrors:UInt64 = 0
    var lastStats:Double = 0
    var format: CMVideoFormatDescription!
    override init() {
        super.init()
        device = CMIOExtensionDevice(localizedName:"G870 Quanta — Canlı",deviceID:UUID(uuidString:"C3610715-FA7D-4845-A126-7927657A8B3D")!,legacyDeviceID:nil,source:self)
        let status = CMVideoFormatDescriptionCreate(allocator:kCFAllocatorDefault,codecType:kCVPixelFormatType_32BGRA,width:640,height:480,extensions:nil,formatDescriptionOut:&format)
        precondition(status == noErr)
        video = CameraStream(device:device,format:format)
        do { try device.addStream(video.stream) } catch { fatalError("addStream: \(error)") }
    }
    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType,.deviceModel] }
    func deviceProperties(forProperties properties:Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let p = CMIOExtensionDeviceProperties(dictionary:[:])
        if properties.contains(.deviceTransportType) { p.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { p.model = "Quanta 0408:209d / UVC48 continuous video experiment" }
        return p
    }
    func setDeviceProperties(_ properties:CMIOExtensionDeviceProperties) throws {}
    func start() {
        state.async {
            self.clients += 1
            guard self.clients == 1 else { return }
            self.generation += 1
            let session = LiveSession(device:self,generation:self.generation)
            self.session = session;self.sentFrames = 0;self.decodeErrors = 0;self.lastStats = CFAbsoluteTimeGetCurrent()
            TestLog.shared.write("LIVE START: continuous USB stream; new real frames only.")
            self.worker.async {
                guard session.begin() else { return }
                let code = g870_stream(captureLogger,liveFrameHandler,Unmanaged.passUnretained(session).toOpaque())
                session.end()
                self.state.async {
                    if self.generation == session.generation { TestLog.shared.write("LIVE USB worker ended: result=\(code). Close and reopen camera to retry if needed.") }
                }
            }
        }
    }
    func stop() {
        state.async {
            guard self.clients > 0 else { return }
            self.clients -= 1
            if self.clients == 0 {
                self.generation += 1;self.session?.cancel();self.session = nil
                TestLog.shared.write("LIVE STOP: last client closed; draining USB reads and closing camera.")
            }
        }
    }
    func receive(_ data:CFData,session:LiveSession) {
        guard decodeSlots.wait(timeout:.now()) == .success else { return }
        let timestamp = CMClockGetTime(CMClockGetHostTimeClock())
        decodeQueue.async {
            // The closure retains the CFData after the C callback returns.
            var pixel:CVPixelBuffer?
            autoreleasepool {
                do { pixel = try self.decode(data) }
                catch { pixel = nil }
            }
            let decoded = pixel
            self.state.async {
                defer {self.decodeSlots.signal()}
                guard self.generation == session.generation && self.clients > 0 else {return}
                guard let decoded = decoded else {
                    self.decodeErrors += 1
                    if self.decodeErrors == 1 {TestLog.shared.write("LIVE decode: invalid JPEG skipped.")};return
                }
                self.send(decoded,timestamp:timestamp)
            }
        }
    }
    func decode(_ data:CFData) throws -> CVPixelBuffer {
        guard let src = CGImageSourceCreateWithData(data,nil), let image = CGImageSourceCreateImageAtIndex(src,0,nil),image.width == 640,image.height == 480 else {
            throw NSError(domain:"G870",code:1,userInfo:[NSLocalizedDescriptionKey:"Expected a decoded real 640x480 JPEG"])
        }
        var pixel: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey:[:] as [String:Any]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault,640,480,kCVPixelFormatType_32BGRA,attrs,&pixel) == kCVReturnSuccess, let pixel = pixel else { throw NSError(domain:"G870",code:2) }
        CVPixelBufferLockBaseAddress(pixel,[])
        let bitmap = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let context = CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:640,height:480,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:bitmap)
        context?.draw(image,in:CGRect(x:0,y:0,width:640,height:480))
        CVPixelBufferUnlockBaseAddress(pixel,[])
        guard context != nil else { throw NSError(domain:"G870",code:3) }
        return pixel
    }
    func send(_ pixel:CVPixelBuffer,timestamp:CMTime) {
        var timing = CMSampleTimingInfo(duration:CMTime(value:1,timescale:30),presentationTimeStamp:timestamp,decodeTimeStamp:.invalid)
        var sample:CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,dataReady:true,makeDataReadyCallback:nil,refcon:nil,formatDescription:format,sampleTiming:&timing,sampleBufferOut:&sample)
        if status == noErr,let sample = sample {
            video.stream.send(sample,discontinuity:[],hostTimeInNanoseconds:UInt64(timestamp.seconds*1_000_000_000))
            sentFrames += 1
            if sentFrames == 1 {TestLog.shared.write("LIVE FIRST FRAME SENT: real 640x480 image; continuing capture.")}
            let now = CFAbsoluteTimeGetCurrent()
            if now-lastStats >= 5 {TestLog.shared.write("LIVE CMIO sent=\(sentFrames) decode-errors=\(decodeErrors)");lastStats = now}
        } else {TestLog.shared.write("LIVE sample creation failed: \(status)")}
    }

}

final class CameraStream: NSObject, CMIOExtensionStreamSource {
    var stream:CMIOExtensionStream!
    let device:CMIOExtensionDevice
    let formats:[CMIOExtensionStreamFormat]
    init(device:CMIOExtensionDevice,format:CMVideoFormatDescription) {
        self.device = device
        self.formats = [CMIOExtensionStreamFormat(formatDescription:format,maxFrameDuration:CMTime(value:1,timescale:30),minFrameDuration:CMTime(value:1,timescale:30),validFrameDurations:nil)]
        super.init()
        stream = CMIOExtensionStream(localizedName:"G870 Live Video",streamID:UUID(uuidString:"D4AFA933-8EE1-48E4-978A-AD14D99B25EC")!,direction:.source,clockType:.hostTime,source:self)
    }
    var activeFormatIndex:Int = 0
    var availableProperties:Set<CMIOExtensionProperty> { [.streamActiveFormatIndex,.streamFrameDuration] }
    func streamProperties(forProperties properties:Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary:[:])
        if properties.contains(.streamActiveFormatIndex) { p.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { p.frameDuration = CMTime(value:1,timescale:30) }
        return p
    }
    func setStreamProperties(_ properties:CMIOExtensionStreamProperties) throws {
        if let i = properties.activeFormatIndex, i != 0 { throw NSError(domain:"G870",code:4) }
    }
    func authorizedToStartStream(for client:CMIOExtensionClient) -> Bool { true }
    func startStream() throws { (device.source as? CameraDevice)?.start() }
    func stopStream() throws { (device.source as? CameraDevice)?.stop() }
}

final class QuantaProvider: NSObject, CMIOExtensionProviderSource {
    var provider:CMIOExtensionProvider!
    var camera:CameraDevice!
    override init() {
        super.init()
        provider = CMIOExtensionProvider(source:self,clientQueue:nil)
        camera = CameraDevice()
        do { try provider.addDevice(camera.device) } catch { fatalError("addDevice: \(error)") }
        TestLog.shared.write("PROVIDER 0.4 STARTED. Camera listed; hardware capture only on stream start. UVC48 live stream; hardware duration/fps not yet verified.")
    }
    var availableProperties:Set<CMIOExtensionProperty> { [.providerManufacturer] }
    func providerProperties(forProperties properties:Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let p = CMIOExtensionProviderProperties(dictionary:[:]);if properties.contains(.providerManufacturer) {p.manufacturer = "G870 local camera experiment"};return p
    }
    func setProviderProperties(_ properties:CMIOExtensionProviderProperties) throws {}
    func connect(to client:CMIOExtensionClient) throws {}
    func disconnect(from client:CMIOExtensionClient) {}
}
