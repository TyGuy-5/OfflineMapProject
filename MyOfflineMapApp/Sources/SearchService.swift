import Foundation
import CoreLocation
import SQLite
import SQLite3

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let lat: Double
    public let lon: Double

    public var category: String {
        let lower = name.lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        let gasKeywords: Set<String> = ["gas", "gasoline", "fuel", "oil", "petrol", "chevron", "shell", "exxon", "texaco", "bp", "mobil", "conoco", "tesoro"]
        let coffeeKeywords: Set<String> = ["coffee", "cafe", "espresso", "starbucks", "barista"]
        let foodKeywords: Set<String> = ["restaurant", "restaurants", "pizza", "diner", "grill", "burger", "burgers", "bar", "bakery", "kitchen", "pub", "bistro", "steakhouse", "taco", "sushi", "dining"]
        let hotelKeywords: Set<String> = ["hotel", "motel", "inn", "resort", "suites", "lodge", "hostel"]
        let parkingKeywords: Set<String> = ["parking", "garage"]
        let parkKeywords: Set<String> = ["park", "parks", "trail", "lake", "forest"]
        let hospitalKeywords: Set<String> = ["hospital", "clinic", "medical", "health", "doctor", "pharmacy", "infirmary"]
        let airportKeywords: Set<String> = ["airport", "airfield", "airstrip"]
        let groceryKeywords: Set<String> = [
            "grocery", "groceries", "supermarket", "supermarkets", "safeway",
            "walmart", "costco", "carrs", "kroger", "albertsons", "aldi",
            "sprouts", "bodega", "foodmart", "iga"
        ]

        let isFredMeyer = words.contains("fred") && words.contains("meyer")
        let isTraderJoes = words.contains("trader") && (words.contains("joe") || words.contains("joes"))
        let isWholeFoods = words.contains("whole") && (words.contains("foods") || words.contains("food"))

        if !words.isDisjoint(with: gasKeywords) {
            return "gas"
        } else if !words.isDisjoint(with: coffeeKeywords) {
            return "coffee"
        } else if !words.isDisjoint(with: foodKeywords) {
            return "food"
        } else if !words.isDisjoint(with: hotelKeywords) {
            return "hotel"
        } else if !words.isDisjoint(with: parkingKeywords) {
            return "parking"
        } else if !words.isDisjoint(with: parkKeywords) {
            return "park"
        } else if !words.isDisjoint(with: hospitalKeywords) {
            return "hospital"
        } else if !words.isDisjoint(with: airportKeywords) {
            return "airport"
        } else if !words.isDisjoint(with: groceryKeywords) || words.contains("market") || isFredMeyer || isTraderJoes || isWholeFoods {
            return "grocery"
        } else {
            return "place"
        }
    }

    public var iconName: String {
        switch category {
        case "gas": return "fuelpump.fill"
        case "coffee": return "cup.and.saucer.fill"
        case "food": return "fork.knife"
        case "hotel": return "bed.double.fill"
        case "parking": return "parkingsign.circle.fill"
        case "park": return "leaf.fill"
        case "hospital": return "cross.case.fill"
        case "airport": return "airplane"
        case "grocery": return "cart.fill"
        default: return "mappin.circle.fill"
        }
    }

    public func distanceMiles(from coord: CLLocationCoordinate2D?) -> Double? {
        guard let coord = coord else { return nil }
        let latRad = coord.latitude * .pi / 180.0
        let dx = (lon - coord.longitude) * 111320.0 * cos(latRad)
        let dy = (lat - coord.latitude) * 110540.0
        let meters = sqrt(dx * dx + dy * dy)
        return meters * 0.000621371
    }

    public func formattedDistance(from coord: CLLocationCoordinate2D?, useMetric: Bool = false) -> String {
        guard let miles = distanceMiles(from: coord) else {
            return String(format: "%.4f, %.4f", lat, lon)
        }
        if useMetric {
            let meters = miles * 1609.34
            if meters < 1000 {
                return "\(Int(meters)) m away"
            } else {
                return String(format: "%.1f km away", miles * 1.60934)
            }
        } else {
            if miles < 0.1 {
                return "\(Int(miles * 5280)) ft away"
            } else {
                return String(format: "%.1f mi away", miles)
            }
        }
    }
}

