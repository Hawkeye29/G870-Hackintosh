import Foundation
import AppKit

@main struct ProfileTests {
 @MainActor static func main() throws {
    let suite = "local.g870.profile-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName:suite)!
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:dir) }
    let request = dir.appendingPathComponent("control-request.txt")
    func requested() -> String { try! String(contentsOf:request,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines) }
    func sample(_ seq:Int,_ result:Int=0,allModes:Bool=true,mode:Int=2,stale:Bool=false,zones:Bool=true,session:String="test-a") throws {
        let data: [String:Any] = ["session_id":session,"timestamp":Date().timeIntervalSince1970-(stale ? 30:0),"controls":true,"restoration_pending":false,"action_sequence":seq,"action_result":result,"rgb_supported":true,"rgb_zones_supported":zones,"curve_point_count":8,"curve_all_modes":allModes,"status":["cpu_temperature_raw":50,"gpu_temperature_raw":45,"cpu_fan_raw":1200,"gpu_fan_raw":1200],"mode":["firmware_mode_raw":mode]]
        try JSONSerialization.data(withJSONObject:data).write(to:dir.appendingPathComponent("telemetry-live.json"))
    }
    let monitor = Monitor(defaults:defaults,directory:dir)
    try sample(0); monitor.refresh()
    assert(!FileManager.default.fileExists(atPath:request.path)) // first run doesn't change hardware
    monitor.selectMode(1)
    assert(requested()=="fan auto")
    monitor.refresh(); assert(requested()=="fan auto") // wait for acknowledgement
    try sample(1);monitor.refresh();assert(requested()=="mode 1")
    try sample(2,mode:1);monitor.refresh();assert(requested()=="fan auto")
    assert(defaults.object(forKey:"lastProfileMode")==nil)
    try sample(3,mode:1);monitor.refresh()
    assert(!monitor.restoringProfile && defaults.integer(forKey:"lastProfileMode")==1)
    monitor.sendCurve(FanCurvePoint.defaults)
    try sample(4,mode:1);monitor.refresh();assert(requested()=="mode 1")
    try sample(5,mode:1);monitor.refresh();assert(requested().hasPrefix("curve "))
    try sample(6,mode:1);monitor.refresh();assert(monitor.currentProfile.fan=="curve")
    monitor.selectMode(2)
    try sample(7,9);monitor.refresh();assert(!monitor.restoringProfile)
    assert(defaults.integer(forKey:"lastProfileMode")==1) // failed switch not persisted
    monitor.selectMode(1)
    try sample(8,allModes:false,mode:1);monitor.refresh()
    try sample(9,allModes:false,mode:1);monitor.refresh()
    try sample(10,allModes:false,mode:1);monitor.refresh()
    let oldDriver = Monitor(defaults:defaults,directory:dir)
    try? FileManager.default.removeItem(at:request)
    oldDriver.refresh()
    assert(!FileManager.default.fileExists(atPath:request.path)) // no wrong-mode curve on old driver
    assert(oldDriver.feedback.contains("0.7"))
    try sample(10,mode:1)
    let restored = Monitor(defaults:defaults,directory:dir)
    restored.refresh();assert(requested()=="fan auto")
    try sample(11,mode:1);restored.refresh();assert(requested()=="mode 1")
    try sample(12,mode:1);restored.refresh();assert(requested().hasPrefix("curve "))
    try sample(13,mode:1);restored.refresh()
    restored.saveRGB(mode:"pastel",color:.red,brightness:1,interval:6)
    try sample(14,mode:1);restored.refresh()
    try sample(15,mode:1);restored.refresh()
    try sample(16,mode:1);restored.refresh();assert(requested().hasPrefix("rgb "))
    assert(restored.rgbEffect.isEmpty) // don't animate until profile RGB ack
    try sample(17,mode:1);restored.refresh();assert(restored.rgbEffect=="pastel")
    try sample(18,mode:1,stale:true);restored.refresh();assert(restored.rgbEffect.isEmpty)
    let saved = try JSONDecoder().decode([String:ModeProfile].self,from:defaults.data(forKey:"modeProfilesV1")!)
    assert(saved["1"]?.rgbMode=="pastel" && saved["1"]?.fan=="curve")
    assert(saved["2"]==nil) // mode settings stay independent
    defaults.set(false,forKey:"rememberMode")
    try? FileManager.default.removeItem(at:request)
    let disabled = Monitor(defaults:defaults,directory:dir)
    try sample(19,mode:1);disabled.refresh();assert(!FileManager.default.fileExists(atPath:request.path))
    let zoned = Monitor(defaults:defaults,directory:dir)
    try sample(20,mode:1);zoned.refresh()
    zoned.saveRGBZones(colors:[.red,.green,.blue],brightness:2)
    assert(requested()=="fan auto")
    try sample(21,mode:1);zoned.refresh();assert(requested()=="mode 1")
    try sample(22,mode:1);zoned.refresh();assert(requested().hasPrefix("curve "))
    try sample(23,mode:1);zoned.refresh();assert(requested()=="rgbzone 5 12ff0000")
    try sample(24,mode:1);zoned.refresh();assert(requested()=="rgbzone 4 1200ff00")
    try sample(25,mode:1);zoned.refresh();assert(requested()=="rgbzone 3 120000ff")
    try sample(26,mode:1);zoned.refresh();assert(!zoned.restoringProfile && zoned.rgbEffect.isEmpty)
    let zoneProfiles = try JSONDecoder().decode([String:ModeProfile].self,from:defaults.data(forKey:"modeProfilesV1")!)
    assert(zoneProfiles["1"]?.rgbZones?.count==3 && zoneProfiles["1"]?.rgbZones?[0].red==1)
    try? FileManager.default.removeItem(at:request)
    try sample(27,mode:1,zones:false);zoned.refresh();zoned.selectMode(1)
    assert(!FileManager.default.fileExists(atPath:request.path) && zoned.feedback.contains("0.8"))
    defaults.set(true,forKey:"rememberMode")
    let reconnected = Monitor(defaults:defaults,directory:dir)
    try sample(27,mode:1);reconnected.refresh();assert(reconnected.pending)
    try? FileManager.default.removeItem(at:request)
    try sample(0,mode:1,session:"test-b");reconnected.refresh()
    assert(requested()=="fan auto" && reconnected.pending)
    try sample(1,mode:1,session:"test-b");reconnected.refresh();assert(requested()=="mode 1")
    var invalid = ModeProfile();invalid.rgbZones = [RGBZoneColor(red:1,green:0,blue:0)]
    assert(!invalid.valid)
    print("PASS: independent profiles, ack sequencing, failed switch, persistence, startup restore, old-driver guard, software RGB lifecycle, restore toggle.")
 }
}
