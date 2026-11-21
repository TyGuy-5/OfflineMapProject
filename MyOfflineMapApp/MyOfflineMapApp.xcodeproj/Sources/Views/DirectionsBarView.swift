import SwiftUI
import CoreLocation

/// Two-field directions bar interface supporting custom origin, destination, swap, and reset actions.
public struct DirectionsBarView: View {
    @Binding public var originText: String
    @Binding public var destinationText: String
    public let originDisplayName: String
    public let isOriginCurrentLocation: Bool
    public let onSwap: () -> Void
    public let onResetOrigin: () -> Void
    public let onOriginCommit: () -> Void
    public let onDestinationCommit: () -> Void

    public init(
        originText: Binding<String>,
        destinationText: Binding<String>,
        originDisplayName: String,
        isOriginCurrentLocation: Bool,
        onSwap: @escaping () -> Void,
        onResetOrigin: @escaping () -> Void,
        onOriginCommit: @escaping () -> Void,
        onDestinationCommit: @escaping () -> Void
    ) {
        self._originText = originText
        self._destinationText = destinationText
        self.originDisplayName = originDisplayName
        self.isOriginCurrentLocation = isOriginCurrentLocation
        self.onSwap = onSwap
        self.onResetOrigin = onResetOrigin
        self.onOriginCommit = onOriginCommit
        self.onDestinationCommit = onDestinationCommit
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Origin & Destination Inputs Column
                VStack(spacing: 6) {
                    // Origin Field
                    HStack(spacing: 6) {
                        Menu {
                            Button(action: onResetOrigin) {
                                Label("Current Location", systemImage: "location.fill")
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: isOriginCurrentLocation ? "location.fill" : "mappin.circle.fill")
                                    .foregroundColor(isOriginCurrentLocation ? .blue : .green)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .accessibilityLabel("Origin options")

                        TextField("Search origin", text: $originText, onCommit: onOriginCommit)
                            .font(.subheadline)
                            .textFieldStyle(.plain)

                        if !originText.isEmpty {
                            Button(action: {
                                originText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Clear origin")
                        }
                    }
                    .padding(8)
                    #if os(iOS)
                    .background(Color(UIColor.systemGray6))
                    #else
                    .background(Color.gray.opacity(0.15))
                    #endif
                    .cornerRadius(8)

                    // Destination Field
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.red)

                        TextField("Search destination", text: $destinationText, onCommit: onDestinationCommit)
                            .font(.subheadline)
                            .textFieldStyle(.plain)

                        if !destinationText.isEmpty {
                            Button(action: {
                                destinationText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Clear destination")
                        }
                    }
                    .padding(8)
                    #if os(iOS)
                    .background(Color(UIColor.systemGray6))
                    #else
                    .background(Color.gray.opacity(0.15))
                    #endif
                    .cornerRadius(8)
                }

                // Swap Button
                Button(action: onSwap) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Swap origin and destination")
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.systemBackground))
        #else
        .background(Color.white)
        #endif
        .cornerRadius(12)
        .shadow(radius: 3)
    }
}
