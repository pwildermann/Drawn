import PencilKit
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(TimerStore.self) private var timerStore
    @State private var showingCreateSheet = false
    @State private var sheetDragOffset: CGFloat = 0
    @State private var selectedTimer: DrawnTimer? = nil
    @State private var actionSheetDragOffset: CGFloat = 0
    @State private var editingTimer: DrawnTimer? = nil
    @State private var editSheetDragOffset: CGFloat = 0
    @State private var notificationPrimerDragOffset: CGFloat = 0

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(hex: 0xF2F2F2)
                .ignoresSafeArea()

            if timerStore.timers.isEmpty {
                VStack(spacing: 0) {
                    headline
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                        .padding(.horizontal, 20)

                    Spacer()

                    VStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("Pretty empty here")
                                .foregroundStyle(Color(hex: 0x8C8C8C))
                            Text("Add your first timer")
                                .foregroundStyle(Color(hex: 0x0D0D0D))
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .kerning(-0.32)
                        .multilineTextAlignment(.center)

                        addButton
                    }

                    Spacer()
                }
            } else {
                // Root `ZStack` is laid out in the *safe* rect: bottom padding is measured from the
                // safe bottom, then the home indicator adds another band—so the gap looks ~2× the
                // trailing 48. Subtract `safeAreaInsets.bottom` so the total space matches ~48 to the
                // physical bottom (see Apple’s safe-area insets on `GeometryReader`).
                GeometryReader { gridProxy in
                    ZStack(alignment: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 32) {
                                headline
                                    .padding(.top, 24)

                                LazyVGrid(columns: columns, spacing: 14) {
                                    ForEach(timerStore.timers) { timer in
                                        HomeTimerCardView(
                                            timeText: timer.remainingDisplayText,
                                            doodleData: timer.doodleData,
                                            isRunning: timer.isRunning,
                                            hasStarted: timer.hasStarted,
                                            progress: timer.progress,
                                            isRinging: timerStore.ringingAlarmTimerIDForUI == timer.id,
                                            onStopRinging: { timerStore.resetTimer(timer.id) },
                                            onToggle: { timerStore.toggleTimer(timer.id) },
                                            onCardTap: {
                                                withAnimation(BottomSheetMotion.present) {
                                                    selectedTimer = timer
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            // ~110 for FAB; +112 for Figma bottom scrim (32 fade + 80 fill) so last rows clear it.
                            .padding(.bottom, 220)
                            // On scroll *content* so the marker UIKit view is a descendant of `UIScrollView`.
                            // Then we can clear `delaysContentTouches` (quick taps vs “long-press” feel).
                            .background(ScrollViewDisablesContentTouchDelays(), alignment: .topLeading)
                        }
                    }
                    .frame(width: gridProxy.size.width, height: gridProxy.size.height, alignment: .top)
                    // Spacer+scrim in a `ZStack(alignment: .top)` was top-aligned: only ~112pt tall and sat at the
                    // top of the stack. Pin with `overlay(alignment: .bottom)` so the fade hugs the bar.
                    // `GeometryReader` stops at the *safe* bottom; `ignoresSafeArea` on the overlay does not
                    // always extend layout into the home-indicator strip, so a gap remains. Shift the whole
                    // 112pt scrim down by that inset so the solid fill runs to the real screen bottom.
                    .overlay(alignment: .bottom) {
                        HomeListBottomScrim()
                            .frame(maxWidth: .infinity)
                            .offset(y: gridProxy.safeAreaInsets.bottom)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        addButton
                            .padding(.trailing, 48)
                            .padding(
                                .bottom,
                                max(8, 48 - gridProxy.safeAreaInsets.bottom)
                            )
                    }
                }
            }
        }
        // Timer action sheet overlay
        .overlay {
            GeometryReader { _ in
                ZStack(alignment: .bottom) {
                    Color.black
                        .opacity(selectedTimer != nil ? 0.2 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(selectedTimer != nil)
                        .onTapGesture { dismissActionSheet() }
                        .animation(.easeInOut(duration: 0.25), value: selectedTimer?.id)
                        .zIndex(0)

                    if selectedTimer != nil {
                        timerActionSheet()
                            .offset(y: actionSheetDragOffset)
                            .gesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        let y = value.translation.height
                                        actionSheetDragOffset = y > 0 ? y : y * 0.08
                                    }
                                    .onEnded { value in
                                        let shouldDismiss = value.translation.height > 80
                                            || value.predictedEndTranslation.height > 200
                                        if shouldDismiss {
                                            dismissActionSheet()
                                        } else {
                                            withAnimation(BottomSheetMotion.dismiss) {
                                                actionSheetDragOffset = 0
                                            }
                                        }
                                    }
                            )
                            .transition(.move(edge: .bottom))
                            .zIndex(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
            }
            .allowsHitTesting(selectedTimer != nil)
        }
        // Edit timer sheet overlay
        .overlay {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Color.black
                        .opacity(editingTimer != nil ? 0.35 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(editingTimer != nil)
                        .onTapGesture { dismissEditSheet() }
                        .animation(.easeInOut(duration: 0.25), value: editingTimer?.id)
                        .zIndex(0)

                    if let timer = editingTimer {
                        EditTimerView(isPresented: Binding(
                            get: { editingTimer != nil },
                            set: { if !$0 { dismissEditSheet() } }
                        ), timer: timer)
                        .environment(timerStore)
                        .frame(width: proxy.size.width - 16, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(.white)
                        .clipShape(
                            RoundedRectangle(cornerRadius: HomeSheetLayout.clipCornerRadius)
                            )
                            .padding(.bottom, 8)
                            .offset(y: editSheetDragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    let y = value.translation.height
                                    editSheetDragOffset = y > 0 ? y : y * 0.08
                                }
                                .onEnded { value in
                                    let shouldDismiss = value.translation.height > 80
                                        || value.predictedEndTranslation.height > 220
                                    if shouldDismiss {
                                        dismissEditSheet()
                                    } else {
                                        withAnimation(BottomSheetMotion.dismiss) {
                                            editSheetDragOffset = 0
                                        }
                                    }
                                }
                        )
                        .transition(.move(edge: .bottom))
                        .zIndex(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
            }
            .allowsHitTesting(editingTimer != nil)
        }
        // Notification permission primer (once, after first timer start — Figma 169:523)
        .overlay {
            GeometryReader { _ in
                ZStack(alignment: .bottom) {
                    Color.black
                        .opacity(timerStore.presentNotificationPermissionPrimer ? 0.2 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(timerStore.presentNotificationPermissionPrimer)
                        .onTapGesture { dismissNotificationPermissionPrimerFlow() }
                        .animation(.easeInOut(duration: 0.25), value: timerStore.presentNotificationPermissionPrimer)

                    if timerStore.presentNotificationPermissionPrimer {
                        DrawnHomeNotificationPrimerSheet(onGotIt: dismissNotificationPermissionPrimerFlow)
                            .offset(y: notificationPrimerDragOffset)
                            .gesture(notificationPrimerDragGesture)
                            .transition(.move(edge: .bottom))
                    }
                }
                .animation(BottomSheetMotion.present, value: timerStore.presentNotificationPermissionPrimer)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
            }
            .allowsHitTesting(timerStore.presentNotificationPermissionPrimer)
        }
        // Create timer sheet — last in the overlay chain so it paints above other full-screen
        // dim layers; explicit zIndex keeps the sheet above its own backdrop during transitions.
        .overlay {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    // Backdrop lives outside the `if` so it fades linearly rather than
                    // spring-animating opacity (which overshoots and pops to 0).
                    Color.black
                        .opacity(showingCreateSheet ? 0.35 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(showingCreateSheet)
                        .onTapGesture { dismissSheet() }
                        .animation(.easeInOut(duration: 0.25), value: showingCreateSheet)
                        .zIndex(0)

                    if showingCreateSheet {
                        CreateTimerView(isPresented: $showingCreateSheet)
                            .environment(timerStore)
                            // Intrinsic height: fixed `height: …` left dead space. `TimePickerWheelView` uses
                            // a fixed 144pt frame + UIKit `intrinsicContentSize` so `fixedSize` is safe.
                            .frame(width: proxy.size.width - 16, alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(.white)
                            .clipShape(
                                RoundedRectangle(cornerRadius: HomeSheetLayout.clipCornerRadius)
                            )
                            .padding(.bottom, 8)
                            // `GeometryReader` is in safe-area coordinates; without this shift the sheet
                            // sits `safeAreaInsets.bottom` higher than the physical screen edge.
                            .offset(y: sheetDragOffset + proxy.safeAreaInsets.bottom)
                            .gesture(dragGesture)
                            .transition(.move(edge: .bottom))
                            .zIndex(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
            }
            .allowsHitTesting(showingCreateSheet)
        }
        .onChange(of: timerStore.presentNotificationPermissionPrimer) { _, presenting in
            if presenting {
                notificationPrimerDragOffset = 0
            }
        }
    }

    private func dismissEditSheet() {
        withAnimation(BottomSheetMotion.dismiss) {
            editingTimer = nil
            editSheetDragOffset = 0
        }
    }

    // MARK: - Action sheet

    @ViewBuilder
    private func timerActionSheet() -> some View {
        VStack(spacing: 32) {
            // Grabber row: 16pt tall container, capsule pinned 5pt from top (matches Figma)
            Color.clear
                .frame(height: 16)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color(hex: 0xCCCCCC))
                        .frame(width: 36, height: 5)
                        .padding(.top, 5)
                }

            // Actions
            VStack(spacing: 12) {
                // Reset — only enabled when the timer has been started or paused
                actionButton(
                    icon: "arrow.uturn.backward",
                    label: "Reset",
                    enabled: selectedTimer?.hasStarted ?? false
                ) {
                    if let id = selectedTimer?.id { timerStore.resetTimer(id) }
                    dismissActionSheet()
                }

                // Edit
                actionButtonCustomIcon(icon: AnyView(EditIcon()), label: "Edit") {
                    guard let toEdit = selectedTimer else { return }
                    withAnimation(BottomSheetMotion.present) {
                        editingTimer = toEdit
                        selectedTimer = nil
                        actionSheetDragOffset = 0
                    }
                }

                // Delete (label + vertical padding = 36pt; 20pt to sheet bottom, same as create sheet insets)
                Button {
                    if let id = selectedTimer?.id { timerStore.deleteTimer(id) }
                    dismissActionSheet()
                } label: {
                    Text("Delete")
                        .font(.system(size: 16, weight: .semibold))
                        .kerning(-0.32)
                        .foregroundStyle(Color(hex: 0xD93535))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(.white)
        .clipShape(
            RoundedRectangle(cornerRadius: HomeSheetLayout.clipCornerRadius)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        actionButtonCustomIcon(
            icon: AnyView(
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
            ),
            label: label,
            enabled: enabled,
            action: action
        )
    }

    @ViewBuilder
    private func actionButtonCustomIcon(icon: AnyView, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: 24, height: 24)
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .kerning(-0.32)
            }
            .foregroundStyle(enabled ? Color(hex: 0x0D0D0D) : Color(hex: 0xD9D9D9))
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .disabled(!enabled)
        .buttonStyle(PressScaleButtonStyle())
    }

    private func dismissActionSheet() {
        withAnimation(BottomSheetMotion.dismiss) {
            selectedTimer = nil
            actionSheetDragOffset = 0
        }
    }

    // MARK: - Drag to dismiss (create sheet)

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let y = value.translation.height
                sheetDragOffset = y > 0 ? y : y * 0.08
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > 80
                    || value.predictedEndTranslation.height > 220
                if shouldDismiss {
                    dismissSheet()
                } else {
                    withAnimation(BottomSheetMotion.dismiss) {
                        sheetDragOffset = 0
                    }
                }
            }
    }

    private func dismissSheet() {
        withAnimation(BottomSheetMotion.dismiss) {
            showingCreateSheet = false
            sheetDragOffset = 0
        }
    }

    private var notificationPrimerDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let y = value.translation.height
                notificationPrimerDragOffset = y > 0 ? y : y * 0.08
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > 80
                    || value.predictedEndTranslation.height > 200
                if shouldDismiss {
                    dismissNotificationPermissionPrimerFlow()
                } else {
                    withAnimation(BottomSheetMotion.dismiss) {
                        notificationPrimerDragOffset = 0
                    }
                }
            }
    }

    private func dismissNotificationPermissionPrimerFlow() {
        DrawnNotificationPermissionEducation.markPrimerFlowFinished()
        withAnimation(BottomSheetMotion.dismiss) {
            notificationPrimerDragOffset = 0
            timerStore.dismissNotificationPermissionPrimer()
        }
        Task {
            await timerStore.resumeNotificationSchedulingAfterEducationSheet()
        }
    }

    // MARK: - Shared subviews

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning,"
        case 12..<18: return "Good afternoon,"
        case 18..<22: return "Good evening,"
        default:      return "Good night,"
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .foregroundStyle(Color(hex: 0x0D0D0D))
            Text("what's on the clock?")
                .foregroundStyle(Color(hex: 0x8C8C8C))
        }
        .font(.system(size: 28, weight: .bold))
        .kerning(-0.56)
        .lineSpacing(4)
    }

    private var addButton: some View {
        Button {
            withAnimation(BottomSheetMotion.present) {
                showingCreateSheet = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color(hex: 0x0D0D0D))
                .padding(14)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Add Timer")
    }
}

// MARK: - Home list bottom scrim (Figma 75:331)

/// 32pt gradient into `grey/100` + 80pt solid — sits above the home bar, under the + button.
private struct HomeListBottomScrim: View {
    private static let fill = Color(hex: 0xF2F2F2)

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Self.fill.opacity(0), Self.fill],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 32)
            .frame(maxWidth: .infinity)

            Self.fill
                .frame(height: 80)
                .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ringing pill micro-motion (Figma 147:608)

private struct RingingControlVibrationModifier: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 48.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let jitterX = sin(t * 21.0) * 0.55 + sin(t * 39.3) * 0.22
            let jitterY = cos(t * 18.5) * 0.36 + cos(t * 28.8) * 0.18
            let deg = sin(t * 17.7) * 0.35
            content
                .offset(x: jitterX, y: jitterY)
                .rotationEffect(.degrees(deg))
        }
    }
}

