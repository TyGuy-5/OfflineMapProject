import Foundation
import CoreLocation

// Direct extract of SearchService.parseCoordinates logic for adversarial testing
func parseCoordinates(query: String) -> CLLocationCoordinate2D? {
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

var passed = 0
var failed = 0

func assertTest(_ name: String, _ condition: Bool) {
    if condition {
        passed += 1
        print("  ✅ [PASS] \(name)")
    } else {
        failed += 1
        print("  ❌ [FAIL] \(name)")
    }
}

print("Running Adversarial Stress Test Suite for Coordinate Parsing...")

// Empty and whitespace
assertTest("Empty string returns nil", parseCoordinates(query: "") == nil)
assertTest("Spaces only returns nil", parseCoordinates(query: "   \t\n  ") == nil)
assertTest("Degree symbols only returns nil", parseCoordinates(query: "° º ˚") == nil)

// Count of numbers
assertTest("Single number returns nil", parseCoordinates(query: "64.8436") == nil)
assertTest("Three numbers return nil", parseCoordinates(query: "64.8436, -147.7215, 12.34") == nil)

// Boundary coordinates
let northPole = parseCoordinates(query: "90.0, 0.0")
assertTest("North Pole 90, 0 is valid", northPole != nil && northPole!.latitude == 90.0 && northPole!.longitude == 0.0)

let southPole = parseCoordinates(query: "-90.0, 0.0")
assertTest("South Pole -90, 0 is valid", southPole != nil && southPole!.latitude == -90.0 && southPole!.longitude == 0.0)

let antimeridianEast = parseCoordinates(query: "0.0, 180.0")
assertTest("Antimeridian 0, 180 is valid", antimeridianEast != nil && antimeridianEast!.latitude == 0.0 && antimeridianEast!.longitude == 180.0)

let antimeridianWest = parseCoordinates(query: "0.0, -180.0")
assertTest("Antimeridian 0, -180 is valid", antimeridianWest != nil && antimeridianWest!.latitude == 0.0 && antimeridianWest!.longitude == -180.0)

assertTest("Latitude 90.0001 out of range returns nil", parseCoordinates(query: "90.0001, -147.7215") == nil)
assertTest("Latitude -90.0001 out of range returns nil", parseCoordinates(query: "-90.0001, -147.7215") == nil)
assertTest("Longitude 180.0001 out of range returns nil", parseCoordinates(query: "64.8436, 180.0001") == nil)
assertTest("Longitude -180.0001 out of range returns nil", parseCoordinates(query: "64.8436, -180.0001") == nil)

// Cardinal conflicts
assertTest("Two North cardinals return nil", parseCoordinates(query: "64.8436 N, 147.7215 N") == nil)
assertTest("Two South cardinals return nil", parseCoordinates(query: "64.8436 S, 147.7215 S") == nil)
assertTest("Two East cardinals return nil", parseCoordinates(query: "64.8436 E, 147.7215 E") == nil)
assertTest("Two West cardinals return nil", parseCoordinates(query: "64.8436 W, 147.7215 W") == nil)
assertTest("North and South cardinals return nil", parseCoordinates(query: "64.8436 N, 147.7215 S") == nil)
assertTest("East and West cardinals return nil", parseCoordinates(query: "64.8436 E, 147.7215 W") == nil)

// Correct Cardinal & Inverted
let buenosAires = parseCoordinates(query: "34.6037 S, 58.3816 W")
assertTest("Buenos Aires (S, W) correctly negative", buenosAires != nil && abs(buenosAires!.latitude - (-34.6037)) < 0.0001 && abs(buenosAires!.longitude - (-58.3816)) < 0.0001)

let inverted = parseCoordinates(query: "147.7215 W, 64.8436 N")
assertTest("Inverted Lon W, Lat N resolves lat/lon correctly", inverted != nil && abs(inverted!.latitude - 64.8436) < 0.0001 && abs(inverted!.longitude - (-147.7215)) < 0.0001)

let invertedEastSouth = parseCoordinates(query: "151.2093 E, 33.8688 S")
assertTest("Inverted Lon E, Lat S resolves lat/lon correctly", invertedEastSouth != nil && abs(invertedEastSouth!.latitude - (-33.8688)) < 0.0001 && abs(invertedEastSouth!.longitude - 151.2093) < 0.0001)

// Malicious / injection / garbage inputs
assertTest("SQL injection in coordinates rejected", parseCoordinates(query: "64.8436; DROP TABLE geocoder; -147.7215") == nil)
assertTest("HTML tags in coordinates rejected", parseCoordinates(query: "64.8436<script>, -147.7215") == nil)
assertTest("Trailing letters rejected", parseCoordinates(query: "64.8436 N -147.7215 W foo") == nil)
assertTest("Leading letters rejected", parseCoordinates(query: "bar 64.8436 N, 147.7215 W") == nil)
assertTest("Interleaved letters rejected", parseCoordinates(query: "64.8436abc, -147.7215") == nil)

// Separators and unicode variations
let slashCoord = parseCoordinates(query: "64.8436 / -147.7215")
assertTest("Slash separator parses correctly", slashCoord != nil && abs(slashCoord!.latitude - 64.8436) < 0.0001 && abs(slashCoord!.longitude - (-147.7215)) < 0.0001)

let tabCoord = parseCoordinates(query: "64.8436\t-147.7215")
assertTest("Tab separator parses correctly", tabCoord != nil && abs(tabCoord!.latitude - 64.8436) < 0.0001 && abs(tabCoord!.longitude - (-147.7215)) < 0.0001)

let newlineCoord = parseCoordinates(query: "64.8436\n-147.7215")
assertTest("Newline separator parses correctly", newlineCoord != nil && abs(newlineCoord!.latitude - 64.8436) < 0.0001 && abs(newlineCoord!.longitude - (-147.7215)) < 0.0001)

let unicodeDegree1 = parseCoordinates(query: "64.8436º, -147.7215º")
assertTest("Masculine ordinal indicator (º U+00BA) parses correctly", unicodeDegree1 != nil && abs(unicodeDegree1!.latitude - 64.8436) < 0.0001 && abs(unicodeDegree1!.longitude - (-147.7215)) < 0.0001)

let unicodeDegree2 = parseCoordinates(query: "64.8436˚, -147.7215˚")
assertTest("Ring above (˚ U+02DA) parses correctly", unicodeDegree2 != nil && abs(unicodeDegree2!.latitude - 64.8436) < 0.0001 && abs(unicodeDegree2!.longitude - (-147.7215)) < 0.0001)

let mixedDegreeAndCase = parseCoordinates(query: "64.8436˚ n; 147.7215º w")
assertTest("Mixed unicode and lowercase cardinals parses correctly", mixedDegreeAndCase != nil && abs(mixedDegreeAndCase!.latitude - 64.8436) < 0.0001 && abs(mixedDegreeAndCase!.longitude - (-147.7215)) < 0.0001)

let positiveExplicit = parseCoordinates(query: "+64.8436, +147.7215")
assertTest("Explicit plus signs parse correctly", positiveExplicit != nil && abs(positiveExplicit!.latitude - 64.8436) < 0.0001 && abs(positiveExplicit!.longitude - 147.7215) < 0.0001)

print("\n--- RESULTS: \(passed) Passed, \(failed) Failed ---")
if failed > 0 {
    exit(1)
}
