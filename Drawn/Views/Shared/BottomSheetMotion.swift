import SwiftUI

/// Bottom sheets in `HomeView`: same spring *family* for in and out; dismiss is a bit slower and
/// more damped so the panel doesn’t leave as abruptly as it arrives.
enum BottomSheetMotion {
    static let present = Animation.spring(response: 0.38, dampingFraction: 0.7)
    static let dismiss = Animation.spring(response: 0.52, dampingFraction: 0.78)
}
