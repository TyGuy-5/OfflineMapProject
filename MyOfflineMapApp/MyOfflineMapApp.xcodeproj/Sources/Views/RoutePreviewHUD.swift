import SwiftUI
import CoreLocation

/// Banner HUD shown when the origin point is remote (>200m) and the app is in Route Preview Mode.
public struct RoutePreviewHUD: View {
    public let originName: String
    public let onNavigateToStart: () -> Void
    public let onDismiss: () -> Void

    public init(
        originName: String,
        onNavigateToStart: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.originName = originName
        self.onNavigateToStart = onNavigateToStart
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .foregroundColor(.white)
                    .font(.subheadline.bold())
                Text("Route Preview Mode")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.8))
                        .padding(4)
                }
            }

            Text("Previewing route from \(originName). Live GPS guidance will activate when within 200m of the starting point.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))

            HStack {
                Button(action: onNavigateToStart) {
                    Label("Route to Start", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        )
        .padding(.horizontal)
    }
}
