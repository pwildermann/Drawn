import PencilKit
import SwiftUI

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var controller: PencilCanvasController

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.tool = PKInkingTool(.monoline, color: .black, width: 3)
        canvasView.drawing = drawing
        controller.attach(canvasView)
        return canvasView
    }

    /// Intentionally empty. The canvas and `NSUndoManager` own the drawing; the binding is
    /// updated from `canvasViewDrawingDidChange` only, matching system Notes/Freeform behaviour
    /// and avoiding stale SwiftUI state overwriting live strokes.
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, controller: self.controller)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding private var drawing: PKDrawing
        weak var controller: PencilCanvasController?

        init(drawing: Binding<PKDrawing>, controller: PencilCanvasController) {
            _drawing = drawing
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // PKCanvasViewDelegate can fire while SwiftUI is still in a view update; writing
            // the binding synchronously triggers “Modifying state during view update”.
            let newDrawing = canvasView.drawing
            DispatchQueue.main.async { [weak self] in
                self?.drawing = newDrawing
                self?.controller?.refreshUndoState()
            }
        }
    }
}
