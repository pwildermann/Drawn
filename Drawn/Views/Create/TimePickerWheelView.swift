import SwiftUI
import UIKit

// MARK: - Shared layout constants

private enum PC {
    static let numFont:  UIFont  = .systemFont(ofSize: 20, weight: .semibold)
    static let unitFont: UIFont  = .systemFont(ofSize: 18, weight: .semibold)
    static let gap:      CGFloat = 4

    /// Tall enough that the top/bottom faded rows stay visible; +~20pt vs 160 when they felt clipped.
    static let wheelFrameHeight: CGFloat = 180

    /// Width reserved for the widest number ("59") — right-aligned in every row
    static let maxNumWidth: CGFloat = {
        ("59" as NSString).size(withAttributes: [.font: numFont]).width.rounded(.up)
    }()

    static func unitWidth(for text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: unitFont]).width.rounded(.up)
    }

    /// Left inset so that (number + gap + unit) is centred inside a column of `pickerWidth`
    static func leftPad(pickerWidth: CGFloat, unitText: String) -> CGFloat {
        max(0, (pickerWidth - maxNumWidth - gap - unitWidth(for: unitText)) / 2)
    }
}

// MARK: - Public SwiftUI view

struct TimePickerWheelView: View {
    @Binding var duration: TimerDuration

    var body: some View {
        TriplePickerRepresentable(duration: $duration)
            .frame(maxWidth: .infinity)
            .frame(height: PC.wheelFrameHeight)
    }
}

// MARK: - UIViewRepresentable

private struct TriplePickerRepresentable: UIViewRepresentable {
    @Binding var duration: TimerDuration

    func makeCoordinator() -> Coordinator { Coordinator(duration: $duration) }

    func makeUIView(context: Context) -> TriplePickerContainer {
        let v = TriplePickerContainer(coordinator: context.coordinator)
        context.coordinator.container = v
        return v
    }

    func updateUIView(_ view: TriplePickerContainer, context: Context) {
        context.coordinator.duration = $duration
        view.sync(duration: duration)
    }

    // Coordinator holds the Binding so closures always write to the live state
    final class Coordinator {
        var duration: Binding<TimerDuration>
        weak var container: TriplePickerContainer?

        init(duration: Binding<TimerDuration>) { self.duration = duration }

        func set(hours: Int)   { duration.wrappedValue.hours   = hours   }
        func set(minutes: Int) { duration.wrappedValue.minutes = minutes }
        func set(seconds: Int) { duration.wrappedValue.seconds = seconds }
    }
}

// MARK: - Container view

final class TriplePickerContainer: UIView {
    private let hourPicker:   SingleValuePicker
    private let minutePicker: SingleValuePicker
    private let secondPicker: SingleValuePicker
    private let stack:        UIStackView
    private let selectionBg:  UIView

    fileprivate init(coordinator: TriplePickerRepresentable.Coordinator) {
        hourPicker   = SingleValuePicker(unitText: "hour", count: 24)
        minutePicker = SingleValuePicker(unitText: "min",  count: 60)
        secondPicker = SingleValuePicker(unitText: "sec",  count: 60)

        stack = UIStackView(arrangedSubviews: [hourPicker, minutePicker, secondPicker])
        stack.axis         = .horizontal
        stack.distribution = .fillEqually
        stack.spacing      = 0

        selectionBg = UIView()
        selectionBg.backgroundColor = UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1) // system grey6 equivalent
        selectionBg.layer.cornerRadius = 8
        selectionBg.isUserInteractionEnabled = false

        super.init(frame: .zero)

        addSubview(selectionBg)
        addSubview(stack)

        hourPicker.onValueChanged   = { coordinator.set(hours:   $0) }
        minutePicker.onValueChanged = { coordinator.set(minutes: $0) }
        secondPicker.onValueChanged = { coordinator.set(seconds: $0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: PC.wheelFrameHeight)
    }

