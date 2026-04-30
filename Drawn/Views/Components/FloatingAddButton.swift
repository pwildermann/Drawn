import SwiftUI

struct FloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .shadow(radius: 8, y: 4)
        }
        .accessibilityLabel("Add Timer")
    }
}

#Preview {
    FloatingAddButton(action: {})
}
