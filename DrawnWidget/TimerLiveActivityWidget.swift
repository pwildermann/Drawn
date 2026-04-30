import ActivityKit
import AppIntents
import DrawnActivityModels
import SwiftUI
import UIKit
import WidgetKit

// Running countdown: **`Text(endDate, style: .timer)`** uses the **system** clock (**no** per-second `TimelineView` ticks — those are throttled when the app is suspended). Plain digits + **`TimelineView.periodic`** froze labels in the background.
//
// Uses `doodleImageData` on each `ContentState` update so the Live Activity shows the
// current doodle; falls back to attributes from the first frame.
private func doodleImageData(for context: ActivityViewContext<TimerActivityAttributes>) -> Data? {
    context.state.doodleImageData ?? context.attributes.doodleImageData
}

/// `drawn://stop|toggle?id=` — iOS 16 fallback **`Link`**; iOS 17+ stop uses `StopDrawnTimerIntent` (`openAppWhenRun: false`, no app switch). Toggle uses `ToggleDrawnTimerIntent`.
private func drawnTimerDeepLink(host: String, timerID: String) -> URL {
    var c = URLComponents()
    c.scheme = "drawn"
    c.host = host
    c.queryItems = [URLQueryItem(name: "id", value: timerID)]
    return c.url!
}

private func canShowPlayPauseToggle(_ state: TimerActivityAttributes.ContentState) -> Bool {
    guard !state.isRinging else { return false }
    if state.isPaused { return state.remainingSeconds > 0 }
    // Deadline passed but push hasn’t flipped `isRinging` yet — suppress play/pause (same as ringing).
    if state.endDate.timeIntervalSinceNow <= 0 { return false }
    guard state.remainingSeconds > 0 else { return false }
    return state.endDate.timeIntervalSinceNow > -120
}

/// True when **`now`** has reached **`endDate`** for a running, non‑paused countdown while **`isRinging`** may still be false (activity update not delivered).
private func liveActivityRunningCountdownHasElapsed(_ state: TimerActivityAttributes.ContentState, now: Date) -> Bool {
    guard !state.isRinging, !state.isPaused else { return false }
    return now >= state.endDate
}

private func countdownLabel(seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, sec)
        : String(format: "%d:%02d", m, sec)
}

/// Running Live Activity countdown via **`Text(endDate, style: .timer)`**; **`LiveActivityCountdownSizing`** avoids zero-width timer text.
private struct RunningLiveActivityTimerText: View {
    let state: TimerActivityAttributes.ContentState
    let font: Font
    let kerning: CGFloat
    let foreground: Color
    var maxTrailingWidth: CGFloat?
    /// Stable layout width for pills (**ActivityKit**). In the pill, glyphs are **leading** inside the column so the icon→time gap stays tight; **`LiveActivityPillCenterLayout.clusterOpticalBalanceX`** recenters the row.
    var fixedDigitColumnWidth: CGFloat?

    init(
        state: TimerActivityAttributes.ContentState,
        font: Font,
        kerning: CGFloat,
        foreground: Color,
        maxTrailingWidth: CGFloat? = nil,
        fixedDigitColumnWidth: CGFloat? = nil
    ) {
        self.state = state
        self.font = font
        self.kerning = kerning
        self.foreground = foreground
        self.maxTrailingWidth = maxTrailingWidth
        self.fixedDigitColumnWidth = fixedDigitColumnWidth
    }

    var body: some View {
        Text(state.endDate, style: .timer)
            .font(font)
            .kerning(kerning)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .multilineTextAlignment(fixedDigitColumnWidth != nil ? .leading : .center)
            .modifier(
                LiveActivityCountdownSizing(
                    maxTrailingCap: maxTrailingWidth,
                    fixedDigitColumnWidth: fixedDigitColumnWidth
                )
            )
            .liveActivityCountdownDigitSnap()
    }
}

private struct LiveActivityCountdownSizing: ViewModifier {
    let maxTrailingCap: CGFloat?
    let fixedDigitColumnWidth: CGFloat?