// MARK: - Timer card

private struct HomeTimerCardView: View {
    let timeText: String
    let doodleData: Data?
    let isRunning: Bool
    let hasStarted: Bool
    let progress: Double
    /// Figma 147:608 — ringing row (light-red pill + X + `0:00`) replaces play/pause when alarm is sounding.
    let isRinging: Bool
    let onStopRinging: () -> Void
    let onToggle: () -> Void
    let onCardTap: () -> Void

    /// Whole-card scale uses SwiftUI on the outer wrapper. The play pill uses UIKit transform
    /// inside `PressTrackingButton`; the card tap target is a full-bleed control *behind* the
    /// doodle so `Image` doesn’t steal touches from the `UIButton`.
    @State private var cardPressed = false

    /// `170`pt card with `12`pt inner padding on all sides.
    private var cardContentHeight: CGFloat { 170 - 12 * 2 }

    private var contentColor: Color {
        if isRunning  { return Color(hex: 0xF98500) }
        if hasStarted { return Color(hex: 0x00AD42) }
        return Color(hex: 0x3241E8)
    }
    private var bgColor: Color {
        if isRunning  { return Color(hex: 0xFFF3E9) }
        if hasStarted { return Color(hex: 0xEFFAF0) }
        return Color(hex: 0xF0F5FF)
    }
    private var progressColor: Color {
        isRunning ? Color(hex: 0xFFE5D0) : Color(hex: 0xDBF5DD)
    }

