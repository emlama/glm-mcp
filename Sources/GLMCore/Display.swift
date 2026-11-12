import Foundation

/// Human/speech-friendly value with an imperial equivalent, e.g. `"2.271 m (89.4 in)"`.
public func displayString(value: Double, unit: MeasureUnit) -> String {
    switch unit {
    case .m: String(format: "%.3f m (%.1f in)", value, value * 39.370_079)
    case .m2: String(format: "%.3f m² (%.1f ft²)", value, value * 10.763_910)
    case .m3: String(format: "%.3f m³ (%.1f ft³)", value, value * 35.314_667)
    }
}
