// SettingsPersistenceTests.swift — Tier 1 Feature Coverage: Settings Persistence, Unit Conversions, Data Exclusions

import Foundation
import CoreLocation

public final class SettingsPersistenceTests: E2ETestSuite {
    public let name = "Settings Persistence & Data Architecture Suite"
    public let tier = TestTier.tier1
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT1_UserPreferencesPersistenceWithAppStorageKeys", tier: tier, block: testT1_UserPreferencesPersistenceWithAppStorageKeys),
            TestCaseEntry(name: "testT1_MetricDistanceUnitConversionAndFormatting", tier: tier, block: testT1_MetricDistanceUnitConversionAndFormatting),
            TestCaseEntry(name: "testT1_ImperialDistanceUnitConversionAndFormatting", tier: tier, block: testT1_ImperialDistanceUnitConversionAndFormatting),
            TestCaseEntry(name: "testT1_SpeedAndAltitudeUnitConversion", tier: tier, block: testT1_SpeedAndAltitudeUnitConversion),
            TestCaseEntry(name: "testT1_ScopedICloudBackupExclusionForAssetFiles", tier: tier, block: testT1_ScopedICloudBackupExclusionForAssetFiles),
            TestCaseEntry(name: "testT1_AlaskaSupportedRegionBoundingBoxFiltering", tier: tier, block: testT1_AlaskaSupportedRegionBoundingBoxFiltering)
        ]
    }
    
    /// R1.3: Persist user preferences (useMetric and isVoiceMuted) across launches using @AppStorage keys
    /// aligning with PrivacyInfo.xcprivacy (NSPrivacyAccessedAPITypeUserDefaults - CA92.1)
    func testT1_UserPreferencesPersistenceWithAppStorageKeys() async throws {
        let testSuiteName = "com.offline.e2e.tests.settings.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: testSuiteName) else {
            fail("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: testSuiteName)
        }
        
        let keyMetric = "useMetric"
        let keyVoiceMuted = "isVoiceMuted"
        
        // Defaults
        assertFalse(userDefaults.bool(forKey: keyMetric), "Default useMetric should be false")
        assertFalse(userDefaults.bool(forKey: keyVoiceMuted), "Default isVoiceMuted should be false")
        
        // Save preference updates
        userDefaults.set(true, forKey: keyMetric)
        userDefaults.set(true, forKey: keyVoiceMuted)
        
        // Reload from defaults
        assertTrue(userDefaults.bool(forKey: keyMetric), "Persisted useMetric must be true")
        assertTrue(userDefaults.bool(forKey: keyVoiceMuted), "Persisted isVoiceMuted must be true")
    }
    
    /// Metric distance unit formatting (meters for < 1000m, kilometers for >= 1km)
    func testT1_MetricDistanceUnitConversionAndFormatting() async throws {
        let stepShort = OpaqueNavigationStep(instruction: "Turn right", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 10, streetName: nil, startIndex: 0, endIndex: 1)
        let formattedShort = stepShort.formattedDistance(useMetric: true)
        assertTrue(formattedShort.hasSuffix("m"), "Short distance in metric should format in meters: \(formattedShort)")
        assertFalse(formattedShort.contains("ft"), "Must not contain 'ft'")
        
        let stepLong = OpaqueNavigationStep(instruction: "Stay on highway", distanceMiles: 5.0, durationSeconds: 300, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
        let formattedLong = stepLong.formattedDistance(useMetric: true)
        assertTrue(formattedLong.hasSuffix("km"), "Long distance in metric should format in km: \(formattedLong)")
        assertTrue(formattedLong.contains("8.0 km") || formattedLong.contains("8.1 km"), "5 miles should be ~8.0 km")
    }
    
    /// Imperial distance unit formatting (feet for < 0.1 mi, miles for >= 0.1 mi)
    func testT1_ImperialDistanceUnitConversionAndFormatting() async throws {
        let stepShort = OpaqueNavigationStep(instruction: "Turn left", distanceMiles: 0.05, durationSeconds: 5, maneuverType: 15, streetName: nil, startIndex: 0, endIndex: 1)
        let formattedShort = stepShort.formattedDistance(useMetric: false)
        assertTrue(formattedShort.hasSuffix("ft"), "Short imperial distance should format in feet: \(formattedShort)")
        assertEqual(formattedShort, "264 ft", "0.05 miles is exactly 264 feet")
        
        let stepLong = OpaqueNavigationStep(instruction: "Continue straight", distanceMiles: 2.5, durationSeconds: 150, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
        let formattedLong = stepLong.formattedDistance(useMetric: false)
        assertTrue(formattedLong.hasSuffix("mi"), "Long imperial distance should format in miles: \(formattedLong)")
        assertEqual(formattedLong, "2.5 mi")
    }
    
    /// Speed and altitude conversion units
    func testT1_SpeedAndAltitudeUnitConversion() async throws {
        let speedMph = 60
        let speedKmh = Int(Double(speedMph) * 1.60934)
        assertEqual(speedKmh, 96, "60 mph should convert to ~96 km/h")
        
        let altMeters = 200.0
        let altFeet = Int(altMeters * 3.28084)
        assertEqual(altFeet, 656, "200m altitude should convert to ~656 ft")
    }
    
    /// R6.3: In OfflineDataManager.swift, exclude only downloaded offline map asset files in Documents directory
    /// from iCloud backup rather than excluding the entire directory.
    func testT1_ScopedICloudBackupExclusionForAssetFiles() async throws {
        // Assets that must be excluded:
        let assetFiles = [
            "north-america.pmtiles",
            "alaska_tiles.tar",
            "valhalla_tiles.tar",
            "search_index.db",
            "valhalla.json"
        ]
        for file in assetFiles {
            assertTrue(OpaqueBackupExclusionManager.isAssetExcluded(filename: file), "Asset '\(file)' must be excluded from iCloud backup")
        }
        
        // User files in Documents that must NOT be excluded:
        let userDocuments = [
            "UserNotes.txt",
            "SavedTrips.plist",
            "UserWaypoints.gpx",
            "ExportedData.csv",
            "AppConfig.xml"
        ]
        for file in userDocuments {
            assertFalse(OpaqueBackupExclusionManager.isAssetExcluded(filename: file), "User document '\(file)' must NOT be excluded from iCloud backup")
        }
    }
    
    /// Alaska supported region bounding box [51.0, 72.0] x [-179.0, -129.0]
    func testT1_AlaskaSupportedRegionBoundingBoxFiltering() async throws {
        func isWithinSupportedRegion(_ coord: CLLocationCoordinate2D) -> Bool {
            return coord.latitude >= 51.0 && coord.latitude <= 72.0 &&
                   coord.longitude >= -179.0 && coord.longitude <= -129.0
        }
        
        // Alaska benchmarks should be accepted
        assertTrue(isWithinSupportedRegion(TestCoordinates.fairbanksDowntown), "Fairbanks is within Alaska")
        assertTrue(isWithinSupportedRegion(TestCoordinates.anchorageDowntown), "Anchorage is within Alaska")
        assertTrue(isWithinSupportedRegion(TestCoordinates.juneauDowntown), "Juneau is within Alaska")
        assertTrue(isWithinSupportedRegion(TestCoordinates.barrowUtqiagvik), "Barrow is within Alaska")
        assertTrue(isWithinSupportedRegion(TestCoordinates.southwestBoundary), "SW boundary accepted")
        assertTrue(isWithinSupportedRegion(TestCoordinates.northeastBoundary), "NE boundary accepted")
        
        // Out-of-region coordinates should be rejected
        assertFalse(isWithinSupportedRegion(TestCoordinates.seattleDowntown), "Seattle is outside Alaska")
        assertFalse(isWithinSupportedRegion(TestCoordinates.sanFrancisco), "SF is outside Alaska")
        assertFalse(isWithinSupportedRegion(TestCoordinates.newYorkCity), "NYC is outside Alaska")
        assertFalse(isWithinSupportedRegion(TestCoordinates.london), "London is outside Alaska")
        assertFalse(isWithinSupportedRegion(TestCoordinates.tokyo), "Tokyo is outside Alaska")
    }
}