    /// Figma — `red/200` pill, `red/600` content.
    private let ringingPillBg = Color(hex: 0xFECACA)
    private let ringingAccent = Color(hex: 0xDC2626)

    private func setCardPressed(_ pressed: Bool) {
        withAnimation(pressed ? .easeOut(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.38)) {
            cardPressed = pressed
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1) Full card: `UIButton` receives touches in the whole padded area (including on
            // top of the drawing — the doodle overlay has `allowsHitTesting(false)`).
            PressTrackingButton(
                expandsToFill: true,
                useUIKitPressAnimation: false,
                action: { if !isRinging { onCardTap() } },
                onPressingChanged: setCardPressed
            ) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 2) Running / paused play pill, **or** Figma 147:608 ringing strip (tap stops alarm).
            Group {
                if isRinging {
                    PressTrackingButton(action: onStopRinging) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 12, height: 12)
                            Text("0:00")
                                .font(.system(size: 16, weight: .semibold))
                                .kerning(-0.32)
                                .monospacedDigit()
                        }
                        .foregroundStyle(ringingAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(ringingPillBg))
                        .modifier(RingingControlVibrationModifier())
                    }
                } else {
                    PressTrackingButton(action: onToggle) {
                        HStack(spacing: 4) {
                            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 20, height: 20)
                            Text(timeText)
                                .font(.system(size: 16, weight: .semibold))
                                .kerning(-0.32)
                                .lineLimit(1)
                        }
                        .foregroundStyle(contentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule().fill(bgColor)
                            if hasStarted && progress > 0 {
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(progressColor)
                                        .frame(width: geo.size.width * progress)
                                        .animation(.linear(duration: 1), value: progress)
                                }
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // 3) Doodle on top for display; touches pass through to (1) or (2)
            doodlePreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(10)
                .allowsHitTesting(false)
        }
        // Pin height so the full-bleed `PressTrackingButton` gets a non-zero `sizeThatFits` in `ZStack`.
        .frame(maxWidth: .infinity, minHeight: cardContentHeight, maxHeight: cardContentHeight)
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .compositingGroup()
        .scaleEffect(cardPressed ? 0.90 : 1.0)
        .brightness(cardPressed ? -0.04 : 0)
    }

    private var doodlePreview: some View {
        let canvasRect = CGRect(origin: .zero, size: CGSize(width: 337, height: 337))
        let drawing: PKDrawing = {
            if let data = doodleData, let d = try? PKDrawing(data: data) { return d }
            return PKDrawing()
        }()
        let img = drawing.image(from: canvasRect, scale: 2)
        return Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

/// Edit / pencil icon converted from the Figma SVG asset (24×24 viewBox).
private struct EditIcon: View {
    var color: Color = Color(hex: 0x0D0D0D)

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24.0
            var path = Path()

            // Pencil body
            path.move(to:    .init(x: 12*s, y: 8*s))
            path.addLine(to: .init(x: 4*s,  y: 16*s))
            path.addLine(to: .init(x: 4*s,  y: 20*s))
            path.addLine(to: .init(x: 8*s,  y: 20*s))
            path.addLine(to: .init(x: 16*s, y: 12*s))

            // Pencil tip / ferrule
            path.move(to:    .init(x: 12*s,      y: 8*s))
            path.addLine(to: .init(x: 14.8686*s, y: 5.13146*s))
            path.addLine(to: .init(x: 14.8704*s, y: 5.12976*s))
            path.addCurve(
                to:       .init(x: 15.691*s,  y: 4.46301*s),
                control1: .init(x: 15.2652*s, y: 4.73488*s),
                control2: .init(x: 15.463*s,  y: 4.53709*s)
            )
            path.addCurve(
                to:       .init(x: 16.3091*s, y: 4.46301*s),
                control1: .init(x: 15.8919*s, y: 4.39775*s),
                control2: .init(x: 16.1082*s, y: 4.39775*s)
            )
            path.addCurve(
                to:       .init(x: 17.1288*s, y: 5.12892*s),
                control1: .init(x: 16.5369*s, y: 4.53704*s),
                control2: .init(x: 16.7345*s, y: 4.7346*s)
            )
            path.addLine(to: .init(x: 18.8686*s, y: 6.86872*s))
            path.addCurve(
                to:       .init(x: 19.5369*s, y: 7.69117*s),
                control1: .init(x: 19.2646*s, y: 7.26474*s),
                control2: .init(x: 19.4627*s, y: 7.46284*s)
            )
            path.addCurve(
                to:       .init(x: 19.5369*s, y: 8.3092*s),
                control1: .init(x: 19.6022*s, y: 7.89201*s),
                control2: .init(x: 19.6021*s, y: 8.10835*s)
            )
            path.addCurve(
                to:       .init(x: 18.8695*s, y: 9.13061*s),
                control1: .init(x: 19.4628*s, y: 8.53736*s),
                control2: .init(x: 19.265*s,  y: 8.73516*s)
            )
            path.addLine(to: .init(x: 18.8686*s, y: 9.13146*s))
            path.addLine(to: .init(x: 16*s,      y: 12*s))

            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 2*s, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Notification permission primer (bundled here so this file stays in the Xcode target)

/// Figma `169:523` — “Never miss a ding” primer before the system notification alert.
/// https://www.figma.com/design/t76BiRqvlGkpiIjdnPaykn/Drawn?node-id=169-523
private struct DrawnHomeNotificationPrimerSheet: View {
    var onGotIt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                notificationGrabberRow

                primerIllustration
                    .frame(width: 160, height: 120)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Never miss a ding")
                        .font(.system(size: 20, weight: .semibold))
                        .kerning(-0.4)
                        .foregroundStyle(Color(hex: 0x0D0D0D))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Text("We'll tap you when your timer's up. Just allow notifications on the next screen.")
                        .font(.system(size: 16, weight: .medium))
                        .kerning(-0.32)
                        .foregroundStyle(Color(hex: 0x737373))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }

            Button(action: onGotIt) {
                Text("Got it")
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
            .padding(.top, 32)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: HomeSheetLayout.clipCornerRadius))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var notificationGrabberRow: some View {
        Color.clear
            .frame(height: 16)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color(hex: 0xCCCCCC))
                    .frame(width: 36, height: 5)
                    .padding(.top, 5)
            }
    }

    private var primerIllustration: some View {
        BundledSVGIllustrationView(resourceName: "ringingtimer", svgExtension: "svg", width: 160, height: 120)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Home timer list scroll: fast taps

/// Plants a zero-size view in a SwiftUI `ScrollView` and clears `delaysContentTouches` on the
/// hosting `UIScrollView` so `UIButton` / `PressTrackingButton` in `LazyVGrid` get immediate touches.
private struct ScrollViewDisablesContentTouchDelays: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollContentTouchDelayFixMarker {
        let v = ScrollContentTouchDelayFixMarker()
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }

    func updateUIView(_ uiView: ScrollContentTouchDelayFixMarker, context: Context) {
        uiView.requestFix()
    }
}

private final class ScrollContentTouchDelayFixMarker: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        requestFix()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        requestFix()
    }

    fileprivate func requestFix() {
        DispatchQueue.main.async { [weak self] in
            self?.applyDelaysContentTouchesOff()
        }
    }

    private func applyDelaysContentTouchesOff() {
        var v: UIView? = self
        for _ in 0 ..< 80 {
            guard let c = v else { return }
            if let scroll = c as? UIScrollView {
                scroll.delaysContentTouches = false
                return
            }
            v = c.superview
        }
    }
}

#Preview {
    HomeView()
        .environment(TimerStore())
}