public final class SearchService: @unchecked Sendable, ObservableObject {
    private var db: Connection?
    private let queue = DispatchQueue(label: "com.offline.search", qos: .userInitiated)

    public init() {
        queue.async {
            self.connect()
        }
    }

    private func connect() {
        guard db == nil else { return }
        let dbURL = OfflineDataManager.url(for: "search_index.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            print("SearchService: search_index.db not found at \(dbURL.path)")
            return
        }
        do {
            let conn = try Connection(dbURL.path, readonly: true)
            try? conn.execute("PRAGMA query_only = ON;")
            try? conn.execute("PRAGMA mmap_size = 268435456;") // 256MB mmap
            self.db = conn
            print("SearchService: Connected to search_index.db with mmap enabled.")
        } catch {
            print("SearchService: Failed to connect to database: \(error)")
        }
    }

    private func performSearch(query: String, userLocation: CLLocationCoordinate2D? = nil) -> [SearchResult] {
        if self.db == nil {
            self.connect()
        }
        guard let db = self.db else { return [] }

        let nonAlphanumeric = CharacterSet.alphanumerics.inverted
        let tokens = query.components(separatedBy: nonAlphanumeric).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        let normalizedQuery = tokens.joined(separator: " ").lowercased()
        let searchQuery: String
        if normalizedQuery == "groceries" || normalizedQuery == "grocery" {
            searchQuery = "\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*"
        } else {
            searchQuery = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
        }
        var results: [SearchResult] = []

        if let user = userLocation {
            let latMin = user.latitude - 2.0
            let latMax = user.latitude + 2.0
            let lonMin = user.longitude - 3.5
            let lonMax = user.longitude + 3.5
            let cosLat = cos(user.latitude * .pi / 180.0)
            let cosLatSq = cosLat * cosLat

            let localSql = """
            SELECT rowid, name, lat, lon FROM geocoder 
            WHERE geocoder MATCH ? AND CAST(lat AS REAL) BETWEEN ? AND ? AND CAST(lon AS REAL) BETWEEN ? AND ? 
            ORDER BY ((CAST(lat AS REAL) - ?) * (CAST(lat AS REAL) - ?) + (CAST(lon AS REAL) - ?) * (CAST(lon AS REAL) - ?) * ?) ASC 
            LIMIT 50;
            """
            do {
                for row in try db.prepare(localSql, searchQuery, latMin, latMax, lonMin, lonMax, user.latitude, user.latitude, user.longitude, user.longitude, cosLatSq) {
                    let rLat = (row[2] as? Double) ?? (row[2] as? String).flatMap { Double($0) }
                    let rLon = (row[3] as? Double) ?? (row[3] as? String).flatMap { Double($0) }
                    if let rId = row[0] as? Int64,
                       let rName = row[1] as? String,
                       let lat = rLat,
                       let lon = rLon {
                        results.append(SearchResult(
                            id: rId,
                            name: rName,
                            lat: lat,
                            lon: lon
                        ))
                    }
                }
            } catch {
                print("SearchService: Local bounded search query failed: \(error)")
            }
        }

        if results.count < 20 {
            let globalSql = "SELECT rowid, name, lat, lon FROM geocoder WHERE geocoder MATCH ? LIMIT 50;"
            do {
                var existingIds = Set(results.map { $0.id })
                for row in try db.prepare(globalSql, searchQuery) {
                    let rLat = (row[2] as? Double) ?? (row[2] as? String).flatMap { Double($0) }
                    let rLon = (row[3] as? Double) ?? (row[3] as? String).flatMap { Double($0) }
                    if let rId = row[0] as? Int64,
                       let rName = row[1] as? String,
                       let lat = rLat,
                       let lon = rLon {
                        if !existingIds.contains(rId) {
                            existingIds.insert(rId)
                            results.append(SearchResult(
                                id: rId,
                                name: rName,
                                lat: lat,
                                lon: lon
                            ))
                        }
                    }
                }
            } catch {
                print("SearchService: Global search query failed for '\(searchQuery)': \(error)")
            }
        }

        if let userLoc = userLocation {
            results.sort {
                let d1 = $0.distanceMiles(from: userLoc) ?? Double.greatestFiniteMagnitude
                let d2 = $1.distanceMiles(from: userLoc) ?? Double.greatestFiniteMagnitude
                return d1 < d2
            }
        }

        return Array(results.prefix(25))
    }

