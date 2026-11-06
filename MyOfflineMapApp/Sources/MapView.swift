import SwiftUI
import MapLibre
import CoreLocation

public struct MapView: UIViewRepresentable {
    public let pmtilesURL: URL
    public let destinationTitle: String?
    @Binding public var selectedCoordinate: CLLocationCoordinate2D?
    @Binding public var routeCoordinates: [CLLocationCoordinate2D]?
    @Binding public var simulatedUserCoordinate: CLLocationCoordinate2D?
    @Binding public var userLocationCenter: CLLocationCoordinate2D?
    @Binding public var zoomStep: Double?
    public let simulatedHeading: Double?
    public let isNavigating: Bool
    public let mapStyleName: String
    public let onMapTap: (() -> Void)?
    public let onLongPressCoordinate: ((CLLocationCoordinate2D) -> Void)?

    public init(
        pmtilesURL: URL,
        destinationTitle: String?,
        selectedCoordinate: Binding<CLLocationCoordinate2D?>,
        routeCoordinates: Binding<[CLLocationCoordinate2D]?>,
        simulatedUserCoordinate: Binding<CLLocationCoordinate2D?>,
        userLocationCenter: Binding<CLLocationCoordinate2D?> = .constant(nil),
        zoomStep: Binding<Double?> = .constant(nil),
        simulatedHeading: Double?,
        isNavigating: Bool,
        mapStyleName: String,
        onMapTap: (() -> Void)? = nil,
        onLongPressCoordinate: ((CLLocationCoordinate2D) -> Void)? = nil
    ) {
        self.pmtilesURL = pmtilesURL
        self.destinationTitle = destinationTitle
        self._selectedCoordinate = selectedCoordinate
        self._routeCoordinates = routeCoordinates
        self._simulatedUserCoordinate = simulatedUserCoordinate
        self._userLocationCenter = userLocationCenter
        self._zoomStep = zoomStep
        self.simulatedHeading = simulatedHeading
        self.isNavigating = isNavigating
        self.mapStyleName = mapStyleName
        self.onMapTap = onMapTap
        self.onLongPressCoordinate = onLongPressCoordinate
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.automaticallyAdjustsContentInset = false
        mapView.minimumZoomLevel = 2
        mapView.maximumZoomLevel = 19
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.delegate = context.coordinator

        // Tap gesture to dismiss search / dropdowns
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        // Long-press gesture to drop a pin (Google Maps style)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.65
        mapView.addGestureRecognizer(longPress)

        // Initial camera centered on Downtown Fairbanks, AK (Cushman St & 1st Ave)
        let centerCoordinate = CLLocationCoordinate2D(latitude: 64.8378, longitude: -147.7166)
        mapView.setCenter(centerCoordinate, zoomLevel: 13, animated: false)

        context.coordinator.loadMapStyle(on: mapView, pmtilesURL: pmtilesURL)

        return mapView
    }

    public static func dismantleUIView(_ uiView: MLNMapView, coordinator: Coordinator) {
        uiView.delegate = nil
        coordinator.clearRoute(on: uiView)
        coordinator.removeDestinationAnnotation(from: uiView)
        coordinator.removeCarAnnotation(from: uiView)
    }

    public func updateUIView(_ uiView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        uiView.showsUserLocation = !isNavigating

        // Recenter on user if requested
        if let userCoord = userLocationCenter {
            uiView.setCenter(userCoord, zoomLevel: 15, animated: true)
            DispatchQueue.main.async {
                self.userLocationCenter = nil
            }
        }

        // Zoom in / out control
        if let step = zoomStep {
            let targetZoom = max(uiView.minimumZoomLevel, min(uiView.maximumZoomLevel, uiView.zoomLevel + step))
            uiView.setZoomLevel(targetZoom, animated: true)
            DispatchQueue.main.async {
                self.zoomStep = nil
            }
        }

        // Destination Pin
        if let coordinate = selectedCoordinate {
            let coordChanged = coordinator.lastSelectedCoordinate == nil ||
                abs(coordinator.lastSelectedCoordinate!.latitude - coordinate.latitude) > 0.00001 ||
                abs(coordinator.lastSelectedCoordinate!.longitude - coordinate.longitude) > 0.00001
            let titleChanged = coordinator.lastDestinationTitle != destinationTitle

            if coordChanged || titleChanged {
                coordinator.lastSelectedCoordinate = coordinate
                coordinator.lastDestinationTitle = destinationTitle
                if !isNavigating && coordChanged {
                    uiView.userTrackingMode = .none
                    uiView.setCenter(coordinate, zoomLevel: 15, animated: true)
                }
                coordinator.updateDestinationAnnotation(on: uiView, coordinate: coordinate, title: destinationTitle)
            }
        } else if coordinator.lastSelectedCoordinate != nil {
            coordinator.lastSelectedCoordinate = nil
            coordinator.lastDestinationTitle = nil
            coordinator.removeDestinationAnnotation(from: uiView)
        }

        // Route Polyline (Robust deep comparison)
        if let route = routeCoordinates {
            let hasChanged: Bool = {
                guard let last = coordinator.lastRouteCoordinates else { return true }
                if last.count != route.count { return true }
                guard let f1 = last.first, let f2 = route.first,
                      let l1 = last.last, let l2 = route.last else { return true }
                if abs(f1.latitude - f2.latitude) > 0.00001 || abs(f1.longitude - f2.longitude) > 0.00001 ||
                   abs(l1.latitude - l2.latitude) > 0.00001 || abs(l1.longitude - l2.longitude) > 0.00001 {
                    return true
                }
                let mid = route.count / 2
                let m1 = last[mid]
                let m2 = route[mid]
                return abs(m1.latitude - m2.latitude) > 0.00001 || abs(m1.longitude - m2.longitude) > 0.00001
            }()

            if hasChanged {
                coordinator.lastRouteCoordinates = route
                coordinator.drawRoute(on: uiView, coordinates: route)
            }
        } else {
            if coordinator.lastRouteCoordinates != nil || coordinator.pendingRoute != nil {
                coordinator.lastRouteCoordinates = nil
                coordinator.pendingRoute = nil
                coordinator.clearRoute(on: uiView)
            }
        }

        // 3D Navigation Camera
        if isNavigating {
            if let userCoord = simulatedUserCoordinate {
                coordinator.updateCarAnnotation(on: uiView, coordinate: userCoord)
                let heading = simulatedHeading ?? uiView.camera.heading
                let navCamera = MLNMapCamera(
                    lookingAtCenter: userCoord,
                    altitude: 480,
                    pitch: 55,
                    heading: heading
                )
                uiView.setCamera(navCamera, animated: true)
            }
        } else {
            coordinator.removeCarAnnotation(from: uiView)
        }
    }

