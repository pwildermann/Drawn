import PencilKit
import SwiftUI

struct EditTimerView: View {
    @Binding var isPresented: Bool
    let timer: DrawnTimer

    @Environment(TimerStore.self) private var timerStore

    @State private var duration: TimerDuration
    @State private var drawing: PKDrawing
    @StateObject private var pencilCanvas = PencilCanvasController()

    init(isPresented: Binding<Bool>, timer: DrawnTimer) {
        self._isPresented = isPresented
        self.timer = timer
        self._pencilCanvas = StateObject(wrappedValue: PencilCanvasController())
        self._duration = State(initialValue: timer.duration)
        let initialDrawing: PKDrawing
        if let data = timer.doodleData, let d = try? PKDrawing(data: data) {
            initialDrawing = d
        } else {
            initialDrawing = PKDrawing()
        }
        self._drawing = State(initialValue: initialDrawing)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xCCCCCC))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)

            VStack(spacing: 20) {
                TimePickerWheelView(duration: $duration)

                VStack(alignment: .leading, spacing: 12) {
                    Text({
                        var s = AttributedString("Describe")
                        s.strikethroughStyle = .single
                        return s + AttributedString(" Doodle your Timer")
                    }())
                    .font(.system(size: 16, weight: .semibold))
                    .kerning(-0.32)
                    .foregroundStyle(Color(hex: 0x8C8C8C))

                    ZStack {
                        Color.white
                        DotGridView()
                        PencilCanvasView(drawing: $drawing, controller: pencilCanvas)
                    }
                    .frame(minHeight: 337, maxHeight: 337)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: 0xD9D9D9), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 12) {
                        roundIconButton(systemName: "trash", enabled: !drawing.strokes.isEmpty, action: { pencilCanvas.clear() })

                        UndoRedoPill(
                            canUndo: pencilCanvas.canUndo,
                            canRedo: pencilCanvas.canRedo,
                            onUndo: { pencilCanvas.undo() },
                            onRedo: { pencilCanvas.redo() }
                        )
                    }
                }

                Button { saveChanges() } label: {
                    Text("Save changes")
                        .font(.system(size: 16, weight: .semibold))
                        .kerning(-0.32)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: 0x0D0D0D))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func roundIconButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            iconImage(systemName: systemName, enabled: enabled)
                .frame(width: 24, height: 24)
                .padding(14)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .disabled(!enabled)
        .buttonStyle(PressScaleButtonStyle())
    }

    @ViewBuilder
    private func iconImage(systemName: String, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(enabled ? Color(hex: 0x0D0D0D) : Color(hex: 0xD9D9D9))
    }

    private func saveChanges() {
        timerStore.updateTimer(
            id: timer.id,
            duration: duration,
            doodleData: drawing.dataRepresentation()
        )
        withAnimation(BottomSheetMotion.dismiss) {
            isPresented = false
        }
    }
}

private struct DotGridView: View {
    private let inset:   CGFloat = 19
    private let spacing: CGFloat = 20
    private let radius:  CGFloat = 1.0
    private let color    = Color(hex: 0xD9D9D9)

    var body: some View {
        Canvas { ctx, size in
            var y = inset
            while y <= size.height - radius {
                var x = inset
                while x <= size.width - radius {
                    let rect = CGRect(x: x - radius, y: y - radius,
                                     width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
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

#Preview {
    EditTimerView(
        isPresented: .constant(true),
        timer: DrawnTimer(name: "Preview", duration: TimerDuration(hours: 0, minutes: 5, seconds: 0))
    )
    .environment(TimerStore())
}