    func body(content: Content) -> some View {
        if let w = fixedDigitColumnWidth {
            // Leading inside the column avoids a wide “dead” gap after the icon when the string is shorter than **`h:mm:ss`**; row is still optically centred via **`clusterOpticalBalanceX`**.
            content.frame(width: w, alignment: .leading)
        } else if let w = maxTrailingCap {
            // Center in the compact-trailing slot (`.trailing` felt left‑heavy next to the doodle).
            content.frame(maxWidth: w, alignment: .center)
        } else {
            // Stable width for digits (ActivityKit may ignore plain `fixedSize`; `timer` Text was 0×0 here.)
            content.frame(minWidth: 72, alignment: .center)
        }
    }
}

/// Locks monospace digit column width to **`remainingSeconds`** (matches **`Text(…, style: .timer)`** toggling **`h:mm:ss`** / **`m:ss`**). Optional **`cappedMax`** keeps expanded **175×48** capsules from overflowing.
private enum TimerCountdownDigitLayout {
    static func columnWidth(secondsRemaining: Int, cappedMax: CGFloat? = nil) -> CGFloat {
        let s = max(0, secondsRemaining)
        let raw: CGFloat
        switch s {
        case 3600...:
            raw = 108
        case 600 ..< 3600:
            raw = 88
        case 60 ..< 600:
            raw = 82
        default:
            raw = 74
        }
        guard let cap = cappedMax else { return raw }
        return min(raw, cap)
    }

    /// Elapsed **`endDate`** (Live Activity **`Text(…, style: .timer)`** still shows **`0`** briefly); layout uses **0**.
    static func secondsRemaining(for state: TimerActivityAttributes.ContentState, now: Date) -> Int {
        max(0, Int(ceil(state.endDate.timeIntervalSince(now))))
    }
}

/// Layout constants for **`LiveActivityPillCenteredIconAndTimer`** — must live outside the generic struct (**Swift** forbids `static let` storage there).
private enum LiveActivityPillCenterLayout {
    static let iconBoxWidth: CGFloat = 24
    /// Figma spacing between SF Symbol slot and monospace time (**4**).
    static let iconToLabelSpacing: CGFloat = 4
    /// Leading digits leave **trailing** slack in the fixed column → visual centre sits left of **`HStack`** centre; bias **`position`** right (tune against device snapshots).
    static let clusterOpticalBalanceX: CGFloat = 10
    static let iconOpticalNudgeX: CGFloat = 0
}

/// True geometric center (**`GeometryReader`** + **`position`**) — `Spacer`/`ZStack` rows still looked off-centre inside Live Activity capsules.
private struct LiveActivityPillCenteredIconAndTimer<Label: View>: View {
    let systemName: String
    let iconSize: CGFloat
    let iconWeight: Font.Weight
    let foreground: Color
    let pillHeight: CGFloat
    @ViewBuilder var label: () -> Label

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: LiveActivityPillCenterLayout.iconToLabelSpacing) {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: iconWeight))
                    .foregroundStyle(foreground)
                    .frame(width: LiveActivityPillCenterLayout.iconBoxWidth, height: pillHeight)
                    .imageScale(.medium)
                    .offset(x: LiveActivityPillCenterLayout.iconOpticalNudgeX)
                label()
            }
            .fixedSize(horizontal: true, vertical: false)
            .position(
                x: geo.size.width * 0.5 + LiveActivityPillCenterLayout.clusterOpticalBalanceX,
                y: geo.size.height * 0.5
            )
        }
    }
}

private extension View {
    /// Avoid noisy implicit transitions when timer digits redraw.
    @ViewBuilder
    func liveActivityCountdownDigitSnap() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.identity)
        } else {
            self.transaction { $0.disablesAnimations = true }
        }
    }
}

// Deep links are the stable path for Live Activity controls in this project.
@ViewBuilder
private func stopDismissControl<Content: View>(timerID: String, @ViewBuilder label: () -> Content) -> some View {
    Link(destination: drawnTimerDeepLink(host: "stop", timerID: timerID)) {
        label()
    }
}

