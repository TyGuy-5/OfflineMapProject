import SwiftUI
import CoreLocation

#if canImport(MapLibre)
import MapLibre
#endif

/// Main application view harmonizing MapView, DirectionsBarView, RoutePreviewHUD,
/// TrailNavigationHUD, ElevationProfileView, RegionalTrailsSheet, and TrailListView.
@MainActor
public struct ContentView: View {
    // MARK: - State Objects
    @StateObject private var navigationViewModel = NavigationViewModel()
    @StateObject private var trailManager = TrailManager(autoScan: true)
    @StateObject private var trailNavigator = TrailNavigator(
        audioAlertService: TrailAudioAlertService(),
        locationManager: LocationManager.shared
    )
    @ObservedObject private var locationManager = LocationManager.shared
    
    // MARK: - Local UI State
    @State private var isShowingDirectionsBar: Bool = false
    @State private var isShowingRegionalTrailsSheet: Bool = false
    @State private var isShowingTrailListSheet: Bool = false
    @State private var isShowingElevationProfile: Bool = true
    @State private var visibleMapBounds: MLNCoordinateBounds? = nil
    @State private var downloadedRegionURLs: [URL] = []
    @State private var searchService = SearchService()
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Layer 0: MapView (Full-Screen Basemap & Overlays)
            MapView(
                visibleBounds: $visibleMapBounds,
                downloadedRegionURLs: downloadedRegionURLs,
                importedTrailURLs: trailManager.allTrailGeoJSONURLs(),
                currentRoute: navigationViewModel.currentRoute,
                activeGPXTrack: trailNavigator.activeTrack,
                originEndpoint: navigationViewModel.originEndpoint,
                destinationEndpoint: navigationViewModel.destinationEndpoint,
                userLocation: locationManager.currentLocation,
                isTrailNavigationActive: trailNavigator.activeTrack != nil
            )
            .ignoresSafeArea()
            
            // Layer 1: Floating HUDs & Controls
            VStack(spacing: 8) {
                // Top HUD: DirectionsBarView (Mode A: Road Route Planning)
                if isShowingDirectionsBar && trailNavigator.activeTrack == nil {
                    DirectionsBarView(
                        originText: $navigationViewModel.originText,
                        destinationText: $navigationViewModel.destinationText,
                        originDisplayName: navigationViewModel.originEndpoint.displayName,
                        isOriginCurrentLocation: navigationViewModel.originEndpoint.isCurrentLocation,
                        onSwap: {
                            navigationViewModel.swapOriginDestination()
                        },
                        onResetOrigin: {
                            navigationViewModel.resetOriginToCurrentLocation()
                        },
                        onOriginCommit: {
                            Task {
                                await resolveSearch(query: navigationViewModel.originText, isOrigin: true)
                            }
                        },
                        onDestinationCommit: {
                            Task {
                                await resolveSearch(query: navigationViewModel.destinationText, isOrigin: false)
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Top HUD: RoutePreviewHUD (When origin is remote >200m)
                if navigationViewModel.isRoutePreviewMode && trailNavigator.activeTrack == nil {
                    RoutePreviewHUD(
                        originName: navigationViewModel.originEndpoint.displayName,
                        onNavigateToStart: {
                            navigationViewModel.routeToStart()
                        },
                        onDismiss: {
                            navigationViewModel.isRoutePreviewMode = false
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Bottom HUD: Trail Navigation & Elevation Profile (Mode B: Active Trail Navigation)
                if let activeTrack = trailNavigator.activeTrack {
                    VStack(spacing: 8) {
                        // Elevation Profile Chart (Collapsible)
                        if isShowingElevationProfile {
                            ElevationProfileView(
                                points: activeTrack.points,
                                userProgressDistance: trailNavigator.userProgressDistance,
                                currentElevation: trailNavigator.currentElevation
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // Active Navigation HUD
                        TrailNavigationHUD(
                            navigator: trailNavigator,
                            onStopNavigation: {
                                trailNavigator.stopNavigation()
                            }
                        )
                    }
                    .padding(.bottom, 16)
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.25), value: isShowingDirectionsBar)
            .animation(.easeInOut(duration: 0.25), value: navigationViewModel.isRoutePreviewMode)
            .animation(.easeInOut(duration: 0.25), value: trailNavigator.activeTrack != nil)
            .animation(.easeInOut(duration: 0.25), value: isShowingElevationProfile)
            
            // Layer 2: Floating Action Buttons (Right Margin)
            VStack(spacing: 12) {
                Spacer()
                
                // Directions / Route Planning Toggle
                Button {
                    withAnimation {
                        isShowingDirectionsBar.toggle()
                    }
                } label: {
                    Image(systemName: isShowingDirectionsBar ? "xmark" : "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Toggle Directions")
                
                // Regional Trails Downloader Sheet
                Button {
                    isShowingRegionalTrailsSheet = true
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.orange)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Download Regional Trails")
                
                // GPX Trail Manager Sheet
                Button {
                    isShowingTrailListSheet = true
                } label: {
                    Image(systemName: "figure.hiking")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.green)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("GPX Trails")
                
                // Recenter GPS Button
                Button {
                    // Recenter on user's current GPS location
                    if let _ = locationManager.currentLocation {
                        // Triggers user tracking or view recenter
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Recenter")
                
                // Elevation Toggle (Visible only during active trail navigation)
                if trailNavigator.activeTrack != nil {
                    Button {
                        withAnimation {
                            isShowingElevationProfile.toggle()
                        }
                    } label: {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(isShowingElevationProfile ? Color.purple : Color.gray)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .accessibilityLabel("Toggle Elevation Profile")
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, trailNavigator.activeTrack != nil ? 180 : 32)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Sheets
        .sheet(isPresented: $isShowingRegionalTrailsSheet) {
            RegionalTrailsSheet(
                visibleBounds: visibleMapBounds,
                downloader: .shared,
                onTrailsUpdated: { files in
                    self.downloadedRegionURLs = files
                }
            )
        }
        .sheet(isPresented: $isShowingTrailListSheet) {
            TrailListView(
                trailManager: trailManager,
                selectedTrail: trailNavigator.activeTrack,
                onSelectTrail: { track in
                    isShowingTrailListSheet = false
                    isShowingDirectionsBar = false
                    navigationViewModel.currentRoute = nil
                    trailNavigator.startNavigation(track: track)
                },
                onDismiss: {
                    isShowingTrailListSheet = false
                }
            )
        }
        .task {
            // Load initial downloaded regions
            self.downloadedRegionURLs = await RegionalTrailDownloader.shared.listDownloadedRegions()
        }
        .onReceive(locationManager.$currentLocation) { newLoc in
            guard let loc = newLoc else { return }
            if trailNavigator.activeTrack != nil {
                _ = trailNavigator.updateLocation(loc)
            } else if navigationViewModel.currentRoute != nil {
                navigationViewModel.handleLocationUpdate(loc)
            }
        }
    }
    
    // MARK: - Search Resolution
    private func resolveSearch(query: String, isOrigin: Bool) async {
        let results = await searchService.search(query: query)
        guard let first = results.first else { return }
        let place = PlaceLocation(id: first.id, name: first.title, subtitle: first.subtitle, coordinate: first.coordinate)
        if isOrigin {
            navigationViewModel.originEndpoint = .custom(place: place)
        } else {
            navigationViewModel.destinationEndpoint = .custom(place: place)
        }
        await navigationViewModel.calculateRoute()
    }
}
