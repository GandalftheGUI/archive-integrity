import Foundation

extension String {
    /// Replaces raw ASCII control characters with visible Unicode "control picture" glyphs.
    ///
    /// Some real files legitimately contain control characters in their names — notably
    /// macOS's hidden `Icon\r` custom-folder-icon marker, whose name ends in a literal
    /// carriage return. Printed as-is, that `\r` resets a terminal's cursor to the start
    /// of the line, making the following line appear to overwrite it. This makes such
    /// characters visible instead of letting them corrupt terminal/log rendering.
    public func sanitizedForDisplay() -> String {
        var result = ""
        result.reserveCapacity(count)
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x00...0x1F:
                result.unicodeScalars.append(UnicodeScalar(0x2400 + scalar.value)!)
            case 0x7F:
                result.unicodeScalars.append(UnicodeScalar(0x2421)!)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