private func playPauseToggleOrStaticExpanded(timerID: String, state: TimerActivityAttributes.ContentState) -> some View {
    let pill = ExpandedTimerPill(state: state)
    /// Pin **175×48** — keeps the capsule layout stable while still being tappable.
    return Group {
        if canShowPlayPauseToggle(state) {
            Link(destination: drawnTimerDeepLink(host: "toggle", timerID: timerID)) { pill }
                .buttonStyle(LiveActivityPressScaleStyle())
        } else {
            pill
        }
    }
    .frame(width: ExpandedIslandTimerMetrics.capsuleWidth, height: ExpandedIslandTimerMetrics.capsuleHeight)
}

@ViewBuilder
private func playPauseToggleOrStaticLockScreen(timerID: String, state: TimerActivityAttributes.ContentState) -> some View {
    let pill = LockScreenTimerPill(state: state)
    if canShowPlayPauseToggle(state) {
        Link(destination: drawnTimerDeepLink(host: "toggle", timerID: timerID)) { pill }
            .buttonStyle(LiveActivityPressScaleStyle())
            .frame(maxWidth: .infinity)
    } else {
        pill
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Tap scale (matches `PressScaleButtonStyle` in the app; plain default has no scale)

private struct LiveActivityPressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.90

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.4, dampingFraction: 0.38),
                value: configuration.isPressed
            )
    }
}

// MARK: - Ringing style (Figma 134:1119 Dynamic Island expanded, 147:658 Lock Screen LA)

private enum LiveActivityRingingTokens {
    static let pillBg = Color(hex: 0xFECACA)
    static let accent = Color(hex: 0xDC2626)
    /// Lock screen dismiss button fill (147:665)
    static let lockDismissBg = Color(hex: 0xF2F2F2)
}

// MARK: - Widget

struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Top “31” in Figma is the camera / island inset — don’t add top padding here.
                // Only bottom + horizontal: 31pt below content, 31 / 37 side insets.
                DynamicIslandExpandedRegion(.bottom) {
                    // Equal **`Spacer`**s center **doodle · pill · dismiss** as a group; **`fixedSize`** + inner row **`Spacer`**s keep the timer glyphs centered inside the pill.
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)

                        HStack(spacing: 12) {
                            DoodleView(imageData: doodleImageData(for: context), inverted: false)
                                .frame(width: 60, height: 60)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            HStack(spacing: 8) {
                                playPauseToggleOrStaticExpanded(timerID: context.attributes.timerID, state: context.state)

                                stopDismissControl(timerID: context.attributes.timerID) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                        .frame(width: 48, height: 48)
                                        .background(Color(hex: 0x404040))
                                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                }
                                .buttonStyle(LiveActivityPressScaleStyle())
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 34)
                    .padding(.bottom, 31)
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                CompactLeadingDoodle(imageData: doodleImageData(for: context))
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalIcon(state: context.state)
            }
        }
    }
}

// MARK: - Lock Screen
// Figma 147:658 — ringing: red/200 pill + red/600 `0:00`; dismiss `#F2F2F2` + grey-900 ×. Non‑ringing: 145:523 capsule + grey-100 close.

private struct LockScreenView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            lockChrome(now: context.date)
        }
    }

    private func lockChrome(now: Date) -> some View {
        let elapsed = liveActivityRunningCountdownHasElapsed(context.state, now: now)
        let ringingDismissChrome = context.state.isRinging || elapsed
        /// Doodle + timer stay **leading**; **`Spacer`** keeps the dismiss control on the trailing edge.
        return HStack(alignment: .center, spacing: 12) {
            DoodleView(
                imageData: context.state.doodleImageData ?? context.attributes.doodleImageData,
                inverted: false
            )
            .frame(width: 48, height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 9.6, style: .continuous))

            playPauseToggleOrStaticLockScreen(timerID: context.attributes.timerID, state: context.state)

            stopDismissControl(timerID: context.attributes.timerID) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.lockScreenGrey900)
                    .frame(width: 48, height: 48)
                    .background(ringingDismissChrome ? LiveActivityRingingTokens.lockDismissBg : Color.lockScreenGrey100)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(LiveActivityPressScaleStyle())
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(hex: 0xF2F2F2), lineWidth: 1)
        }
    }
}