    /// Primary search with FTS5 prefix matching and distance-biased ranking
    public func search(query: String, userLocation: CLLocationCoordinate2D? = nil) -> [SearchResult] {
        if let coord = parseCoordinates(query: query) {
            return [SearchResult(id: -1, name: String(format: "Location (%.4f, %.4f)", coord.latitude, coord.longitude), lat: coord.latitude, lon: coord.longitude)]
        }

        return queue.sync {
            self.performSearch(query: query, userLocation: userLocation)
        }
    }

    public func searchAsync(query: String, userLocation: CLLocationCoordinate2D? = nil) async -> [SearchResult] {
        if let coord = parseCoordinates(query: query) {
            return [SearchResult(id: -1, name: String(format: "Location (%.4f, %.4f)", coord.latitude, coord.longitude), lat: coord.latitude, lon: coord.longitude)]
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                let results = self.performSearch(query: query, userLocation: userLocation)
                continuation.resume(returning: results)
            }
        }
    }

    public func reverseGeocodeAsync(coordinate: CLLocationCoordinate2D) async -> SearchResult? {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.performReverseGeocode(coordinate: coordinate)
                continuation.resume(returning: result)
            }
        }
    }

    /// Offline reverse geocoding: finds closest indexed point to a coordinate (e.g. for long-press)
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult? {
        return queue.sync {
            self.performReverseGeocode(coordinate: coordinate)
        }
    }

    private func performReverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult? {
        if self.db == nil {
            self.connect()
        }
        guard let db = self.db else {
            return SearchResult(
                id: 0,
                name: String(format: "Dropped Pin (%.4f, %.4f)", coordinate.latitude, coordinate.longitude),
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
        }

        // Tight initial bounding box (~0.008 deg ~ 800m)
        let latMin = coordinate.latitude - 0.008
        let latMax = coordinate.latitude + 0.008
        let lonMin = coordinate.longitude - 0.008
        let lonMax = coordinate.longitude + 0.008

        let sql = "SELECT rowid, name, lat, lon FROM geocoder WHERE CAST(lat AS REAL) BETWEEN ? AND ? AND CAST(lon AS REAL) BETWEEN ? AND ? LIMIT 250;"

        final class ProgressBox {
            var ticks = 0
            let startTime = CFAbsoluteTimeGetCurrent()
        }
        let box = ProgressBox()
        let boxPtr = Unmanaged.passUnretained(box).toOpaque()
        // Provide generous opcode budget (~25M opcodes) across full dataset while enforcing <0.7s deadline for sparse areas
        sqlite3_progress_handler(db.handle, 10000, { ptr in
            guard let ptr = ptr else { return 0 }
            let b = Unmanaged<ProgressBox>.fromOpaque(ptr).takeUnretainedValue()
            b.ticks += 1
            if b.ticks > 2500 || (CFAbsoluteTimeGetCurrent() - b.startTime) > 0.65 {
                return 1
            }
            return 0
        }, boxPtr)
        defer {
            sqlite3_progress_handler(db.handle, 0, nil, nil)
        }

        var closest: SearchResult?
        var minDistanceMeters = Double.greatestFiniteMagnitude
        let latRad = coordinate.latitude * .pi / 180.0
        let cosLat = cos(latRad)

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db.handle, sql, -1, &statement, nil) == SQLITE_OK {
            defer {
                sqlite3_finalize(statement)
            }
            sqlite3_bind_double(statement, 1, latMin)
            sqlite3_bind_double(statement, 2, latMax)
            sqlite3_bind_double(statement, 3, lonMin)
            sqlite3_bind_double(statement, 4, lonMax)

            while sqlite3_step(statement) == SQLITE_ROW {
                let rId = sqlite3_column_int64(statement, 0)
                let rName: String
                if let cStr = sqlite3_column_text(statement, 1) {
                    rName = String(cString: cStr)
                } else {
                    rName = "Point of Interest"
                }
                let lat = sqlite3_column_double(statement, 2)
                let lon = sqlite3_column_double(statement, 3)

                let dx = (lon - coordinate.longitude) * 111320.0 * cosLat
                let dy = (lat - coordinate.latitude) * 110540.0
                let d = sqrt(dx * dx + dy * dy)
                if d < minDistanceMeters {
                    minDistanceMeters = d
                    closest = SearchResult(id: rId, name: rName, lat: lat, lon: lon)
                }
            }
        }

        return closest ?? SearchResult(
            id: 0,
            name: String(format: "Dropped Pin (%.4f, %.4f)", coordinate.latitude, coordinate.longitude),
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )
    }

    /// Detect and parse coordinates in search bar (e.g. "64.8569, -147.8028", "64.8436° N, 147.7215° W")
    public func parseCoordinates(query: String) -> CLLocationCoordinate2D? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"([+-]?\d+(?:\.\d+)?)\s*[°º˚]?\s*([NSEWnsew])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsString = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))
        guard matches.count == 2 else { return nil }

        // Ensure remaining non-matched text contains only allowed delimiter characters
        let nonCoord = regex.stringByReplacingMatches(
            in: trimmed,
            options: [],
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        )
        let allowedSeparators = CharacterSet(charactersIn: ",; \t\n°º˚/")
        guard nonCoord.unicodeScalars.allSatisfy({ allowedSeparators.contains($0) }) else { return nil }

        struct CoordComponent {
            let value: Double
            let cardinal: Character?
        }

        var components: [CoordComponent] = []
        for match in matches {
            let valRange = match.range(at: 1)
            guard valRange.location != NSNotFound,
                  let val = Double(nsString.substring(with: valRange)) else { return nil }

            var card: Character? = nil
            let cardRange = match.range(at: 2)
            if cardRange.location != NSNotFound {
                let cardStr = nsString.substring(with: cardRange).uppercased()
                if let first = cardStr.first {
                    card = first
                }
            }
            components.append(CoordComponent(value: val, cardinal: card))
        }

        guard components.count == 2 else { return nil }
        let c0 = components[0]
        let c1 = components[1]
        var lat: Double?
        var lon: Double?

        if let dir0 = c0.cardinal, let dir1 = c1.cardinal {
            if (dir0 == "N" || dir0 == "S") && (dir1 == "E" || dir1 == "W") {
                lat = (dir0 == "S") ? -abs(c0.value) : abs(c0.value)
                lon = (dir1 == "W") ? -abs(c1.value) : abs(c1.value)
            } else if (dir0 == "E" || dir0 == "W") && (dir1 == "N" || dir1 == "S") {
                lon = (dir0 == "W") ? -abs(c0.value) : abs(c0.value)
                lat = (dir1 == "S") ? -abs(c1.value) : abs(c1.value)
            } else {
                return nil
            }
        } else if let dir0 = c0.cardinal {
            if dir0 == "N" || dir0 == "S" {
                lat = (dir0 == "S") ? -abs(c0.value) : abs(c0.value)
                lon = c1.value
            } else {
                lon = (dir0 == "W") ? -abs(c0.value) : abs(c0.value)
                lat = c1.value
            }
        } else if let dir1 = c1.cardinal {
            if dir1 == "N" || dir1 == "S" {
                lat = (dir1 == "S") ? -abs(c1.value) : abs(c1.value)
                lon = c0.value
            } else {
                lon = (dir1 == "W") ? -abs(c1.value) : abs(c1.value)
                lat = c0.value
            }
        } else {
            lat = c0.value
            lon = c1.value
        }

        guard let finalLat = lat, let finalLon = lon,
              finalLat >= -90.0 && finalLat <= 90.0,
              finalLon >= -180.0 && finalLon <= 180.0 else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: finalLat, longitude: finalLon)
    }
}
