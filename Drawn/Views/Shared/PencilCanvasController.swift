import Combine
import PencilKit
import SwiftUI

/// Drives the **native** PencilKit / `NSUndoManager` stack (same path as Notes, Freeform, etc.).
/// This avoids a custom `PKDrawing` snapshot stack and view replacement, so undo/redo
/// doesn’t flash.
@MainActor
final class PencilCanvasController: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private weak var canvasView: PKCanvasView?

    /// Call from `PencilCanvasView.makeUIView` after the canvas is configured.
    func attach(_ canvas: PKCanvasView) {
        canvasView = canvas
        // Defer first responder until after the sheet settles — `becomeFirstResponder` during
        // presentation competes with keyboard/sheet animation and feels janky.
        DispatchQueue.main.async { [weak self] in
            _ = self?.canvasView?.becomeFirstResponder()
            self?.refreshUndoState()
        }
    }

    func refreshUndoState() {
        canUndo = canvasView?.undoManager?.canUndo ?? false
        canRedo = canvasView?.undoManager?.canRedo ?? false
    }

    func undo() {
        guard let m = canvasView?.undoManager, m.canUndo else { return }
        m.undo()
        refreshUndoState()
    }

    func redo() {
        guard let m = canvasView?.undoManager, m.canRedo else { return }
        m.redo()
        refreshUndoState()
    }

    /// Replaces the canvas contents; PencilKit records this in the same undo stack as strokes.
    func clear() {
        guard let c = canvasView, !c.drawing.strokes.isEmpty else { return }
        c.drawing = PKDrawing()
        refreshUndoState()
    }
}