// MARK: - Lock Screen timer capsule — running · paused · ended (orange) · **ringing** (147:658 red)

/// One shell for **running ↔ paused** avoids ActivityKit swapping branches (layout jump).
private struct LockScreenUnifiedRunPauseCapsule: View {
    let state: TimerActivityAttributes.ContentState
    var timelineNow: Date

    private var paused: Bool { state.isPaused }
    private var fg: Color { paused ? Color(hex: 0x00AD42) : Color(hex: 0xF98500) }
    private var capsuleFill: Color { paused ? Color(hex: 0xEFFAF0) : Color(hex: 0xFFF3E9) }

    private var secondsForColumn: Int {
        paused
            ? max(0, state.remainingSeconds)
            : TimerCountdownDigitLayout.secondsRemaining(for: state, now: timelineNow)
    }

    var body: some View {
        let digitColumn = TimerCountdownDigitLayout.columnWidth(secondsRemaining: secondsForColumn)
        return Capsule()
            .fill(capsuleFill)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay {
                LiveActivityPillCenteredIconAndTimer(
                    systemName: paused ? "play.fill" : "pause.fill",
                    iconSize: 15,
                    iconWeight: .bold,
                    foreground: fg,
                    pillHeight: 48
                ) {
                    if paused {
                        Text(countdownLabel(seconds: state.remainingSeconds))
                            .font(.system(size: 20, weight: .semibold))
                            .kerning(-0.4)
                            .monospacedDigit()
                            .foregroundStyle(fg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(width: digitColumn, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    } else {
                        RunningLiveActivityTimerText(
                            state: state,
                            font: .system(size: 20, weight: .semibold),
                            kerning: -0.4,
                            foreground: fg,
                            maxTrailingWidth: nil,
                            fixedDigitColumnWidth: digitColumn
                        )
                    }
                }
            }
            .transaction { $0.animation = nil }
    }
}

private struct LockScreenTimerPill: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = liveActivityRunningCountdownHasElapsed(state, now: context.date)
            Group {
                if state.isRinging || elapsed {
                    ringingPill147658
                } else {
                    LockScreenUnifiedRunPauseCapsule(state: state, timelineNow: context.date)
                }
            }
            .frame(minHeight: 48)
        }
    }

    /// Figma 147:660 — Heading/H2, `red/200` capsule, centered `red/600`.
    private var ringingPill147658: some View {
        ZStack {
            Capsule().fill(LiveActivityRingingTokens.pillBg)
            Text("0:00")
                .font(.system(size: 20, weight: .semibold))
                .kerning(-0.4)
                .monospacedDigit()
                .foregroundStyle(LiveActivityRingingTokens.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }

}

/// Expanded Dynamic Island pill size (Figma ~175×48).
private enum ExpandedIslandTimerMetrics {
    static let capsuleWidth: CGFloat = 175
    static let capsuleHeight: CGFloat = 48
    /// Room left for monospace digits beside SF Symbol (`iconBoxWidth` + `iconToLabelSpacing` + nominal horizontal slack).
    static let expandedInnerTimerDigitCap: CGFloat =
        capsuleWidth
        - LiveActivityPillCenterLayout.iconBoxWidth
        - LiveActivityPillCenterLayout.iconToLabelSpacing
        - (12 + 12)
}

/// Same idea as lock screen: one **175×48** shell for **running ↔ paused** so the expanded island doesn’t swap layout trees.
private struct ExpandedUnifiedRunPauseCapsule: View {
    let state: TimerActivityAttributes.ContentState
    var timelineNow: Date

    private var paused: Bool { state.isPaused }
    private var fg: Color { paused ? Color(hex: 0x00AD42) : Color(hex: 0xF98500) }
    private var capsuleFill: Color { paused ? Color(hex: 0xEFFAF0) : Color(hex: 0xFFF3E9) }

    private var secondsForColumn: Int {
        paused
            ? max(0, state.remainingSeconds)
            : TimerCountdownDigitLayout.secondsRemaining(for: state, now: timelineNow)
    }

    var body: some View {
        let cap = ExpandedIslandTimerMetrics.expandedInnerTimerDigitCap
        let digitColumn = TimerCountdownDigitLayout.columnWidth(secondsRemaining: secondsForColumn, cappedMax: cap)
        return Capsule()
            .fill(capsuleFill)
            .frame(width: ExpandedIslandTimerMetrics.capsuleWidth, height: ExpandedIslandTimerMetrics.capsuleHeight)
            .overlay {
                LiveActivityPillCenteredIconAndTimer(
                    systemName: paused ? "play.fill" : "pause.fill",
                    iconSize: 13,
                    iconWeight: .bold,
                    foreground: fg,
                    pillHeight: ExpandedIslandTimerMetrics.capsuleHeight
                ) {
                    if paused {
                        Text(countdownLabel(seconds: state.remainingSeconds))
                            .font(.system(size: 20, weight: .semibold))
                            .kerning(-0.4)
                            .monospacedDigit()
                            .foregroundStyle(fg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(width: digitColumn, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    } else {
                        RunningLiveActivityTimerText(
                            state: state,
                            font: .system(size: 20, weight: .semibold),
                            kerning: -0.4,
                            foreground: fg,
                            maxTrailingWidth: nil,
                            fixedDigitColumnWidth: digitColumn
                        )
                    }
                }
            }
            .transaction { $0.animation = nil }
    }
}

// MARK: - Expanded timer pill
// Running/paused: 175×48 orange/green capsule. Finished (non‑ringing): orange ended. Ringing: Figma **134:1119**.

private struct ExpandedTimerPill: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = liveActivityRunningCountdownHasElapsed(state, now: context.date)
            if state.isRinging || elapsed {
                ringingExpandedPill1341119
            } else {
                ExpandedUnifiedRunPauseCapsule(state: state, timelineNow: context.date)
            }
        }
    }

    /// Figma 134:1145–1148 — light red pill only; layered offset shadow caused a darker strip peeking above the pill in Dynamic Island.
    private var ringingExpandedPill1341119: some View {
        Capsule()
            .fill(LiveActivityRingingTokens.pillBg)
            .frame(width: ExpandedIslandTimerMetrics.capsuleWidth, height: ExpandedIslandTimerMetrics.capsuleHeight)
            .overlay {
                Text("0:00")
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(LiveActivityRingingTokens.accent)
            }
    }
}

