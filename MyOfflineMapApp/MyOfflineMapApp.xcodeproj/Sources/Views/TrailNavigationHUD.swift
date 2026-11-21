import SwiftUI

/// Overlay HUD displayed during active trail navigation, presenting real-time remaining distance,
/// current elevation, off-trail warning alerts, and a button to terminate navigation.
public struct TrailNavigationHUD: View {
    @ObservedObject public var navigator: TrailNavigator
    public var onStopNavigation: (() -> Void)?
    
    public init(navigator: TrailNavigator, onStopNavigation: (() -> Void)? = nil) {
        self.navigator = navigator
        self.onStopNavigation = onStopNavigation
    }
    
    private var formattedRemainingDistance: String {
        let remaining = navigator.remainingDistance
        if remaining >= 1000.0 {
            return String(format: "%.1f km", remaining / 1000.0)
        } else {
            return "\(Int(remaining)) m"
        }
    }
    
    private var formattedElevation: String {
        if let ele = navigator.currentElevation {
            return "\(Int(ele)) m"
        } else {
            return "-- m"
        }
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Off-Trail Alert Banner
            if navigator.isOffTrail {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text("OFF TRAIL (\(Int(navigator.crossTrackDeviation))m deviation)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.red)
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Primary Metrics Container
            HStack(alignment: .center, spacing: 16) {
                // Metric 1: Remaining Distance
                VStack(alignment: .leading, spacing: 2) {
                    Text("REMAINING")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(formattedRemainingDistance)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Divider()
                    .frame(height: 36)
                
                // Metric 2: Elevation
                VStack(alignment: .leading, spacing: 2) {
                    Text("ELEVATION")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(formattedElevation)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Action: Stop Navigation Button
                Button(action: {
                    navigator.stopNavigation()
                    onStopNavigation?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Stop Navigation")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal)
    }
}
