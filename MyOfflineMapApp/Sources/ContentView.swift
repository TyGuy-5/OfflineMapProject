import SwiftUI
import CoreLocation

enum MapAppMode: Equatable {
    case explore
    case searchList
    case placeDetail
    case routePreview
    case navigation
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()

    // Mode state
    @State private var appMode: MapAppMode = .explore
    @State private var selectedPlace: SearchResult?
    @State var routeDetails: RouteDetails?
    @State private var selectedTravelMode: String = "auto"
    @State private var showStepsSheet = false
    @State private var showAttributionAlert = false
    @State private var isHudMode = false // Windshield HUD Reflection Mode
    @State var useMetric = false // mph vs km/h

    // Search state
    @State private var destinationText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State var searchTask: Task<Void, Never>?

    // Map bindings
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D]?
    @State var simulatedUserCoordinate: CLLocationCoordinate2D?
    @State private var userLocationCenter: CLLocationCoordinate2D?
    @State private var simulatedHeading: Double?
    @State private var zoomStep: Double?

    // Navigation & simulation state
    @State var isNavigating = false
    @State var isSimulating = false
    @State private var simulationTimer: Timer?
    @State var currentStepIndex = 0
    @State var currentCoordIndex = 0
    @State private var simulatedSpeedMph: Int = 0
    @State private var simulationSpeedMultiplier: Double = 1.0
    @State private var isVoiceMuted = false
    @State var isProgrammaticTextChange = false
    @State private var isRecalculating = false
    @State private var lastRerouteTime = Date.distantPast
    @State private var activeRouteRequestId: UUID? = nil
    @State var remainingStepDistanceMiles: Double = 0.0
    @State private var remainingRouteDistanceMiles: Double = 0.0
    @State private var remainingRouteDurationSeconds: Double = 0.0
    @State private var dynamicArrivalDate: Date = Date()
    @State private var hasAnnouncedAdvanceTurn = false

    private static let hudEtaFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    func formatCountdownDistance(_ miles: Double, useMetric: Bool) -> String {
        if useMetric {
            let meters = miles * 1609.34
            if meters < 1000 {
                return "\(max(0, Int(meters))) m"
            } else {
                return String(format: "%.1f km", max(0, miles * 1.60934))
            }
        } else {
            let feet = miles * 5280
            if miles < 0.1 {
                return "\(max(0, Int(feet))) ft"
            } else {
                return String(format: "%.1f mi", max(0, miles))
            }
        }
    }

    var formattedRemainingDuration: String {
        let minutes = Int(remainingRouteDurationSeconds / 60)
        if minutes < 60 {
            return "\(max(1, minutes)) min"
        } else {
            let hours = minutes / 60
            let remMin = minutes % 60
            return "\(hours) hr \(remMin) min"
        }
    }

    var formattedRemainingETA: String {
        ContentView.hudEtaFormatter.string(from: dynamicArrivalDate)
    }

    // Alerts
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isMapDataMissing: Bool = false

    // Services
    @StateObject private var searchService = SearchService()
    @StateObject private var routingService = RoutingService()

    // Live Telemetry
    var displaySpeed: Int {
        if isSimulating {
            return useMetric ? Int(Double(simulatedSpeedMph) * 1.60934) : simulatedSpeedMph
        }
        return useMetric ? locationManager.smoothedSpeedKmh : locationManager.smoothedSpeedMph
    }

    var speedUnit: String {
        useMetric ? "km/h" : "mph"
    }

    var altitudeValue: Int {
        let alt = locationManager.location?.altitude ?? 0
        return useMetric ? Int(alt) : Int(alt * 3.28084)
    }

    var altitudeUnit: String {
        useMetric ? "m" : "ft"
    }

    static let defaultAlaskaCoordinate = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)

    func isWithinSupportedRegion(_ coord: CLLocationCoordinate2D) -> Bool {
        return coord.latitude >= 51.0 && coord.latitude <= 72.0 &&
               coord.longitude >= -179.0 && coord.longitude <= -129.0
    }

    var effectiveUserCoordinate: CLLocationCoordinate2D {
        if let sim = simulatedUserCoordinate { return sim }
        if let user = locationManager.location?.coordinate, isWithinSupportedRegion(user) {
            return user
        }
        return ContentView.defaultAlaskaCoordinate
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background Map
            MapView(
                pmtilesURL: OfflineDataManager.url(for: "north-america.pmtiles"),
                destinationTitle: selectedPlace?.name ?? destinationText,
                selectedCoordinate: $selectedCoordinate,
                routeCoordinates: $routeCoordinates,
                simulatedUserCoordinate: $simulatedUserCoordinate,
                userLocationCenter: $userLocationCenter,
                zoomStep: $zoomStep,
                simulatedHeading: simulatedHeading,
                isNavigating: isNavigating,
                mapStyleName: "standard",
                onMapTap: {
                    if appMode == .searchList {
                        dismissSearch()
                    }
                },
                onLongPressCoordinate: { coord in
                    handleMapLongPress(at: coord)
                }
            )
            .ignoresSafeArea()

            // HUD Windshield Mirroring Overlay (when active)
            if isHudMode {
                hudWindshieldView
                    .transition(.opacity)
            } else {
                // Regular Google Maps UI
                VStack(spacing: 0) {
                    if isNavigating {
                        navigationTopBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        topSearchHeader
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    statusAlertBanner

                    if appMode == .searchList && !searchResults.isEmpty {
                        searchResultsDropdown
                            .transition(.opacity)
                    }

                    Spacer()

                    bottomControlsArea
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appMode)
        .animation(.easeInOut(duration: 0.25), value: isNavigating)
        .animation(.easeInOut(duration: 0.25), value: isHudMode)
        .sheet(isPresented: $showStepsSheet) {
            if let details = routeDetails {
                NavigationStepsSheet(routeDetails: details, currentStepIndex: currentStepIndex, useMetric: useMetric)
            }
        }
        .task {
            let pmtilesPath = OfflineDataManager.url(for: "north-america.pmtiles").path
            self.isMapDataMissing = !FileManager.default.fileExists(atPath: pmtilesPath)
        }
        .alert("Notice", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .alert("Map Data & Open-Source Licensing", isPresented: $showAttributionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("• Map Data: © OpenStreetMap contributors (ODbL 1.0) & © OpenMapTiles (CC-BY 4.0)\n• Rendering: MapLibre GL Native (BSD 2-Clause)\n• Routing: Valhalla (MIT)\n• Database: SQLite.swift (MIT)\n• Terrain: Natural Earth (Public Domain)\n\nAll data and algorithms operate 100% offline. See THIRD_PARTY_NOTICES.md for complete copyright and license details.")
        }
        .onReceive(locationManager.$location) { newLoc in
            handleLocationUpdate(newLoc)
        }
        .onChange(of: useMetric) { _, _ in
            if !isNavigating && !isSimulating {
                if let dest = selectedCoordinate, routeDetails != nil {
                    let place = selectedPlace ?? SearchResult(id: 0, name: destinationText, lat: dest.latitude, lon: dest.longitude)
                    calculateRouteTo(place)
                }
            }
        }
        .onDisappear {
            endNavigation()
        }
    }

    // MARK: - 1. Top Search Header (Google Maps Style)
    private var topSearchHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if appMode == .placeDetail || appMode == .routePreview || appMode == .searchList {
                    Button(action: resetToExplore) {
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(8)
                    }
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.leading, 6)
                }

                TextField("Search here", text: $destinationText)
                    .font(.body)
                    .autocorrectionDisabled()
                    .onChange(of: destinationText) { _, newValue in
                        if isProgrammaticTextChange {
                            isProgrammaticTextChange = false
                            return
                        }
                        if let place = selectedPlace, place.name == newValue {
                            return
                        }
                        handleQueryChange(newValue)
                    }
                    .onSubmit {
                        if !searchResults.isEmpty {
                            selectPlace(searchResults[0])
                        }
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 4)
                } else if !destinationText.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .cornerRadius(28)
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // Category Chips Carousel
            if appMode == .explore || appMode == .searchList {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(icon: "fuelpump.fill", title: "Gas", color: .orange) {
                            searchCategory("Gas")
                        }
                        CategoryChip(icon: "cup.and.saucer.fill", title: "Coffee", color: .brown) {
                            searchCategory("Coffee")
                        }
                        CategoryChip(icon: "fork.knife", title: "Restaurants", color: .red) {
                            searchCategory("Restaurant")
                        }
                        CategoryChip(icon: "cart.fill", title: "Groceries", color: .green) {
                            searchCategory("Market")
                        }
                        CategoryChip(icon: "parkingsign.circle.fill", title: "Parking", color: .blue) {
                            searchCategory("Parking")
                        }
                        CategoryChip(icon: "bed.double.fill", title: "Hotels", color: .purple) {
                            searchCategory("Hotel")
                        }
                        CategoryChip(icon: "cross.case.fill", title: "Hospitals", color: .pink) {
                            searchCategory("Hospital")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Status & Hardware Alerts Banner (No GPS / Wi-Fi iPad / Missing Data)
    @ViewBuilder
    private var statusAlertBanner: some View {
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .foregroundColor(.orange)
                Text("Location Access Disabled. Tap to open Settings.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .onTapGesture {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } else if locationManager.accuracyAuthorization == .reducedAccuracy {
            HStack(spacing: 8) {
                Image(systemName: "location.circle")
                    .foregroundColor(.blue)
                Text("Approximate location only. Tap for precision.")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .onTapGesture {
                locationManager.requestPreciseLocation()
            }
        } else if locationManager.isGpsSignalLow && !isSimulating {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(.orange)
                Text("Weak GPS Signal / Wi-Fi Device")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } else if isMapDataMissing {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text("Offline map archive missing. Drag PMTiles into Files.")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } else if let user = locationManager.location?.coordinate, !isWithinSupportedRegion(user) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.blue)
                Text("Simulated Location: Fairbanks, AK (Offline Region)")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - 2. Search Results List
    private var searchResultsDropdown: some View {
        List(searchResults) { result in
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 38, height: 38)
                    Image(systemName: result.iconName)
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(result.formattedDistance(from: effectiveUserCoordinate, useMetric: useMetric))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                selectPlace(result)
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 280)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - 3. Active Turn-by-Turn Top Banner (Google Maps Dark Green)
    private var navigationTopBanner: some View {
        VStack(spacing: 0) {
            let step = currentNavigationStep
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: step.iconName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(formatCountdownDistance(remainingStepDistanceMiles, useMetric: useMetric))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                    Text(step.instruction)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineLimit(2)
                }

                Spacer()

                // Voice Mute Toggle
                Button(action: {
                    isVoiceMuted.toggle()
                    routingService.isVoiceMuted = isVoiceMuted
                    if isVoiceMuted {
                        routingService.stopVoice()
                    }
                }) {
                    Image(systemName: isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }

                // Exit Navigation
                Button(action: endNavigation) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(red: 0.05, green: 0.42, blue: 0.22))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    private var currentNavigationStep: NavigationStep {
        guard let steps = routeDetails?.steps, !steps.isEmpty else {
            return NavigationStep(
                instruction: "Proceed along route",
                distanceMiles: 0.5,
                durationSeconds: 60,
                maneuverType: 1,
                streetName: nil,
                startIndex: 0,
                endIndex: 1
            )
        }
        let safeIndex = min(currentStepIndex, steps.count - 1)
        return steps[safeIndex]
    }

    // MARK: - 4. Bottom Controls Area
    private var bottomControlsArea: some View {
        VStack(spacing: 12) {
            // Floating Right Map Controls
            if !isNavigating {
                HStack {
                    // Attribution pill (ODbL License compliance)
                    Button(action: { showAttributionAlert = true }) {
                        Text("© OSM")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemBackground).opacity(0.85))
                            .cornerRadius(10)
                    }
                    .padding(.leading, 16)

                    Spacer()

                    VStack(spacing: 10) {
                        // Zoom in / out buttons
                        VStack(spacing: 0) {
                            Button(action: { zoomStep = 1.0 }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 38)
                            }
                            Divider()
                                .frame(width: 28)
                            Button(action: { zoomStep = -1.0 }) {
                                Image(systemName: "minus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 38)
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Color.black.opacity(0.15), radius: 4)

                        // Units toggle (mph / km/h)
                        Button(action: { useMetric.toggle() }) {
                            Text(useMetric ? "KM" : "MI")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.15), radius: 4)
                        }

                        // Recenter on user
                        Button(action: recenterOnUser) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.15), radius: 4)
                        }
                    }
                    .padding(.trailing, 16)
                }
            }

            switch appMode {
            case .explore, .searchList:
                exploreBottomBar
            case .placeDetail:
                placeDetailCard
            case .routePreview:
                routePreviewCard
            case .navigation:
                navigationBottomHUD
            }
        }
        .padding(.bottom, 20)
    }

    private var exploreBottomBar: some View {
        HStack(spacing: 12) {
            DashboardGauge(title: "SPEED", value: "\(displaySpeed)", unit: speedUnit)
            DashboardGauge(title: "ALT", value: "\(altitudeValue)", unit: altitudeUnit)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var placeDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let place = selectedPlace {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Text(place.formattedDistance(from: effectiveUserCoordinate, useMetric: useMetric))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: resetToExplore) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: { calculateRouteTo(place) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            Text("Directions").bold()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(24)
                    }

                    Button(action: {
                        calculateRouteTo(place) {
                            self.startNavigation()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Start").bold()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.1, green: 0.6, blue: 0.3))
                        .cornerRadius(24)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private var routePreviewCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 24) {
                TravelModeTab(icon: "car.fill", title: "Drive", isSelected: selectedTravelMode == "auto") {
                    switchTravelMode("auto")
                }
                TravelModeTab(icon: "figure.walk", title: "Walk", isSelected: selectedTravelMode == "pedestrian") {
                    switchTravelMode("pedestrian")
                }
                TravelModeTab(icon: "bicycle", title: "Bike", isSelected: selectedTravelMode == "bicycle") {
                    switchTravelMode("bicycle")
                }
            }
            .padding(.top, 4)

            Divider()

            if let details = routeDetails {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(details.formattedDuration)
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundColor(Color(red: 0.05, green: 0.6, blue: 0.25))
                            Text(details.formattedDistance(useMetric: useMetric))
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        Text("Arrive by \(details.formattedETA)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button(action: startNavigation) {
                        HStack(spacing: 6) {
                            Image(systemName: "location.north.fill")
                            Text("Start").bold()
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.1, green: 0.6, blue: 0.3))
                        .cornerRadius(26)
                    }

                    Button(action: startSimulatedDrive) {
                        HStack(spacing: 6) {
                            Image(systemName: "car.fill")
                            Text("Simulate")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(26)
                    }

                    Button(action: { showStepsSheet = true }) {
                        Image(systemName: "list.bullet")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Calculating fastest offline route...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(18)
        .background(Color(.systemBackground))
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private var navigationBottomHUD: some View {
        VStack(spacing: 10) {
            if routeDetails != nil {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(formattedRemainingDuration)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Color(red: 0.05, green: 0.6, blue: 0.25))
                            Text("• \(formatCountdownDistance(remainingRouteDistanceMiles, useMetric: useMetric))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("ETA \(formattedRemainingETA)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // HUD Mirror Mode Toggle
                    Button(action: { isHudMode.toggle() }) {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }

                    // Speedometer Badge
                    HStack(spacing: 4) {
                        Text("\(displaySpeed)")
                            .font(.system(size: 20, weight: .heavy))
                        Text(speedUnit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Steps Drawer Button
                    Button(action: { showStepsSheet = true }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }

                    // Exit Navigation Button
                    Button(action: endNavigation) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }

                if isSimulating {
                    HStack(spacing: 8) {
                        Text("Simulation Demo:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        SimulationSpeedButton(label: "1x", isSelected: simulationSpeedMultiplier == 1.0) {
                            simulationSpeedMultiplier = 1.0
                        }
                        SimulationSpeedButton(label: "2x", isSelected: simulationSpeedMultiplier == 2.0) {
                            simulationSpeedMultiplier = 2.0
                        }
                        SimulationSpeedButton(label: "5x", isSelected: simulationSpeedMultiplier == 5.0) {
                            simulationSpeedMultiplier = 5.0
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    // MARK: - 5. HUD Windshield Reflection Mode (Pure OLED Black & Flipped)
    private var hudWindshieldView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                HStack {
                    Spacer()
                    Button(action: { isHudMode = false }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                    }
                }

                Spacer()

                let step = currentNavigationStep
                Image(systemName: step.iconName)
                    .font(.system(size: 100, weight: .bold))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))

                Text(formatCountdownDistance(remainingStepDistanceMiles, useMetric: useMetric))
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundColor(.white)

                Text(step.instruction)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal)

                HStack(spacing: 40) {
                    VStack {
                        Text("\(displaySpeed)")
                            .font(.system(size: 64, weight: .black))
                            .foregroundColor(.white)
                        Text(speedUnit.uppercased())
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    if routeDetails != nil {
                        VStack {
                            Text(formattedRemainingETA)
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.green)
                            Text("ARRIVAL")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    }
                }

                Spacer()
            }
            .scaleEffect(x: -1.0, y: 1.0) // Horizontally mirror for windshield reflection
        }
    }

    // MARK: - Logic & Actions

    func handleLocationUpdate(_ location: CLLocation?) {
        guard let location = location, isNavigating, let details = routeDetails, let coords = routeCoordinates else { return }

        // Skip off-route checks during simulation
        if isSimulating {
            return
        }

        // Ignore out-of-region fixes to avoid overriding Alaska fallback and breaking rerouting
        guard isWithinSupportedRegion(location.coordinate) else { return }

        // Live real GPS driving updates
        simulatedUserCoordinate = location.coordinate
        if location.course >= 0 {
            simulatedHeading = location.course
        } else if locationManager.heading >= 0 {
            simulatedHeading = locationManager.heading
        }

        // Step progression along route maneuvers & live countdown telemetry
        updateCurrentStepForLiveLocation(location.coordinate, in: details)

        // Off-route check with in-progress guard and cooldown
        guard !isRecalculating else { return }
        let now = Date()
        guard now.timeIntervalSince(lastRerouteTime) > 7.0 else { return }

        // Scale threshold by horizontal accuracy (at least 40m, up to 75m in urban canyons)
        let baseThreshold = 40.0
        let accuracySlack = max(0.0, location.horizontalAccuracy - 20.0)
        let effectiveThreshold = min(75.0, baseThreshold + accuracySlack)

        let isOff = routingService.isUserOffRoute(
            userLocation: location.coordinate,
            routeCoordinates: coords,
            thresholdMeters: effectiveThreshold,
            activeCoordIndex: currentCoordIndex
        )
        if isOff, let dest = selectedCoordinate {
            print("ContentView: Off-route detected! Recalculating route...")
            lastRerouteTime = now
            routingService.speakTurnInstruction("Recalculating route.", force: true)
            recalculateActiveRoute(to: dest)
        }
    }

    func updateCurrentStepForLiveLocation(_ userCoord: CLLocationCoordinate2D, in details: RouteDetails) {
        let coords = details.coordinates
        guard !coords.isEmpty else { return }

        // Live arrival check at destination
        if let finalDest = coords.last, coords.count >= 2 {
            let distToFinalDest = segmentDistanceMeters(p1: userCoord, p2: finalDest)
            let isNearEnd = currentCoordIndex >= max(0, coords.count - 3) || (!details.steps.isEmpty && currentStepIndex >= details.steps.count - 1)
            if distToFinalDest < 25.0 || (isNearEnd && distToFinalDest < 40.0) {
                routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
                endNavigation()
                return
            }
        }

        // Keep currentCoordIndex advancing along the polyline smoothly
        let searchStart = max(0, currentCoordIndex - 5)
        let searchEnd = min(coords.count - 1, currentCoordIndex + 50)
        var closestIndex = currentCoordIndex
        var minSegDist = Double.greatestFiniteMagnitude

        for i in searchStart..<searchEnd {
            let dist = routingService.distanceToSegmentMeters(p: userCoord, a: coords[i], b: coords[i + 1])
            if dist < minSegDist {
                minSegDist = dist
                closestIndex = i
            }
        }
        if minSegDist < 40.0 {
            currentCoordIndex = closestIndex
        }

        // Step progression along maneuvers
        if !details.steps.isEmpty && currentStepIndex < details.steps.count {
            let currentStep = details.steps[currentStepIndex]
            let endCoord = coords[min(currentStep.endIndex, coords.count - 1)]
            let distToEndMeters = segmentDistanceMeters(p1: userCoord, p2: endCoord)

            if distToEndMeters < 35.0 && currentStepIndex < details.steps.count - 1 {
                currentStepIndex += 1
                hasAnnouncedAdvanceTurn = false
                currentCoordIndex = max(currentCoordIndex, currentStep.endIndex)
                let nextStep = details.steps[currentStepIndex]
                routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
            } else if currentStepIndex < details.steps.count - 1 && !hasAnnouncedAdvanceTurn && distToEndMeters < 250.0 {
                hasAnnouncedAdvanceTurn = true
                let nextStep = details.steps[currentStepIndex + 1]
                let distStr = formatCountdownDistance(distToEndMeters * 0.000621371, useMetric: useMetric)
                routingService.speakTurnInstruction("In \(distStr), \(nextStep.instruction)", stepId: (currentStepIndex + 1) * 10 + 1)
            }
        }

        updateNavigationTelemetry(at: userCoord, coordIndex: currentCoordIndex, in: details)
    }

    func updateNavigationTelemetry(at userCoord: CLLocationCoordinate2D, coordIndex: Int, in details: RouteDetails) {
        let coords = details.coordinates
        guard coords.count >= 2 else { return }
        let clampedIndex = min(max(0, coordIndex), coords.count - 1)

        // 1. Calculate remaining step distance (monotonically counting down)
        let currentStep: NavigationStep? = (currentStepIndex < details.steps.count) ? details.steps[currentStepIndex] : details.steps.last
        if let currentStep = currentStep {
            let stepEnd = min(currentStep.endIndex, coords.count - 1)
            var stepDistMeters = 0.0
            if clampedIndex < stepEnd {
                stepDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
                if clampedIndex + 1 < stepEnd {
                    for i in (clampedIndex + 1)..<stepEnd {
                        stepDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                    }
                }
            } else {
                stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd])
            }
            self.remainingStepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
        } else {
            self.remainingStepDistanceMiles = 0.0
        }

        // 2. Calculate remaining total route distance (monotonically counting down)
        var routeDistMeters = 0.0
        if clampedIndex < coords.count - 1 {
            routeDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
            if clampedIndex + 1 < coords.count - 1 {
                for i in (clampedIndex + 1)..<(coords.count - 1) {
                    routeDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                }
            }
        } else if let last = coords.last {
            routeDistMeters = segmentDistanceMeters(p1: userCoord, p2: last)
        }
        let routeMiles = max(0.0, routeDistMeters * 0.000621371)
        self.remainingRouteDistanceMiles = routeMiles

        // 3. Proportionally update remaining duration and ETA
        if details.totalDistanceMiles > 0 {
            let ratio = max(0.0, min(1.0, routeMiles / details.totalDistanceMiles))
            self.remainingRouteDurationSeconds = details.totalDurationSeconds * ratio
        } else {
            self.remainingRouteDurationSeconds = 0
        }
        self.dynamicArrivalDate = Date().addingTimeInterval(self.remainingRouteDurationSeconds)
    }

    private func segmentDistanceMeters(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D) -> Double {
        let latRad = p1.latitude * .pi / 180.0
        let dx = (p2.longitude - p1.longitude) * 111320.0 * cos(latRad)
        let dy = (p2.latitude - p1.latitude) * 110540.0
        return sqrt(dx * dx + dy * dy)
    }

    private func recalculateActiveRoute(to dest: CLLocationCoordinate2D) {
        guard isNavigating && !isRecalculating else { return }
        isRecalculating = true
        let start = effectiveUserCoordinate
        let travelMode = selectedTravelMode
        let metric = useMetric
        let reqId = UUID()
        self.activeRouteRequestId = reqId
        let router = routingService

        DispatchQueue.global(qos: .userInitiated).async {
            let details = router.calculateRoute(from: start, to: dest, mode: travelMode, useMetric: metric)
            DispatchQueue.main.async {
                defer { self.isRecalculating = false }
                guard self.isNavigating && self.activeRouteRequestId == reqId else { return }
                if let details = details, !details.coordinates.isEmpty {
                    self.routeDetails = details
                    self.routeCoordinates = details.coordinates
                    self.currentStepIndex = 0
                    self.currentCoordIndex = 0
                    self.hasAnnouncedAdvanceTurn = false
                    self.remainingRouteDistanceMiles = details.totalDistanceMiles
                    self.remainingRouteDurationSeconds = details.totalDurationSeconds
                    self.dynamicArrivalDate = details.targetArrivalDate
                    if let first = details.steps.first {
                        self.remainingStepDistanceMiles = first.distanceMiles
                        self.routingService.speakTurnInstruction(first.instruction, stepId: 0, force: true)
                    }
                } else {
                    self.errorMessage = "Rerouting failed: Current location or destination is outside offline road network."
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func handleMapLongPress(at coordinate: CLLocationCoordinate2D) {
        let tempPlace = SearchResult(
            id: 0,
            name: String(format: "Dropped Pin (%.4f, %.4f)", coordinate.latitude, coordinate.longitude),
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )
        selectPlace(tempPlace)
        let searcher = searchService

        Task.detached(priority: .userInitiated) {
            if let resolved = searcher.reverseGeocode(coordinate: coordinate) {
                await MainActor.run {
                    if self.selectedCoordinate?.latitude == coordinate.latitude &&
                       self.selectedCoordinate?.longitude == coordinate.longitude {
                        let latRad = coordinate.latitude * .pi / 180.0
                        let dx = (resolved.lon - coordinate.longitude) * 111320.0 * cos(latRad)
                        let dy = (resolved.lat - coordinate.latitude) * 110540.0
                        let distMeters = sqrt(dx * dx + dy * dy)
                        if distMeters <= 75.0 && resolved.id != 0 {
                            if self.destinationText != resolved.name {
                                self.isProgrammaticTextChange = true
                            }
                            self.selectedPlace = SearchResult(
                                id: resolved.id,
                                name: resolved.name,
                                lat: coordinate.latitude,
                                lon: coordinate.longitude
                            )
                            self.destinationText = resolved.name
                        }
                    }
                }
            }
        }
    }

    private func handleQueryChange(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
            appMode = .searchList
            isSearching = true
            let userLoc = effectiveUserCoordinate
            let searcher = searchService
            searchTask = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }
                let results = searcher.search(query: trimmed, userLocation: userLoc)
                if !Task.isCancelled {
                    await MainActor.run {
                        self.searchResults = results
                        self.isSearching = false
                    }
                }
            }
        } else {
            searchResults = []
            isSearching = false
            if appMode == .searchList {
                appMode = .explore
            }
        }
    }

    func searchCategory(_ category: String) {
        if destinationText != category {
            isProgrammaticTextChange = true
            destinationText = category
        }
        handleQueryChange(category)
    }

    private func selectPlace(_ place: SearchResult) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if destinationText != place.name {
            isProgrammaticTextChange = true
        }
        selectedPlace = place
        selectedCoordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        destinationText = place.name
        searchResults = []
        appMode = .placeDetail
    }

    private func calculateRouteTo(_ place: SearchResult, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let dest = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        let start = effectiveUserCoordinate
        let travelMode = selectedTravelMode
        let metric = useMetric
        let reqId = UUID()
        self.activeRouteRequestId = reqId
        let router = routingService

        appMode = .routePreview
        routeDetails = nil
        routeCoordinates = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let details = router.calculateRoute(from: start, to: dest, mode: travelMode, useMetric: metric)
            DispatchQueue.main.async {
                guard self.activeRouteRequestId == reqId else { return }
                if let details = details, !details.coordinates.isEmpty {
                    self.routeDetails = details
                    self.routeCoordinates = details.coordinates
                    self.remainingRouteDistanceMiles = details.totalDistanceMiles
                    self.remainingRouteDurationSeconds = details.totalDurationSeconds
                    self.dynamicArrivalDate = details.targetArrivalDate
                    if let first = details.steps.first {
                        self.remainingStepDistanceMiles = first.distanceMiles
                    }
                    completion?()
                } else {
                    self.errorMessage = "Could not calculate route to \(place.name)."
                    self.showErrorAlert = true
                    self.appMode = self.selectedPlace != nil ? .placeDetail : .explore
                }
            }
        }
    }

    private func switchTravelMode(_ mode: String) {
        selectedTravelMode = mode
        if let place = selectedPlace {
            calculateRouteTo(place)
        }
    }

    private func startNavigation() {
        guard let details = routeDetails, !details.coordinates.isEmpty else { return }
        isNavigating = true
        appMode = .navigation
        currentStepIndex = 0
        currentCoordIndex = 0
        hasAnnouncedAdvanceTurn = false
        remainingRouteDistanceMiles = details.totalDistanceMiles
        remainingRouteDurationSeconds = details.totalDurationSeconds
        dynamicArrivalDate = details.targetArrivalDate
        if let first = details.steps.first {
            remainingStepDistanceMiles = first.distanceMiles
        }
        simulatedUserCoordinate = details.coordinates.first
        locationManager.setNavigationActive(true)

        if let first = details.steps.first {
            routingService.speakTurnInstruction(first.instruction)
        }
    }

    private func startSimulatedDrive() {
        guard let details = routeDetails, !details.coordinates.isEmpty else { return }
        startNavigation()
        guard isNavigating else { return }
        isSimulating = true
        simulatedSpeedMph = selectedTravelMode == "pedestrian" ? 3 : (selectedTravelMode == "bicycle" ? 12 : 45)

        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            Task { @MainActor in
                advanceSimulationStep()
            }
        }
    }

    private func advanceSimulationStep() {
        guard let details = routeDetails, !details.coordinates.isEmpty else { return }
        let coords = details.coordinates
        guard currentCoordIndex < coords.count - 1 else {
            routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
            endNavigation()
            return
        }

        let stepJump = Int(max(1, simulationSpeedMultiplier))
        let nextIndex = min(coords.count - 1, currentCoordIndex + stepJump)

        let p1 = coords[currentCoordIndex]
        let p2 = coords[nextIndex]

        let dLon = (p2.longitude - p1.longitude) * .pi / 180
        let lat1 = p1.latitude * .pi / 180
        let lat2 = p2.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        let degreesBearing = (radiansBearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

        simulatedHeading = degreesBearing
        simulatedUserCoordinate = p2
        currentCoordIndex = nextIndex

        if currentStepIndex < details.steps.count - 1 {
            let nextStep = details.steps[currentStepIndex + 1]
            if currentCoordIndex >= nextStep.startIndex {
                currentStepIndex += 1
                hasAnnouncedAdvanceTurn = false
                routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
            } else if !hasAnnouncedAdvanceTurn {
                let turnCoord = coords[min(nextStep.startIndex, coords.count - 1)]
                let distToTurn = segmentDistanceMeters(p1: p2, p2: turnCoord)
                if distToTurn < 250.0 {
                    hasAnnouncedAdvanceTurn = true
                    let distStr = formatCountdownDistance(distToTurn * 0.000621371, useMetric: useMetric)
                    routingService.speakTurnInstruction("In \(distStr), \(nextStep.instruction)", stepId: (currentStepIndex + 1) * 10 + 1)
                }
            }
        }

        updateNavigationTelemetry(at: p2, coordIndex: nextIndex, in: details)
    }

    private func endNavigation() {
        activeRouteRequestId = nil
        isRecalculating = false
        routingService.stopVoice()
        simulationTimer?.invalidate()
        simulationTimer = nil
        isNavigating = false
        isSimulating = false
        isHudMode = false
        simulatedUserCoordinate = nil
        simulatedHeading = nil
        simulatedSpeedMph = 0
        locationManager.setNavigationActive(false)
        appMode = routeDetails != nil ? .routePreview : .explore
    }

    func dismissSearch() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        searchResults = []
        if appMode == .searchList {
            appMode = .explore
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        destinationText = ""
        searchResults = []
        dismissSearch()
    }

    func resetToExplore() {
        endNavigation()
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        destinationText = ""
        searchResults = []
        selectedPlace = nil
        selectedCoordinate = nil
        routeCoordinates = nil
        routeDetails = nil
        appMode = .explore
    }

    private func recenterOnUser() {
        if let user = locationManager.location?.coordinate, isWithinSupportedRegion(user) {
            userLocationCenter = user
        } else {
            userLocationCenter = ContentView.defaultAlaskaCoordinate
        }
    }
}

// MARK: - Subviews

struct CategoryChip: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.systemBackground))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
        }
    }
}

