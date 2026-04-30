import SwiftUI
import UIKit

struct DoodlePlaceholderView: View {
    let data: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill))

            if let image = imageFromData {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.title2)
                    Text("No Doodle")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var imageFromData: UIImage? {
        guard let data else { return nil }
        return UIImage(data: data)
    }
}

#Preview {
    DoodlePlaceholderView(data: nil)
        .frame(width: 160, height: 120)
        .padding()
}
