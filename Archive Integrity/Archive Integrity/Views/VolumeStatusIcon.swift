import SwiftUI

/// Small circular status glyph shared by the menu bar row list and the Settings sidebar.
struct VolumeStatusIcon: View {
    let status: MonitoredVolume.Status
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: size, height: size)
            Image(systemName: symbolName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var symbolName: String {
        switch status {
        case .clean:   return "checkmark"
        case .failed:  return "exclamationmark"
        case .unknown: return "externaldrive"
        }
    }

    private var tint: Color {
        switch status {
        case .clean:   return .green
        case .failed:  return .red
        case .unknown: return .secondary
        }
    }
}
