import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject var viewModel: NavigationViewModel
    @State private var showAttributionAlert = false

    public init(viewModel: NavigationViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? NavigationViewModel())
    }

    // MARK: - Backward-Compatibility Forwarding Properties (Preserves Existing Test Access)
    var locationManager: LocationManager { viewModel.locationManager }
    var searchService: SearchService { viewModel.searchService }
    var routingService: RoutingService { viewModel.routingService }

    var appMode: MapAppMode {
        get { viewModel.appMode }
        nonmutating set { viewModel.appMode = newValue }
    }
    var selectedPlace: SearchResult? {
        get { viewModel.selectedPlace }
        nonmutating set { viewModel.selectedPlace = newValue }
    }
    var routeDetails: RouteDetails? {
        get { viewModel.routeDetails }
        nonmutating set { viewModel.routeDetails = newValue }
    }
    var selectedTravelMode: String {
        get { viewModel.selectedTravelMode }
        nonmutating set { viewModel.selectedTravelMode = newValue }
    }
    var showStepsSheet: Bool {
        get { viewModel.showStepsSheet }
        nonmutating set { viewModel.showStepsSheet = newValue }
    }
    var isHudMode: Bool {
        get { viewModel.isHudMode }
        nonmutating set { viewModel.isHudMode = newValue }
    }
    var useMetric: Bool {
        get { viewModel.useMetric }
        nonmutating set { viewModel.useMetric = newValue }
    }
    var isVoiceMuted: Bool {
        get { viewModel.isVoiceMuted }
        nonmutating set { viewModel.isVoiceMuted = newValue }
    }
    var destinationText: String {
        get { viewModel.destinationText }
        nonmutating set { viewModel.destinationText = newValue }
    }
    var searchResults: [SearchResult] {
        get { viewModel.searchResults }
        nonmutating set { viewModel.searchResults = newValue }
    }
    var isSearching: Bool {
        get { viewModel.isSearching }
        nonmutating set { viewModel.isSearching = newValue }
    }
    var searchTask: Task<Void, Never>? {
        get { viewModel.searchTask }
        nonmutating set { viewModel.searchTask = newValue }
    }
    var isProgrammaticTextChange: Bool {
        get { viewModel.isProgrammaticTextChange }
        nonmutating set { viewModel.isProgrammaticTextChange = newValue }
    }
    var selectedCoordinate: CLLocationCoordinate2D? {
        get { viewModel.selectedCoordinate }
        nonmutating set { viewModel.selectedCoordinate = newValue }
    }
    var routeCoordinates: [CLLocationCoordinate2D]? {
        get { viewModel.routeCoordinates }
        nonmutating set { viewModel.routeCoordinates = newValue }
    }
    var simulatedUserCoordinate: CLLocationCoordinate2D? {
        get { viewModel.simulatedUserCoordinate }
        nonmutating set { viewModel.simulatedUserCoordinate = newValue }
    }
    var userLocationCenter: CLLocationCoordinate2D? {
        get { viewModel.userLocationCenter }
        nonmutating set { viewModel.userLocationCenter = newValue }
    }
    var simulatedHeading: Double? {
        get { viewModel.simulatedHeading }
        nonmutating set { viewModel.simulatedHeading = newValue }
    }
    var zoomStep: Double? {
        get { viewModel.zoomStep }
        nonmutating set { viewModel.zoomStep = newValue }
    }
    var isNavigating: Bool {
        get { viewModel.isNavigating }
        nonmutating set { viewModel.isNavigating = newValue }
    }
    var isSimulating: Bool {
        get { viewModel.isSimulating }
        nonmutating set { viewModel.isSimulating = newValue }
    }
    var currentStepIndex: Int {
        get { viewModel.currentStepIndex }
        nonmutating set { viewModel.currentStepIndex = newValue }
    }
    var currentCoordIndex: Int {
        get { viewModel.currentCoordIndex }
        nonmutating set { viewModel.currentCoordIndex = newValue }
    }
    var simulatedSpeedMph: Int {
        get { viewModel.simulatedSpeedMph }
        nonmutating set { viewModel.simulatedSpeedMph = newValue }
    }
    var simulationSpeedMultiplier: Double {
        get { viewModel.simulationSpeedMultiplier }
        nonmutating set { viewModel.simulationSpeedMultiplier = newValue }
    }
    var isRecalculating: Bool {
        get { viewModel.isRecalculating }
        nonmutating set { viewModel.isRecalculating = newValue }
    }
    var consecutiveRerouteFailures: Int {
        get { viewModel.consecutiveRerouteFailures }
        nonmutating set { viewModel.consecutiveRerouteFailures = newValue }
    }
    var lastRerouteTime: Date {
        get { viewModel.lastRerouteTime }
        nonmutating set { viewModel.lastRerouteTime = newValue }
    }
    var activeRouteRequestId: UUID? {
        get { viewModel.activeRouteRequestId }
        nonmutating set { viewModel.activeRouteRequestId = newValue }
    }
    var remainingStepDistanceMiles: Double {
        get { viewModel.remainingStepDistanceMiles }
        nonmutating set { viewModel.remainingStepDistanceMiles = newValue }
    }
    var remainingRouteDistanceMiles: Double {
        get { viewModel.remainingRouteDistanceMiles }
        nonmutating set { viewModel.remainingRouteDistanceMiles = newValue }
    }
    var remainingRouteDurationSeconds: Double {
        get { viewModel.remainingRouteDurationSeconds }
        nonmutating set { viewModel.remainingRouteDurationSeconds = newValue }
    }
    var dynamicArrivalDate: Date {
        get { viewModel.dynamicArrivalDate }
        nonmutating set { viewModel.dynamicArrivalDate = newValue }
    }
    var hasAnnouncedAdvanceTurn: Bool {
        get { viewModel.hasAnnouncedAdvanceTurn }
        nonmutating set { viewModel.hasAnnouncedAdvanceTurn = newValue }
    }
    var errorMessage: String? {
        get { viewModel.errorMessage }
        nonmutating set { viewModel.errorMessage = newValue }
    }
    var showErrorAlert: Bool {
        get { viewModel.showErrorAlert }
        nonmutating set { viewModel.showErrorAlert = newValue }
    }
    var isMapDataMissing: Bool {
        get { viewModel.isMapDataMissing }
        nonmutating set { viewModel.isMapDataMissing = newValue }
    }

    var displaySpeed: Int { viewModel.displaySpeed }
    var speedUnit: String { viewModel.speedUnit }
    var altitudeValue: Int { viewModel.altitudeValue }
    var altitudeUnit: String { viewModel.altitudeUnit }
    var effectiveUserCoordinate: CLLocationCoordinate2D { viewModel.effectiveUserCoordinate }
    var formattedRemainingDuration: String { viewModel.formattedRemainingDuration }
    var formattedRemainingETA: String { viewModel.formattedRemainingETA }
    var currentNavigationStep: NavigationStep { viewModel.currentNavigationStep }
    static var defaultAlaskaCoordinate: CLLocationCoordinate2D { NavigationViewModel.defaultAlaskaCoordinate }

    // MARK: - Backward-Compatibility Forwarding Methods
    func formatCountdownDistance(_ miles: Double, useMetric: Bool) -> String {
        viewModel.formatCountdownDistance(miles, useMetric: useMetric)
    }

    func isWithinSupportedRegion(_ coord: CLLocationCoordinate2D) -> Bool {
        viewModel.isWithinSupportedRegion(coord)
    }

    func segmentDistanceMeters(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D) -> Double {
        viewModel.segmentDistanceMeters(p1: p1, p2: p2)
    }

    func dismissSearch() {
        searchTask?.cancel()
        viewModel.dismissSearch()
    }

    func clearSearch() {
        searchTask?.cancel()
        viewModel.clearSearch()
    }

    func resetToExplore() {
        searchTask?.cancel()
        viewModel.resetToExplore()
    }

    func searchCategory(_ category: String) {
        if destinationText != category {
            isProgrammaticTextChange = true
            destinationText = category
        }
        viewModel.searchCategory(category)
    }

    func updateCurrentStepForLiveLocation(_ userCoord: CLLocationCoordinate2D, in details: RouteDetails) {
        viewModel.updateCurrentStepForLiveLocation(userCoord, in: details)
    }

    func updateNavigationTelemetry(at userCoord: CLLocationCoordinate2D, coordIndex: Int, in details: RouteDetails) {
        viewModel.updateNavigationTelemetry(at: userCoord, coordIndex: coordIndex, in: details)
    }

    func advanceSimulationStep() {
        viewModel.advanceSimulationStep()
    }

    func handleLocationUpdate(_ location: CLLocation?) {
        guard let location = location else { return }
        guard isWithinSupportedRegion(location.coordinate) else { return }
        viewModel.handleLocationUpdate(location)
    }

    func handleQueryChange(_ query: String) {
        searchTask?.cancel()
        viewModel.handleQueryChange(query)
    }

    func selectPlace(_ place: SearchResult) {
        viewModel.selectPlace(place)
    }

    func calculateRouteTo(_ place: SearchResult, completion: (@MainActor @Sendable () -> Void)? = nil) {
        viewModel.calculateRouteTo(place, completion: completion)
    }

    func switchTravelMode(_ mode: String) {
        viewModel.switchTravelMode(mode)
    }

    func startNavigation() {
        viewModel.startNavigation()
    }

    func startSimulatedDrive() {
        viewModel.startSimulatedDrive()
    }

    func endNavigation() {
        viewModel.endNavigation()
    }

    func recenterOnUser() {
        viewModel.recenterOnUser()
    }

    func toggleVoiceMute() {
        viewModel.toggleVoiceMute()
    }

    func checkMapDataMissing() {
        viewModel.checkMapDataMissing()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background Map
            MapView(
                pmtilesURL: OfflineDataManager.url(for: "north-america.pmtiles"),
                destinationTitle: selectedPlace?.name ?? destinationText,
                selectedCoordinate: $viewModel.selectedCoordinate,
                routeCoordinates: $viewModel.routeCoordinates,
                simulatedUserCoordinate: $viewModel.simulatedUserCoordinate,
                userLocationCenter: $viewModel.userLocationCenter,
                zoomStep: $viewModel.zoomStep,
                simulatedHeading: viewModel.simulatedHeading,
                isNavigating: viewModel.isNavigating,
                mapStyleName: "standard",
                onMapTap: {
                    if appMode == .searchList {
                        dismissSearch()
                    }
                },
                onLongPressCoordinate: { coord in
                    viewModel.handleMapLongPress(at: coord)
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
        .sheet(isPresented: $viewModel.showStepsSheet) {
            if let details = routeDetails {
                NavigationStepsSheet(routeDetails: details, currentStepIndex: currentStepIndex, useMetric: useMetric)
            }
        }
        .task {
            checkMapDataMissing()
        }
        .alert("Notice", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .alert("Map Data & Open-Source Licensing", isPresented: $showAttributionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("• Map Data: © OpenStreetMap contributors (ODbL 1.0) & © OpenMapTiles (CC-BY 4.0)\n• Rendering: MapLibre GL Native (BSD 2-Clause)\n• Routing: Valhalla (MIT)\n• Database: SQLite.swift (MIT)\n• Terrain: Natural Earth (Public Domain)\n\nAll data and algorithms operate 100% offline. See THIRD_PARTY_NOTICES.md for complete copyright and license details.")
        }
        .onReceive(viewModel.locationManager.$location) { newLoc in
            handleLocationUpdate(newLoc)
        }
        .onChange(of: viewModel.useMetric) { _, _ in
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

    // MARK: - 1. Top Search Header & Category Chips (Google Maps Floating Style)
    private var topSearchHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if appMode == .searchList || selectedPlace != nil {
                    Button(action: {
                        dismissSearch()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                    }
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .frame(width: 28, height: 28)
                }

                TextField("Search here", text: $viewModel.destinationText)
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

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)
                } else if !destinationText.isEmpty {
                    Button(action: {
                        clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }

                Button(action: {
                    showAttributionAlert = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Category Chips Carousel (horizontal scroll)
            if appMode == .explore {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(icon: "fuelpump.fill", title: "Gas", color: .orange) {
                            searchCategory("Gas")
                        }
                        CategoryChip(icon: "cup.and.saucer.fill", title: "Coffee", color: .brown) {
                            searchCategory("Coffee")
                        }
                        CategoryChip(icon: "fork.knife", title: "Food", color: .red) {
                            searchCategory("Restaurant")
                        }
                        CategoryChip(icon: "cart.fill", title: "Groceries", color: .green) {
                            searchCategory("Groceries")
                        }
                        CategoryChip(icon: "parkingsign.circle.fill", title: "Parking", color: .blue) {
                            searchCategory("Parking")
                        }
                        CategoryChip(icon: "bed.double.fill", title: "Hotels", color: .indigo) {
                            searchCategory("Hotel")
                        }
                        CategoryChip(icon: "cross.fill", title: "Hospitals", color: .red) {
                            searchCategory("Hospital")
                        }
                        CategoryChip(icon: "tree.fill", title: "Parks", color: .teal) {
                            searchCategory("Park")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 2. Persistent Offline Status & GPS Alert Banner
    @ViewBuilder
    private var statusAlertBanner: some View {
        if locationManager.isGpsSignalLow {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .foregroundColor(.yellow)
                Text("Weak GPS signal. Routing and speedometer may be degraded.")
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
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCountdownDistance(remainingStepDistanceMiles, useMetric: useMetric))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(step.instruction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(2)

                    if let street = step.streetName, !street.isEmpty {
                        Text(street)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }

                Spacer()

                // Voice Mute Toggle
                Button(action: {
                    toggleVoiceMute()
                }) {
                    Image(systemName: isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }

                // Close / End Navigation Button
                Button(action: {
                    endNavigation()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.05, green: 0.50, blue: 0.22)) // Google Maps Navigation Green
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - 4. Search Results Dropdown List
    private var searchResultsDropdown: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults.indices, id: \.self) { index in
                    let result = searchResults[index]
                    Button(action: {
                        selectPlace(result)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundColor(.red)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(result.category)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    Divider().padding(.leading, 44)
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
        .frame(maxHeight: 280)
    }

    // MARK: - 5. Bottom Controls Area (Mode Sensitive)
    @ViewBuilder
    private var bottomControlsArea: some View {
        switch appMode {
        case .explore, .searchList:
            exploreBottomBar
        case .placeDetail:
            placeDetailCard
        case .routePreview:
            routePreviewCard
        case .navigation:
            activeNavigationControls
        }
    }

    // Explore / Map Floating Action Buttons (FABs)
    private var exploreBottomBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                // Live Speedometer and Elevation Gauges
                HStack(spacing: 8) {
                    DashboardGauge(
                        title: "SPEED",
                        value: "\(displaySpeed)",
                        unit: speedUnit
                    )
                    DashboardGauge(
                        title: "ELEVATION",
                        value: "\(altitudeValue)",
                        unit: altitudeUnit
                    )
                }
                Spacer()

                // Map Control Buttons (Recenter, Zoom, Unit toggle)
                VStack(spacing: 8) {
                    Button(action: {
                        recenterOnUser()
                    }) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.15), radius: 4)
                    }

                    VStack(spacing: 0) {
                        Button(action: { zoomStep = 1.0 }) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 44, height: 40)
                        }
                        Divider().frame(width: 28)
                        Button(action: { zoomStep = -1.0 }) {
                            Image(systemName: "minus")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 44, height: 40)
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.15), radius: 4)

                    // Unit Toggle Pill (mph vs km/h)
                    Button(action: {
                        useMetric.toggle()
                    }) {
                        Text(useMetric ? "KM" : "MI")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 28)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.12), radius: 3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    // Place Detail Bottom Sheet
    private var placeDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let place = selectedPlace {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.title3)
                            .bold()
                        Text(place.category)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        resetToExplore()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }

                // Travel mode selector
                HStack(spacing: 20) {
                    TravelModeTab(icon: "car.fill", title: "Drive", isSelected: selectedTravelMode == "auto") {
                        switchTravelMode("auto")
                    }
                    TravelModeTab(icon: "figure.walk", title: "Walk", isSelected: selectedTravelMode == "pedestrian") {
                        switchTravelMode("pedestrian")
                    }
                    TravelModeTab(icon: "bicycle", title: "Bicycle", isSelected: selectedTravelMode == "bicycle") {
                        switchTravelMode("bicycle")
                    }
                    Spacer()
                }
                .padding(.top, 4)

                // Directions CTA Button
                Button(action: {
                    calculateRouteTo(place)
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text("Directions")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding(18)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // Route Preview Card
    private var routePreviewCard: some View {
        VStack(spacing: 12) {
            if let details = routeDetails {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(details.formattedDuration)
                                .font(.title2)
                                .bold()
                                .foregroundColor(Color(red: 0.05, green: 0.6, blue: 0.25))
                            Text("(\(details.formattedDistance(useMetric: useMetric)))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("Fastest route via offline network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button(action: {
                        resetToExplore()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }

                // Travel mode tabs
                HStack(spacing: 20) {
                    TravelModeTab(icon: "car.fill", title: "Drive", isSelected: selectedTravelMode == "auto") {
                        switchTravelMode("auto")
                    }
                    TravelModeTab(icon: "figure.walk", title: "Walk", isSelected: selectedTravelMode == "pedestrian") {
                        switchTravelMode("pedestrian")
                    }
                    TravelModeTab(icon: "bicycle", title: "Bicycle", isSelected: selectedTravelMode == "bicycle") {
                        switchTravelMode("bicycle")
                    }
                    Spacer()
                }

                // Action CTA Buttons (Start Navigation vs Simulation vs Steps)
                HStack(spacing: 10) {
                    Button(action: {
                        startNavigation()
                    }) {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Start")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(action: {
                        startSimulatedDrive()
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Simulate")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }

                    Button(action: {
                        showStepsSheet = true
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Calculating fastest offline route...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(18)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // Active Navigation Bottom Controls (ETA, distance, simulation speeds, HUD toggle)
    private var activeNavigationControls: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                // Live Speedometer and Elevation Gauges
                HStack(spacing: 8) {
                    DashboardGauge(
                        title: "SPEED",
                        value: "\(displaySpeed)",
                        unit: speedUnit
                    )
                    DashboardGauge(
                        title: "ELEVATION",
                        value: "\(altitudeValue)",
                        unit: altitudeUnit
                    )
                }

                Spacer()

                // Windshield HUD Mode Toggle Button
                Button(action: {
                    isHudMode = true
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "car.window.right")
                            .font(.system(size: 16, weight: .bold))
                        Text("HUD")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.2), radius: 4)
                }

                // Recenter Camera FAB
                Button(action: {
                    recenterOnUser()
                }) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.15), radius: 4)
                }
            }
            .padding(.horizontal, 16)

            // Main Bottom Navigation Bar (Google Maps style bottom panel)
            VStack(spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(formattedRemainingETA)
                                .font(.title3)
                                .bold()
                                .foregroundColor(Color(red: 0.05, green: 0.6, blue: 0.25))

                            Text("•  \(formattedRemainingDuration)")
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            Text("•  \(formatCountdownDistance(remainingRouteDistanceMiles, useMetric: useMetric))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let steps = routeDetails?.steps {
                            Text("Step \(min(currentStepIndex + 1, steps.count)) of \(steps.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // End Navigation Button (Red Circle with X)
                    Button(action: {
                        endNavigation()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }

                // Simulation Speed Toggle Toolbar (when running in simulation)
                if isSimulating {
                    Divider()
                    HStack(spacing: 12) {
                        Text("Simulation:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        SimulationSpeedButton(label: "1x", isSelected: simulationSpeedMultiplier == 1.0) {
                            simulationSpeedMultiplier = 1.0
                        }
                        SimulationSpeedButton(label: "2x", isSelected: simulationSpeedMultiplier == 2.0) {
                            simulationSpeedMultiplier = 2.0
                        }
                        SimulationSpeedButton(label: "5x", isSelected: simulationSpeedMultiplier == 5.0) {
                            simulationSpeedMultiplier = 5.0
                        }

                        Spacer()

                        Button(action: {
                            showStepsSheet = true
                        }) {
                            Text("Steps")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: -2)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - 6. HUD Windshield Reflection View (OLED Pure Black with Inverted Text)
    private var hudWindshieldView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button(action: { isHudMode = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text("WINDSHIELD HUD")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Huge Maneuver Arrow & Countdown Distance
                let step = currentNavigationStep
                Image(systemName: step.iconName)
                    .font(.system(size: 100, weight: .bold))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))

                Text(formatCountdownDistance(remainingStepDistanceMiles, useMetric: useMetric))
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text(step.instruction)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                // Speedometer & ETA Display
                HStack(spacing: 40) {
                    VStack(spacing: 4) {
                        Text("\(displaySpeed)")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text(speedUnit.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundColor(.gray)
                    }

                    VStack(spacing: 4) {
                        Text(formattedRemainingETA)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                        Text(formattedRemainingDuration)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()
            }
            .scaleEffect(x: -1.0, y: 1.0) // Horizontally mirror for windshield reflection
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
