import XCTest
import CoreLocation
import MapLibre
import Valhalla
import ValhallaModels
import ValhallaConfigModels
@testable import MyOfflineMapApp

final class MyOfflineMapAppTests: XCTestCase {

    func testDistanceFormatting() {
        let collegeCoord = CLLocationCoordinate2D(latitude: 64.8569, longitude: -147.8028)
        let result = SearchResult(id: 1, name: "Fairbanks Airport", lat: 64.8153, lon: -147.8564)

        let dist = result.distanceMiles(from: collegeCoord)
        XCTAssertNotNil(dist)
        XCTAssertTrue(dist! > 2.0 && dist! < 6.0, "Expected airport distance between 2 and 6 miles from College, AK")

        let formatted = result.formattedDistance(from: collegeCoord)
        XCTAssertTrue(formatted.contains("mi away") || formatted.contains("ft away"))
    }

    func testSearchQueryTokenization() {
        let rawQuery = "Fairbanks - Alaska: Coffee & Gas!"
        let nonAlphanumeric = CharacterSet.alphanumerics.inverted
        let tokens = rawQuery.components(separatedBy: nonAlphanumeric).filter { !$0.isEmpty }

        XCTAssertEqual(tokens, ["Fairbanks", "Alaska", "Coffee", "Gas"])
        let ftsQuery = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
        XCTAssertEqual(ftsQuery, "\"Fairbanks\"* \"Alaska\"* \"Coffee\"* \"Gas\"*")
    }

    func testCategoryDetection() {
        let gasPlace = SearchResult(id: 10, name: "Chevron Gas Station", lat: 64.85, lon: -147.8)
        XCTAssertEqual(gasPlace.category, "gas")
        XCTAssertEqual(gasPlace.iconName, "fuelpump.fill")

        let coffeePlace = SearchResult(id: 20, name: "Mocha Dan's Coffee Shop", lat: 64.85, lon: -147.8)
        XCTAssertEqual(coffeePlace.category, "coffee")
        XCTAssertEqual(coffeePlace.iconName, "cup.and.saucer.fill")

        let restaurantPlace = SearchResult(id: 30, name: "The Pump House Restaurant", lat: 64.85, lon: -147.8)
        XCTAssertEqual(restaurantPlace.category, "food")
        XCTAssertEqual(restaurantPlace.iconName, "fork.knife")

        // Substring false positive tests
        let pizzaPlace = SearchResult(id: 40, name: "Las Vegas Pizza", lat: 64.85, lon: -147.8)
        XCTAssertEqual(pizzaPlace.category, "food", "Las Vegas Pizza must be food, not gas")

        let toiletPlace = SearchResult(id: 50, name: "Public Toilet", lat: 64.85, lon: -147.8)
        XCTAssertNotEqual(toiletPlace.category, "gas", "Toilet must not be classified as gas")

        let dinnerPlace = SearchResult(id: 60, name: "Evening Dinner", lat: 64.85, lon: -147.8)
        XCTAssertNotEqual(dinnerPlace.category, "hotel", "Dinner must not be classified as hotel")

        let barrowPlace = SearchResult(id: 70, name: "Barrow High School", lat: 71.29, lon: -156.78)
        XCTAssertNotEqual(barrowPlace.category, "food", "Barrow must not be classified as food")

        let parkingPlace = SearchResult(id: 80, name: "Downtown Parking Garage", lat: 64.84, lon: -147.72)
        XCTAssertEqual(parkingPlace.category, "parking")
        XCTAssertEqual(parkingPlace.iconName, "parkingsign.circle.fill")
    }

