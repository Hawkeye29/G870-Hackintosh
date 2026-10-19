import Foundation

struct RGBZoneColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var valid: Bool { [red,green,blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}

struct ModeProfile: Codable, Equatable {
    var fan = "auto"
    var curve = FanCurvePoint.defaults
    var rgbEnabled = false
    var rgbMode = "1"
    var red: Double = 0
    var green: Double = 0
    var blue: Double = 1
    var brightness = 2
    var interval: Double = 4
    var rgbZones: [RGBZoneColor]?
    static let effects = ["1","3","6","7","rainbow","pastel","police","candle","pulse","thermal"]
    var valid: Bool {
        (rgbZones == nil || (rgbZones!.count == 3 && rgbZones!.allSatisfy { $0.valid })) &&
        ["auto","max","curve"].contains(fan) && FanCurvePoint.valid(curve) && Self.effects.contains(rgbMode) &&
        [red,green,blue].allSatisfy { $0.isFinite && (0...1).contains($0) } && (0...2).contains(brightness) && interval.isFinite && (4...12).contains(interval)
    }
}
