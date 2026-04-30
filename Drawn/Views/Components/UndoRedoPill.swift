import SwiftUI

/// White pill with undo + redo. Press feedback scales the **entire** pill, not each icon.
struct UndoRedoPill: View {
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void

    @State private var undoPressed = false
    @State private var redoPressed = false

    private var duoPressed: Bool { undoPressed || redoPressed }

    var body: some View {
        HStack(spacing: 32) {
            PressTrackingButton(
                playsHaptic: true,
                useUIKitPressAnimation: false,
                isEnabled: canUndo,
                hugsContent: true,
                action: onUndo,
                onPressingChanged: { p in
                    withAnimation(
                        p ? .easeOut(duration: 0.1) : .easeOut(duration: 0.32)
                    ) {
                        undoPressed = p
                    }
                }
            ) {
                icon(systemName: "arrow.uturn.backward", enabled: canUndo)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            PressTrackingButton(
                playsHaptic: true,
                useUIKitPressAnimation: false,
                isEnabled: canRedo,
                hugsContent: true,
                action: onRedo,
                onPressingChanged: { p in
                    withAnimation(
                        p ? .easeOut(duration: 0.1) : .easeOut(duration: 0.32)
                    ) {
                        redoPressed = p
                    }
                }
            ) {
                icon(systemName: "arrow.uturn.forward", enabled: canRedo)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .scaleEffect(duoPressed ? 0.9 : 1.0)
        .brightness(duoPressed ? -0.04 : 0)
    }

    @ViewBuilder
    private func icon(systemName: String, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(enabled ? Color(hex: 0x0D0D0D) : Color(hex: 0xD9D9D9))
    }
}

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