    func sync(duration: TimerDuration) {
        if hourPicker.selectedRow(inComponent: 0)   != duration.hours   { hourPicker.selectRow(duration.hours,     inComponent: 0, animated: false) }
        if minutePicker.selectedRow(inComponent: 0) != duration.minutes { minutePicker.selectRow(duration.minutes, inComponent: 0, animated: false) }
        if secondPicker.selectedRow(inComponent: 0) != duration.seconds { secondPicker.selectRow(duration.seconds, inComponent: 0, animated: false) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = bounds
        let bgH: CGFloat = 32
        let bgY = (bounds.height - bgH) / 2
        selectionBg.frame = CGRect(x: 0, y: bgY, width: bounds.width, height: bgH)
        sendSubviewToBack(selectionBg)
    }
}

// MARK: - Single-value picker

/// A self-contained UIPickerView for one integer value range.
/// The unit label lives as a direct subview, positioned in the picker's own coordinate system —
/// so there is zero accumulated column-offset error.
final class SingleValuePicker: UIPickerView, UIPickerViewDataSource, UIPickerViewDelegate {
    let unitText: String
    let count:    Int
    var onValueChanged: ((Int) -> Void)?

    private let unitLabel: UILabel = {
        let l = UILabel()
        l.font = PC.unitFont
        l.textColor = .label
        l.isUserInteractionEnabled = false
        return l
    }()

    init(unitText: String, count: Int) {
        self.unitText = unitText
        self.count    = count
        super.init(frame: .zero)
        delegate   = self
        dataSource = self
        backgroundColor = .clear
        unitLabel.text = unitText
        unitLabel.sizeToFit()
        addSubview(unitLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Remove native selection-indicator tints so our container selectionBg shows instead
        for sv in subviews where sv !== unitLabel {
            if sv !== unitLabel { sv.backgroundColor = .clear }
        }

        guard bounds.width > 0 else { return }

        // Position label at the same x the number rows use: lp + maxNumWidth + gap
        let lp  = PC.leftPad(pickerWidth: bounds.width, unitText: unitText)
        let x   = lp + PC.maxNumWidth + PC.gap
        let uw  = PC.unitWidth(for: unitText)
        let uh  = unitLabel.intrinsicContentSize.height
        let y   = (bounds.height - uh) / 2
        unitLabel.frame = CGRect(x: x, y: y, width: uw, height: uh)
        bringSubviewToFront(unitLabel)
    }

    // MARK: UIPickerViewDataSource

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { count }

    // MARK: UIPickerViewDelegate

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 32 }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        pickerView.bounds.width > 0 ? pickerView.bounds.width : 110
    }

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int,
                    forComponent component: Int, reusing view: UIView?) -> UIView {
        let cw       = pickerView.bounds.width > 0 ? pickerView.bounds.width : 110
        let lp       = PC.leftPad(pickerWidth: cw, unitText: unitText)
        let selected = pickerView.selectedRow(inComponent: 0)
        let distance = abs(row - selected)

        let color: UIColor
        switch distance {
        case 0:  color = .label
        case 1:  color = .secondaryLabel
        default: color = .tertiaryLabel
        }

        let numLabel           = UILabel()
        numLabel.text          = "\(row)"
        numLabel.font          = PC.numFont
        numLabel.textColor     = color
        numLabel.textAlignment = .right
        numLabel.frame         = CGRect(x: lp, y: 4, width: PC.maxNumWidth, height: 24)

        let container = UIView(frame: CGRect(x: 0, y: 0, width: cw, height: 32))
        container.backgroundColor = .clear
        container.addSubview(numLabel)
        return container
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        onValueChanged?(row)
        pickerView.reloadComponent(0)
    }
}

// MARK: - Preview

#Preview {
    TimePickerWheelView(duration: .constant(.init(hours: 0, minutes: 7, seconds: 20)))
        .padding()
}