// MARK: - Compact leading: timer doodle (Figma 141:502 — 24×24, 4pt radius, by camera / center)

private struct CompactLeadingDoodle: View {
    let imageData: Data?

    var body: some View {
        DoodleView(imageData: imageData, inverted: false, useCompactPlaceholder: true)
            .frame(width: 24, height: 24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.leading, 6)
    }
}

// MARK: - Compact trailing: live countdown (ringing goes through AlertConfiguration → expanded island; compact matches 0:00)

private struct CompactTrailing: View {
    let state: TimerActivityAttributes.ContentState

    private var isPaused: Bool { state.isPaused }

    private func contentColor(ringLike: Bool, paused: Bool) -> Color {
        if ringLike { return LiveActivityRingingTokens.accent }
        return paused ? Color(hex: 0x00AD42) : Color(hex: 0xF98500)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = liveActivityRunningCountdownHasElapsed(state, now: context.date)
            let ringLike = state.isRinging || elapsed
            Group {
                if ringLike {
                    Text("0:00")
                } else if isPaused {
                    Text(pauseLabel)
                } else {
                    CompactDynamicIslandRunningCountdown(state: state, foreground: contentColor(ringLike: false, paused: false))
                }
            }
            .font(.system(size: 14, weight: .medium))
            .kerning(-0.28)
            .monospacedDigit()
            .foregroundStyle(contentColor(ringLike: ringLike, paused: isPaused))
        }
    }

    private var pauseLabel: String {
        let s = state.remainingSeconds
        if s >= 3600 {
            let h = s / 3600; let m = (s % 3600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else if s >= 60 {
            return "\(s / 60)min"
        } else {
            return "\(s)s"
        }
    }
}

private struct CompactDynamicIslandRunningCountdown: View {
    let state: TimerActivityAttributes.ContentState
    let foreground: Color

    var body: some View {
        RunningLiveActivityTimerText(
            state: state,
            font: .system(size: 14, weight: .medium),
            kerning: -0.28,
            foreground: foreground,
            maxTrailingWidth: 42
        )
    }
}

// MARK: - Minimal

private struct MinimalIcon: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = liveActivityRunningCountdownHasElapsed(state, now: context.date)
            let ringLike = state.isRinging || elapsed
            Image(systemName: ringLike ? "pause.fill" : (state.isPaused ? "play.fill" : "pause.fill"))
                .font(.system(size: 10, weight: .bold))
                .frame(width: 12, height: 12)
                .foregroundStyle(
                    ringLike
                        ? LiveActivityRingingTokens.accent
                        : (state.isPaused ? Color(hex: 0x00AD42) : Color(hex: 0xF98500))
                )
        }
    }
}