    func testRouteDetailsFormatting() {
        let start = CLLocationCoordinate2D(latitude: 64.8569, longitude: -147.8028)
        let dest = CLLocationCoordinate2D(latitude: 64.8378, longitude: -147.7166)

        let step1 = NavigationStep(
            instruction: "Head east on University Ave",
            distanceMiles: 2.5,
            durationSeconds: 300,
            maneuverType: 1,
            streetName: "University Ave",
            startIndex: 0,
            endIndex: 10
        )

        let details = RouteDetails(
            coordinates: [start, dest],
            totalDistanceMiles: 5.2,
            totalDurationSeconds: 660, // 11 mins
            steps: [step1],
            costing: "auto"
        )

        XCTAssertEqual(details.formattedDuration, "11 min")
        XCTAssertEqual(details.formattedDistance, "5.2 mi")
        XCTAssertFalse(details.formattedETA.isEmpty)
        XCTAssertEqual(step1.iconName, "arrow.up")
        XCTAssertEqual(step1.formattedDistance, "2.5 mi")

        // Maneuver icons verification
        let uTurnLeft = NavigationStep(instruction: "U-Turn Left", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 12, streetName: nil, startIndex: 0, endIndex: 1)
        XCTAssertEqual(uTurnLeft.iconName, "arrow.uturn.left")

        let uTurnRight = NavigationStep(instruction: "U-Turn Right", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 13, streetName: nil, startIndex: 0, endIndex: 1)
        XCTAssertEqual(uTurnRight.iconName, "arrow.uturn.right")

        let stayLeft = NavigationStep(instruction: "Stay Left", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 24, streetName: nil, startIndex: 0, endIndex: 1)
        XCTAssertEqual(stayLeft.iconName, "arrow.up.left")

        let stayRight = NavigationStep(instruction: "Stay Right", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 25, streetName: nil, startIndex: 0, endIndex: 1)
        XCTAssertEqual(stayRight.iconName, "arrow.up.right")

        let merge = NavigationStep(instruction: "Merge", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 37, streetName: nil, startIndex: 0, endIndex: 1)
        XCTAssertEqual(merge.iconName, "arrow.triangle.merge")
    }

    func testMapLibreStyleAndPMTiles() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let symlink = appSupport.appendingPathComponent("test_map.pmtiles")
        try? FileManager.default.removeItem(at: symlink)
        let original = OfflineDataManager.url(for: "north-america.pmtiles")
        do {
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
            print("Created PMTiles symlink at: \(symlink.path)")
        } catch {
            print("Failed to create symlink: \(error)")
        }

        let pmtilesURI = "pmtiles://file://" + symlink.path
        let styleURL = OfflineDataManager.url(for: "style.json")
        guard let styleString = try? String(contentsOf: styleURL, encoding: .utf8) else {
            XCTFail("Could not read style.json")
            return
        }

        let dynamicStyle = styleString.replacingOccurrences(of: "PMTILES_PLACEHOLDER", with: pmtilesURI)
        let tempStyle = FileManager.default.temporaryDirectory.appendingPathComponent("test_dynamic_style.json")
        try? dynamicStyle.write(to: tempStyle, atomically: true, encoding: .utf8)

        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        mapView.styleURL = tempStyle
        