    @MainActor
    public class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: MapView
        var isStyleLoaded = false
        var pendingRoute: [CLLocationCoordinate2D]?
        var lastSelectedCoordinate: CLLocationCoordinate2D?
        var lastDestinationTitle: String?
        var lastRouteCoordinates: [CLLocationCoordinate2D]?
        var destinationAnnotation: MLNPointAnnotation?
        var carAnnotation: MLNPointAnnotation?

        init(_ parent: MapView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onMapTap?()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onLongPressCoordinate?(coord)
        }

        func loadMapStyle(on mapView: MLNMapView, pmtilesURL: URL) {
            let styleURL = OfflineDataManager.url(for: "style.json")
            do {
                let data = try Data(contentsOf: styleURL)
                guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                // Create symlink in temp directory without spaces to avoid C++ file source path decoding issues
                let symlinkURL = FileManager.default.temporaryDirectory.appendingPathComponent("offline_map.pmtiles")
                try? FileManager.default.removeItem(at: symlinkURL)
                try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: pmtilesURL)
                let localPMTilesURI = "pmtiles://file://" + symlinkURL.path

                // Configure vector source pointing directly to offline PMTiles archive
                var sources = json["sources"] as? [String: Any] ?? [String: Any]()
                sources["openmaptiles"] = [
                    "type": "vector",
                    "url": localPMTilesURI
                ]
                json["sources"] = sources

                // Check for locally bundled font glyphs without percent-encoding braces or path spaces
                let fontsURL = OfflineDataManager.url(for: "fonts")
                if FileManager.default.fileExists(atPath: fontsURL.path) {
                    let fontsSymlink = FileManager.default.temporaryDirectory.appendingPathComponent("offline_fonts")
                    try? FileManager.default.removeItem(at: fontsSymlink)
                    try? FileManager.default.createSymbolicLink(at: fontsSymlink, withDestinationURL: fontsURL)
                    let base = fontsSymlink.absoluteString.hasSuffix("/") ? fontsSymlink.absoluteString : fontsSymlink.absoluteString + "/"
                    json["glyphs"] = "\(base){fontstack}/{range}.pbf"
                } else {
                    json.removeValue(forKey: "glyphs")
                }

                // Check for locally bundled sprites across all supported extensions (.json, @2x.json, .png, @2x.png)
                let spriteURL = OfflineDataManager.url(for: "sprites/sprite")
                if OfflineDataManager.assetExists(at: spriteURL) {
                    let spritesDirURL = spriteURL.deletingLastPathComponent()
                    let spritesSymlinkDir = FileManager.default.temporaryDirectory.appendingPathComponent("offline_sprites")
                    try? FileManager.default.removeItem(at: spritesSymlinkDir)
                    try? FileManager.default.createSymbolicLink(at: spritesSymlinkDir, withDestinationURL: spritesDirURL)
                    let spritePrefixURL = spritesSymlinkDir.appendingPathComponent(spriteURL.lastPathComponent)
                    json["sprite"] = spritePrefixURL.absoluteString
                } else {
                    json.removeValue(forKey: "sprite")
                }

                // Filter symbol layers granularly: only drop layers whose required assets are missing
                let hasGlyphs = (json["glyphs"] != nil)
                let hasSprites = (json["sprite"] != nil)
                if var layers = json["layers"] as? [[String: Any]] {
                    layers = layers.filter { layer in
                        let type = layer["type"] as? String ?? ""
                        if type == "symbol" {
                            let layout = layer["layout"] as? [String: Any] ?? [:]
                            let hasTextField = layout["text-field"] != nil
                            let hasIconImage = layout["icon-image"] != nil
                            if hasTextField && !hasGlyphs { return false }
                            if hasIconImage && !hasSprites { return false }
                        }
                        let paint = layer["paint"] as? [String: Any] ?? [:]
                        if paint["fill-pattern"] != nil { return false }
                        return true
                    }
                    json["layers"] = layers
                }

                let tempStyleURL = FileManager.default.temporaryDirectory.appendingPathComponent("dynamic_style.json")
                let outData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
                try outData.write(to: tempStyleURL)
                mapView.styleURL = tempStyleURL
                print("MapView: Dynamic offline style prepared with \(sources.count) sources and \((json["layers"] as? [[String: Any]])?.count ?? 0) vector layers.")
            } catch {
                print("MapView ERROR: Failed to prepare dynamic style.json: \(error)")
            }
        }

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            isStyleLoaded = true
            print("MapView: Style finished loading.")
            if let pending = pendingRoute {
                drawRoute(on: mapView, coordinates: pending)
                pendingRoute = nil
            }
        }

        public func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            print("MapView ERROR: Failed to load map: \(error.localizedDescription)")
        }

        func updateDestinationAnnotation(on mapView: MLNMapView, coordinate: CLLocationCoordinate2D, title: String?) {
            removeDestinationAnnotation(from: mapView)
            let annotation = MLNPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = title ?? "Destination"
            mapView.addAnnotation(annotation)
            destinationAnnotation = annotation
        }

        func removeDestinationAnnotation(from mapView: MLNMapView) {
            if let existing = destinationAnnotation {
                mapView.removeAnnotation(existing)
                destinationAnnotation = nil
            }
        }

        func updateCarAnnotation(on mapView: MLNMapView, coordinate: CLLocationCoordinate2D) {
            if let existing = carAnnotation {
                if existing.coordinate.latitude == coordinate.latitude && existing.coordinate.longitude == coordinate.longitude {
                    return
                }
                // MLNPointAnnotation's coordinate property is KVO-compliant.
                // Setting coordinate directly updates the annotation view position smoothly without flicker.
                existing.coordinate = coordinate
            } else {
                let car = MLNPointAnnotation()
                car.coordinate = coordinate
                car.title = "Current Position"
                mapView.addAnnotation(car)
                carAnnotation = car
            }
        }

        func removeCarAnnotation(from mapView: MLNMapView) {
            if let existing = carAnnotation {
                mapView.removeAnnotation(existing)
                carAnnotation = nil
            }
        }

        func drawRoute(on mapView: MLNMapView, coordinates: [CLLocationCoordinate2D]) {
            guard !coordinates.isEmpty else { return }
            guard let style = mapView.style, isStyleLoaded else {
                pendingRoute = coordinates
                return
            }

            // Clean up any existing route layers and sources first
            clearRoute(on: mapView)

            var coords = coordinates
            let polyline = MLNPolyline(coordinates: &coords, count: UInt(coords.count))

            // Shared shape source for both casing and core route layers
            let source = MLNShapeSource(identifier: "route-source", shape: polyline, options: nil)
            style.addSource(source)

            // 1. Casing / Outline (Google Maps Dark Blue Border)
            let casingLayer = MLNLineStyleLayer(identifier: "route-casing-layer", source: source)
            casingLayer.lineColor = NSExpression(forConstantValue: UIColor(red: 0.08, green: 0.35, blue: 0.75, alpha: 1.0))
            casingLayer.lineWidth = NSExpression(forConstantValue: 8.5)
            casingLayer.lineCap = NSExpression(forConstantValue: "round")
            casingLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(casingLayer)

            // 2. Core Line (Vibrant Google Maps Blue)
            let layer = MLNLineStyleLayer(identifier: "route-layer", source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1.0))
            layer.lineWidth = NSExpression(forConstantValue: 6.0)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(layer)

            if coords.count >= 2 && !parent.isNavigating {
                let insets = UIEdgeInsets(top: 120, left: 40, bottom: 260, right: 40)
                mapView.setVisibleCoordinateBounds(polyline.overlayBounds, edgePadding: insets, animated: true)
            }
        }

        func clearRoute(on mapView: MLNMapView) {
            pendingRoute = nil
            guard let style = mapView.style, isStyleLoaded else { return }
            if let layer = style.layer(withIdentifier: "route-layer") {
                style.removeLayer(layer)
            }
            if let casing = style.layer(withIdentifier: "route-casing-layer") {
                style.removeLayer(casing)
            }
            if let source = style.source(withIdentifier: "route-source") {
                style.removeSource(source)
            }
        }

        public func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            return UIColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1.0)
        }

        public func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            return 6.0
        }

        public func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            true
        }
    }
}
