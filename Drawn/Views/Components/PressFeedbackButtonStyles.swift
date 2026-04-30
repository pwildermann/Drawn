import SwiftUI
import UIKit

// MARK: - Press scale
//
// Use this for **off-scroll** `Button`s (sheets, floating controls). For list/grid rows,
// prefer `PressTrackingButton` if `configuration.isPressed` feels late or you were tempted
// to add extra gestures to `ButtonStyle` (those often break taps in scroll views).

struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.90
    var dimBrightness: CGFloat = 0.04

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .brightness(configuration.isPressed ? -dimBrightness : 0)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.4, dampingFraction: 0.38),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    let g = UIImpactFeedbackGenerator(style: .light)
                    g.prepare()
                    g.impactOccurred()
                }
            }
    }
}