        // Wait for style to load
        let styleExp = expectation(description: "Style loading")
        class Delegate: NSObject, MLNMapViewDelegate {
            let exp: XCTestExpectation
            init(_ exp: XCTestExpectation) { self.exp = exp }
            func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
                print("Test: Style finished loading! Sources in style: \(style.sources.map { $0.identifier })")
                print("Layers in style count: \(style.layers.count)")
                exp.fulfill()
            }
            func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
                print("Test: Map loading failed with error: \(error)")
            }
        }
        let del = Delegate(styleExp)
        mapView.delegate = del
        wait(for: [styleExp], timeout: 5.0)
    }

    func testBinnedTileRouting() throws {
        let testTarPath = OfflineDataManager.url(for: "alaska_tiles.tar").path
        guard FileManager.default.fileExists(atPath: testTarPath) else {
            throw XCTSkip("alaska_tiles.tar not available on disk")
        }
        var config = ValhallaConfig()
        config.mjolnir?.tileExtract = testTarPath
        config.mjolnir?.trafficExtract = nil
        config.mjolnir?.tileDir = nil
        config.loki?.useConnectivity = false
        let valhalla = try Valhalla(config)
        
        // Downtown Fairbanks to South Cushman St
        let start = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let dest = CLLocationCoordinate2D(latitude: 64.8358, longitude: -147.7345)
        
        let request = RouteRequest(
            locations: [
                RoutingWaypoint(lat: start.latitude, lon: start.longitude),
                RoutingWaypoint(lat: dest.latitude, lon: dest.longitude)
            ],
            costing: .auto,
            units: .mi
        )
        
        do {
            let response = try valhalla.route(request: request)
            print(">>> SUCCESSFUL ROUTE! Status: \(response.trip.statusMessage ?? "nil"), Legs: \(response.trip.legs.count)")
            if let leg = response.trip.legs.first {
                print(">>> Leg shape points: \(leg.shape.count), length: \(leg.summary.length) mi, time: \(leg.summary.time) s, maneuvers: \(leg.maneuvers.count)")
                for m in leg.maneuvers {
                    print(">>> Step: \(m.instruction) on \(m.streetNames?.joined(separator: ", ") ?? "unnamed")")
                }
            }
            XCTAssertEqual(response.trip.statusMessage, "Found route between points")
        } catch {
            XCTFail("Route failed: \(error)")
        }
    }

    func testValhallaRoutingOnRoads() {
        let service = RoutingService()
        let exp = expectation(description: "Valhalla Routing")
        DispatchQueue.global().async {
            // Downtown Fairbanks: Cushman St & 1st Ave
            let start = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            // Near South Cushman St
            let dest = CLLocationCoordinate2D(latitude: 64.8358, longitude: -147.7345)

            for mode in ["auto", "pedestrian", "bicycle"] {
                guard let route = service.calculateRoute(from: start, to: dest, mode: mode) else {
                    XCTFail("Route returned nil for mode \(mode)")
                    continue
                }
                print(">>> VALHALLA ROUTE [\(mode)]: isFallback=\(route.isFallback), coordsCount=\(route.coordinates.count), steps=\(route.steps.count)")
                XCTAssertFalse(route.isFallback, "Expected real road route, got fallback sine wave")
                XCTAssertTrue(route.coordinates.count > 10, "Expected at least 10 real road coordinates")
                XCTAssertTrue(route.steps.count >= 2, "Expected turn maneuvers")
                XCTAssertTrue(route.totalDistanceMiles > 0.5, "Expected distance > 0.5 mi")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 25.0)
    }

    func testOfflineSearchService() {
        let searchService = SearchService()
        let userLoc = CLLocationCoordinate2D(latitude: 64.8378, longitude: -147.7166)
        
        let results = searchService.search(query: "Fairbanks", userLocation: userLoc)
        XCTAssertFalse(results.isEmpty, "Search should return results from search_index.db")
        print("Search results for 'Fairbanks': \(results.prefix(3).map { $0.name })")
        
        // Reverse geocoding near Fairbanks
        let reversePlace = searchService.reverseGeocode(coordinate: userLoc)
        XCTAssertNotNil(reversePlace)
        print("Reverse geocode result: \(reversePlace?.name ?? "nil")")
    }

    func testLocalBoundedSearchCategory() {
        let searchService = SearchService()
        let fairbanksCoord = CLLocationCoordinate2D(latitude: 64.8378, longitude: -147.7166)

        let gasResults = searchService.search(query: "Gas", userLocation: fairbanksCoord)
        XCTAssertFalse(gasResults.isEmpty, "Category search for 'Gas' must return local results")

        for result in gasResults.prefix(5) {
            let dist = result.distanceMiles(from: fairbanksCoord) ?? 999.0
            print("Local Gas Result: \(result.name), Distance: \(dist) mi, Lat: \(result.lat), Lon: \(result.lon)")
            XCTAssertTrue(dist < 50.0, "Expected local gas result within 50 miles, got \(dist) mi for \(result.name)")
        }
    }

    func testRouteToLocalSearchResult() {
        let routingService = RoutingService()
        let fairbanksCoord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let costcoGasCoord = CLLocationCoordinate2D(latitude: 64.8537575, longitude: -147.7104128)

        guard let route = routingService.calculateRoute(from: fairbanksCoord, to: costcoGasCoord, mode: "auto") else {
            XCTFail("Route returned nil")
            return
        }

        print(">>> ROUTE TO COSTCO GASOLINE: isFallback=\(route.isFallback), distance=\(route.totalDistanceMiles) mi, coords=\(route.coordinates.count), steps=\(route.steps.count)")
        XCTAssertFalse(route.isFallback, "Expected real road route, got fallback")
        XCTAssertTrue(route.totalDistanceMiles > 0.8 && route.totalDistanceMiles < 3.0, "Expected route distance around 1-2 miles")
        XCTAssertTrue(route.steps.count >= 2, "Expected multiple maneuvers")
    }

    func testIsUserOffRoute() {
        let routingService = RoutingService()
        let route = [
            CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200),
            CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200),
            CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200),
            CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
        ]

        // On-route point
        let onRoute = CLLocationCoordinate2D(latitude: 64.8415, longitude: -147.7200)
        XCTAssertFalse(routingService.isUserOffRoute(userLocation: onRoute, routeCoordinates: route, thresholdMeters: 40.0))

        // Slight deviation (10m east)
        let slightDev = CLLocationCoordinate2D(latitude: 64.8415, longitude: -147.7198)
        XCTAssertFalse(routingService.isUserOffRoute(userLocation: slightDev, routeCoordinates: route, thresholdMeters: 40.0))

        // Significant deviation (300m east)
        let farOff = CLLocationCoordinate2D(latitude: 64.8415, longitude: -147.7140)
        XCTAssertTrue(routingService.isUserOffRoute(userLocation: farOff, routeCoordinates: route, thresholdMeters: 40.0))

        // Windowed check with activeCoordIndex
        XCTAssertFalse(routingService.isUserOffRoute(userLocation: onRoute, routeCoordinates: route, thresholdMeters: 40.0, activeCoordIndex: 1))
        XCTAssertTrue(routingService.isUserOffRoute(userLocation: farOff, routeCoordinates: route, thresholdMeters: 40.0, activeCoordIndex: 1))
    }

    func testParseCoordinates() {
        let searchService = SearchService()

        let coord1 = searchService.parseCoordinates(query: "64.8436, -147.7215")
        XCTAssertNotNil(coord1)
        XCTAssertEqual(coord1?.latitude ?? 0, 64.8436, accuracy: 0.0001)
        XCTAssertEqual(coord1?.longitude ?? 0, -147.7215, accuracy: 0.0001)

        let coord2 = searchService.parseCoordinates(query: "  64.8569 ;  -147.8028 ")
        XCTAssertNotNil(coord2)
        XCTAssertEqual(coord2?.latitude ?? 0, 64.8569, accuracy: 0.0001)

        let invalid1 = searchService.parseCoordinates(query: "Fairbanks, AK")
        XCTAssertNil(invalid1)

        let invalid2 = searchService.parseCoordinates(query: "95.0, -147.0") // Latitude > 90
        XCTAssertNil(invalid2)
    }

    func testMetricDistanceFormatting() {
        let collegeCoord = CLLocationCoordinate2D(latitude: 64.8569, longitude: -147.8028)
        let result = SearchResult(id: 1, name: "Fairbanks Airport", lat: 64.8153, lon: -147.8564)

        let formattedMiles = result.formattedDistance(from: collegeCoord, useMetric: false)
        XCTAssertTrue(formattedMiles.contains("mi away") || formattedMiles.contains("ft away"))

        let formattedKm = result.formattedDistance(from: collegeCoord, useMetric: true)
        XCTAssertTrue(formattedKm.contains("km away") || formattedKm.contains("m away"))
    }

    func testExplicitRoutingFailureOnInvalidOrUnreachableCoordinates() {
        let service = RoutingService()
        let exp = expectation(description: "Routing Failure Expectation")

        DispatchQueue.global().async {
            // Unreachable coordinate in the open Pacific Ocean (no tiles or roads)
            let start = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            let unreachableOcean = CLLocationCoordinate2D(latitude: 20.0, longitude: -160.0)

            let route = service.calculateRoute(from: start, to: unreachableOcean, mode: "auto")

            // Critical audit requirement: Valhalla routing failures must return nil rather than synthetic routes
            XCTAssertNil(route, "Routing engine must return explicit failure (nil) for unreachable coordinates, never a synthetic placeholder route")
            exp.fulfill()
        }

        wait(for: [exp], timeout: 15.0)
    }

    func testReverseGeocodeNumericCasting() {
        let searchService = SearchService()
        // Fairbanks coordinate
        let coord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let resolved = searchService.reverseGeocode(coordinate: coord)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.lat ?? 0 > 60.0, "Expected resolved latitude in Alaska region")
    }

    func testOfflineDataManagerResolution() {
        let searchDbURL = OfflineDataManager.url(for: "search_index.db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: searchDbURL.path), "OfflineDataManager must resolve search_index.db")

        let styleURL = OfflineDataManager.url(for: "style.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: styleURL.path), "OfflineDataManager must resolve style.json")
    }

    func testReverseGeocodeBoundingAndSparseCoordinates() {
        let searchService = SearchService()
        // Point in the Pacific Ocean far from any indexed POIs
        let oceanCoord = CLLocationCoordinate2D(latitude: 20.0, longitude: -160.0)
        let startTime = Date()
        let resolved = searchService.reverseGeocode(coordinate: oceanCoord)
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, 0, "Sparse coordinate should return a Dropped Pin with id 0")
        XCTAssertTrue(elapsed < 1.0, "Reverse geocode on sparse coordinates must complete in under 1 second without full-table scan, took \(elapsed)s")
    }
}


