import SwiftUI
import CoreLocation

#if canImport(MapLibre)
import MapLibre
#endif

/// MapView represents MapLibre's MLNMapView in SwiftUI, coordinating basemap trail restyling,
/// on-demand regional trail overlays, imported GPX track overlays, and user location tracking.
@MainActor
public struct MapView: View {
    @Binding public var visibleBounds: MLNCoordinateBounds?
    public var downloadedRegionURLs: [URL]
    public var importedTrailURLs: [URL]
    public var currentRoute: RouteResponse?
    public var activeGPXTrack: GPXTrack?
    public var originEndpoint: RouteEndpoint
    public var destinationEndpoint: RouteEndpoint?
    public var userLocation: CLLocation?
    public var isTrailNavigationActive: Bool
    
    public init(
        visibleBounds: Binding<MLNCoordinateBounds?>,
        downloadedRegionURLs: [URL] = [],
        importedTrailURLs: [URL] = [],
        currentRoute: RouteResponse? = nil,
        activeGPXTrack: GPXTrack? = nil,
        originEndpoint: RouteEndpoint = .currentLocation,
        destinationEndpoint: RouteEndpoint? = nil,
        userLocation: CLLocation? = nil,
        isTrailNavigationActive: Bool = false
    ) {
        self._visibleBounds = visibleBounds
        self.downloadedRegionURLs = downloadedRegionURLs
        self.importedTrailURLs = importedTrailURLs
        self.currentRoute = currentRoute
        self.activeGPXTrack = activeGPXTrack
        self.originEndpoint = originEndpoint
        self.destinationEndpoint = destinationEndpoint
        self.userLocation = userLocation
        self.isTrailNavigationActive = isTrailNavigationActive
    }
    
    #if canImport(MapLibre) && canImport(UIKit)
    public var body: some View {
        MapLibreRepresentable(
            visibleBounds: $visibleBounds,
            allTrailURLs: downloadedRegionURLs + importedTrailURLs,
            currentRoute: currentRoute,
            activeGPXTrack: activeGPXTrack,
            originEndpoint: originEndpoint,
            destinationEndpoint: destinationEndpoint,
            userLocation: userLocation,
            isTrailNavigationActive: isTrailNavigationActive
        )
    }
    #else
    public var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            VStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("MapLibre Basemap & Trails Overlay")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    #endif
}

#if canImport(MapLibre) && canImport(UIKit)
struct MapLibreRepresentable: UIViewRepresentable {
    @Binding var visibleBounds: MLNCoordinateBounds?
    let allTrailURLs: [URL]
    let currentRoute: RouteResponse?
    let activeGPXTrack: GPXTrack?
    let originEndpoint: RouteEndpoint
    let destinationEndpoint: RouteEndpoint?
    let userLocation: CLLocation?
    let isTrailNavigationActive: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        
        if let styleURL = Bundle.main.url(forResource: "style", withExtension: "json") {
            mapView.styleURL = styleURL
        }
        return mapView
    }
    
    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        
        // 1. Update user tracking mode based on active trail navigation
        if isTrailNavigationActive {
            if uiView.userTrackingMode != .followWithHeading {
                uiView.setUserTrackingMode(.followWithHeading, animated: true, completionHandler: nil)
            }
        }
        
        // 2. Apply combined trail overlay to map style
        if let style = uiView.style {
            TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: allTrailURLs)
            TrailOverlayManager.shared.applyBasemapTrailRestylingSafeguard(to: style)
        }
    }
    
    class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreRepresentable
        
        init(_ parent: MapLibreRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            TrailOverlayManager.shared.applyBasemapTrailRestylingSafeguard(to: style)
            TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: parent.allTrailURLs)
        }
        
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.visibleBounds = mapView.visibleCoordinateBounds
            }
        }
    }
}
#endif
