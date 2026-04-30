import SwiftUI
import UIKit

/// Tappable control with reliable touch handling inside `ScrollView` / `LazyVGrid` — `UIButton`
/// instead of `Button` + extra gestures, which often fight the scroll / tap system.
///
/// **Press “animation” (scale / dim)**
/// Other apps and Apple’s own controls do this in **UIKit**: `UIButton` is a `UIControl`; you
/// animate `transform` (and sometimes `alpha`) in `touchDown` / `touchUp` with
/// `UIView.animate`. That is the stable, well-supported path.
///
/// If you *also* need SwiftUI state (e.g. scaling a **parent** that wraps this control), pass
/// `onPressingChanged` and set `@State` there. `useUIKitPressAnimation: false` avoids scaling
/// the `UIButton` itself (so you don’t double-scale the hosted label when the parent scales).
struct PressTrackingButton<Label: View>: UIViewRepresentable {
    var action: () -> Void
    var onPressingChanged: (Bool) -> Void
    var playsHaptic: Bool
    var expandsToFill: Bool
    /// When `true` (default), run press feedback with `UIView.animate` on the control’s
    /// `transform` + `alpha` on the **hosted** SwiftUI view (not the `UIButton`). Scaling the
    /// `UIButton` + Auto Layout + edge‑pinned `UIHostingController` can look like the pill
    /// “only shrinks vertically” because layout keeps re-resolving the full width in the
    /// button’s (untransformed) bounds.
    var useUIKitPressAnimation: Bool
    /// Passed through to the underlying `UIButton` (`isEnabled`); `false` disables press + action.
    var isEnabled: Bool
    /// `false` (default): use the full proposed width and measure height (e.g. play pill, labels with `maxWidth: .infinity`).
    /// `true`: measure intrinsic size in both dimensions (e.g. icon-only actions in a horizontal toolbar).
    var hugsContent: Bool
    @ViewBuilder var label: () -> Label

    init(
        playsHaptic: Bool = true,
        expandsToFill: Bool = false,
        useUIKitPressAnimation: Bool = true,
        isEnabled: Bool = true,
        hugsContent: Bool = false,
        action: @escaping () -> Void,
        onPressingChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.playsHaptic = playsHaptic
        self.expandsToFill = expandsToFill
        self.useUIKitPressAnimation = useUIKitPressAnimation
        self.isEnabled = isEnabled
        self.hugsContent = hugsContent
        self.action = action
        self.onPressingChanged = onPressingChanged
        self.label = label
    }

    final class Coordinator: NSObject {
        var parent: PressTrackingButton<Label>
        var hosting: UIHostingController<Label>?
        weak var button: UIButton?

        init(_ parent: PressTrackingButton<Label>) {
            self.parent = parent
        }

        private func applyUIKitPress(pressed: Bool) {
            guard let button, let content = self.hosting?.view, parent.useUIKitPressAnimation else { return }
            button.transform = .identity
            let t = CGAffineTransform(
                scaleX: PressMetrics.pressScale,
                y: PressMetrics.pressScale
            )
            if pressed {
                UIView.performWithoutAnimation {
                    content.transform = t
                    content.alpha = PressMetrics.pressAlpha
                }
            } else {
                UIView.animate(
                    withDuration: 0.32,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
                ) {
                    content.transform = .identity
                    content.alpha = 1
                }
            }
        }

        @objc func handleTouchDown() {
            guard parent.isEnabled else { return }
            if parent.playsHaptic {
                let g = UIImpactFeedbackGenerator(style: .light)
                g.prepare()
                g.impactOccurred()
            }
            applyUIKitPress(pressed: true)
            parent.onPressingChanged(true)
        }

        @objc func handleTouchUpInside() {
            applyUIKitPress(pressed: false)
            parent.onPressingChanged(false)
            parent.action()
        }

        @objc func handleTouchUpOutsideOrCancel() {
            applyUIKitPress(pressed: false)
            parent.onPressingChanged(false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        // Avoid the button relayouting the hosted view while a transform is applied to it.
        button.autoresizesSubviews = false
        if #available(iOS 15, *) {
            // Avoid the modern button style changing layout/highlight in ways that fight transforms.
            button.configuration = nil
        }
        let host = UIHostingController(rootView: label())
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = true
        host.view.isUserInteractionEnabled = false
        context.coordinator.hosting = host
        context.coordinator.button = button
        button.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: button.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        let c = context.coordinator
        button.addTarget(c, action: #selector(Coordinator.handleTouchDown), for: .touchDown)
        button.addTarget(c, action: #selector(Coordinator.handleTouchUpInside), for: .touchUpInside)
        button.addTarget(c, action: #selector(Coordinator.handleTouchUpOutsideOrCancel), for: [
            .touchUpOutside, .touchCancel
        ])
        // No `touchDragExit` / `touchDragEnter`: long-press micro-movement fires them in sequence and
        // briefly resets the transform to identity — looks like a pop *up* then down on the pill.
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.button = button
        button.isEnabled = isEnabled
        context.coordinator.hosting?.rootView = label()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let parent = context.coordinator.parent
        let w = proposal.width.map { $0 } ?? .nan
        let width: CGFloat
        if w.isFinite, w > 0 {
            width = w
        } else {
            width = UIView.layoutFittingExpandedSize.width
        }

        if parent.expandsToFill {
            // In `ZStack`, height is often *unspecified* in the first pass; falling through
            // to measuring `Color.clear` yields ~0 and the `UIButton` never receives touches.
            let height: CGFloat
            if let h = proposal.height, h.isFinite, h > 0, h < 1e6 {
                height = h
            } else if #available(iOS 16, *) {
                let s = proposal.replacingUnspecifiedDimensions(
                    by: CGSize(width: 400, height: 300)
                )
                height = max(s.height, 1)
            } else {
                height = 200
            }
            return CGSize(width: width, height: height)
        }

        guard let host = context.coordinator.hosting?.view else {
            return CGSize(width: 44, height: 44)
        }

        if parent.hugsContent {
            let measured = host.systemLayoutSizeFitting(
                UIView.layoutFittingCompressedSize,
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel
            )
            return CGSize(
                width: max(measured.width, 1),
                height: max(measured.height, 1)
            )
        }

        let measured = host.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: max(measured.height, 1))
    }
}

private enum PressMetrics {
    static let pressScale: CGFloat = 0.9
    static let pressAlpha: CGFloat = 0.97
}