// MARK: - Doodle image (expanded + compact)

/// Shows the doodle (original colours) when data is available,
/// or a pure-SwiftUI placeholder as fallback.
/// Pass `inverted: true` on the black Dynamic Island to flip
/// dark strokes → white strokes via `.colorInvert()`.
private struct DoodleView: View {
    let imageData: Data?
    var inverted: Bool = false
    /// Small SF Symbol for tiny frames (e.g. compact Island) when there’s no image.
    var useCompactPlaceholder: Bool = false

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else if useCompactPlaceholder {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.primary, lineWidth: 3)
                    Circle()
                        .stroke(Color.primary, lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
        }
        .colorInvert(active: inverted)
    }
}

private extension View {
    @ViewBuilder
    func colorInvert(active: Bool) -> some View {
        if active { self.colorInvert() } else { self }
    }
}

// MARK: - Helpers

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Figma grey-100 (`#F3F4F6`) — lock screen close control background.
    static let lockScreenGrey100 = Color(hex: 0xF3F4F6)
    /// Figma grey-900 (`#111827`) — lock screen close icon.
    static let lockScreenGrey900 = Color(hex: 0x111827)
}

// MARK: - Previews


#Preview("Lock Screen", as: .content,
         using: TimerActivityAttributes(timerID: "preview")) {
    TimerLiveActivityWidget()
} contentStates: {
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date().addingTimeInterval(5400),
        isPaused: false, remainingSeconds: 5400, totalSeconds: 7200)
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date(),
        isPaused: true, remainingSeconds: 3600, totalSeconds: 7200)
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date(),
        isPaused: false, remainingSeconds: 0, totalSeconds: 7200)
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date(),
        isPaused: false, remainingSeconds: 0, totalSeconds: 7200, doodleImageData: nil, isRinging: true
    )
}

#Preview("Compact", as: .dynamicIsland(.compact),
         using: TimerActivityAttributes(timerID: "preview")) {
    TimerLiveActivityWidget()
} contentStates: {
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date().addingTimeInterval(480),
        isPaused: false, remainingSeconds: 480, totalSeconds: 900)
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date(),
        isPaused: true, remainingSeconds: 480, totalSeconds: 900)
}

#Preview("Expanded", as: .dynamicIsland(.expanded),
         using: TimerActivityAttributes(timerID: "preview")) {
    TimerLiveActivityWidget()
} contentStates: {
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date().addingTimeInterval(5400),
        isPaused: false, remainingSeconds: 5400, totalSeconds: 7200)
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date(),
        isPaused: true, remainingSeconds: 5400, totalSeconds: 7200)
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date(),
        isPaused: false, remainingSeconds: 0, totalSeconds: 7200)
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date(),
        isPaused: false, remainingSeconds: 0, totalSeconds: 7200, doodleImageData: nil, isRinging: true
    )
}

#Preview("Minimal", as: .dynamicIsland(.minimal),
         using: TimerActivityAttributes(timerID: "preview")) {
    TimerLiveActivityWidget()
} contentStates: {
    TimerActivityAttributes.ContentState(
        name: "Focus", endDate: Date().addingTimeInterval(900),
        isPaused: false, remainingSeconds: 600, totalSeconds: 900)
}
