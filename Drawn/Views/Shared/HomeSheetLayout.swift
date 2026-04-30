import SwiftUI
import UIKit

/// Shared mask corner radius + display corner helpers for floating bottom sheets (`HomeView`, primer).
enum HomeSheetLayout {
    static let clipCornerRadius: CGFloat = {
        let r =
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.displayCornerRadius ?? 44
        return max(8, r - 8)
    }()
}

extension UIScreen {
    /// Uses `_displayCornerRadius` when present so sheet radii hug the physically rounded panel.
    var displayCornerRadius: CGFloat {
        (value(forKey: "_displayCornerRadius") as? CGFloat) ?? 44
    }
}
