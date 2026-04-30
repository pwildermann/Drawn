import SwiftUI

struct TimerGridItemView: View {
    let timer: DrawnTimer
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            DoodlePlaceholderView(data: timer.doodleData)
                .frame(height: 120)

            Text(timer.name)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    Text(timer.duration.displayText)
                        .font(.subheadline.monospacedDigit())
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    TimerGridItemView(
        timer: .init(name: "Tea", duration: .init(hours: 0, minutes: 3, seconds: 0)),
        onToggle: {}
    )
    .padding()
}
