import SwiftUI
#if canImport(Charts)
import Charts
#endif

/// A SwiftUI view rendering a high-contrast elevation profile along a trail's distance,
/// highlighting the user's active progress marker and gracefully handling tracks with nil elevation.
public struct ElevationProfileView: View {
    public let points: [GPXTrackPoint]
    public let userProgressDistance: Double
    public let currentElevation: Double?
    
    public init(
        points: [GPXTrackPoint],
        userProgressDistance: Double = 0.0,
        currentElevation: Double? = nil
    ) {
        self.points = points
        self.userProgressDistance = userProgressDistance
        self.currentElevation = currentElevation
    }
    
    private struct ElevationSample: Identifiable {
        let id: Int
        let distanceMeters: Double
        let elevationMeters: Double
    }
    
    private var validSamples: [ElevationSample] {
        var samples: [ElevationSample] = []
        for (idx, pt) in points.enumerated() {
            if let ele = pt.elevation {
                samples.append(ElevationSample(id: idx, distanceMeters: pt.cumulativeDistance, elevationMeters: ele))
            }
        }
        return samples
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Elevation Profile", systemImage: "chart.xyaxis.line")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let ele = currentElevation {
                    Text("\(Int(ele)) m")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            
            if validSamples.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mountain.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Elevation data not available for this trail")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(8)
            } else {
                #if canImport(Charts)
                Chart {
                    ForEach(validSamples) { sample in
                        AreaMark(
                            x: .value("Distance (km)", sample.distanceMeters / 1000.0),
                            y: .value("Elevation (m)", sample.elevationMeters)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.6), Color.orange.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        LineMark(
                            x: .value("Distance (km)", sample.distanceMeters / 1000.0),
                            y: .value("Elevation (m)", sample.elevationMeters)
                        )
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    
                    if let userEle = currentElevation, userProgressDistance >= 0 {
                        RuleMark(x: .value("User Position", userProgressDistance / 1000.0))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(Color.blue)
                        
                        PointMark(
                            x: .value("User Position", userProgressDistance / 1000.0),
                            y: .value("User Elevation", userEle)
                        )
                        .symbolSize(60)
                        .foregroundStyle(Color.blue)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text(String(format: "%.1f km", km))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let ele = value.as(Double.self) {
                                Text("\(Int(ele))m")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 120)
                #else
                // Fallback geometry drawing when Charts is not imported
                Canvas { context, size in
                    let path = Path { _ in }
                    context.stroke(path, with: .color(.orange), lineWidth: 2)
                }
                .frame(height: 120)
                #endif
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }
}