struct TravelModeTab: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .blue : .gray)
            .padding(.bottom, 2)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(isSelected ? .blue : .clear)
                    .offset(y: 8),
                alignment: .bottom
            )
        }
    }
}

struct SimulationSpeedButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .bold()
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .cornerRadius(8)
        }
    }
}

struct NavigationStepsSheet: View {
    let routeDetails: RouteDetails
    let currentStepIndex: Int
    var useMetric: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Route Summary")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routeDetails.formattedDuration)
                                .font(.title2)
                                .bold()
                                .foregroundColor(Color(red: 0.05, green: 0.6, blue: 0.25))
                            Text("\(routeDetails.formattedDistance(useMetric: useMetric)) • Fastest route")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Turn-by-Turn Directions")) {
                    ForEach(Array(routeDetails.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: step.iconName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(index == currentStepIndex ? .blue : .primary)
                                .frame(width: 28)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.instruction)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                if let street = step.streetName, !street.isEmpty {
                                    Text(street)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(step.formattedDistance(useMetric: useMetric))
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct DashboardGauge: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.title2).bold()
                Text(unit).font(.system(size: 10, weight: .semibold))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground).opacity(0.95))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.12), radius: 3)
    }
}

// MARK: - Concurrency Conformances
extension NavigationStep: @unchecked Sendable {}
extension RouteDetails: @unchecked Sendable {}

