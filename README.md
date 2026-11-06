# MyOfflineMapApp

A high-performance, 100% offline navigation and mapping application for iOS modeled after Google Maps. Powered by MapLibre Native, Valhalla C++ routing engine, and SQLite FTS5 geocoding.

For comprehensive technical architecture, full file-by-file references, complete version history, and engineering deep dives, see [DOCUMENTATION.md](DOCUMENTATION.md).

## Features Modeled After Google Maps
- **Floating Pill Search Bar**: Autocomplete search with diacritic and tokenized prefix matching against local offline database.
- **Category Chips Carousel**: Instant 1-tap search for Gas, Coffee, Restaurants, Groceries, Parking, Hotels, and Hospitals.
- **Place Detail Cards**: Bottom sheet showing place details, distance, directions button, and quick navigation launch.
- **Multi-Modal Route Preview**: Switch seamlessly between Drive (`auto`), Walk (`pedestrian`), and Bike (`bicycle`) routing profiles with live duration, distance, and ETA calculations.
- **Turn-by-Turn Navigation HUD**: Iconic dark green navigation banner with maneuver turn arrows, countdown distances, next street names, and offline voice guidance (`AVSpeechSynthesizer`).
- **3D Navigation Follow Camera**: Dynamic 55° pitch perspective following heading and user location.
- **Live Route Simulation (Demo Mode)**: Test turn-by-turn driving, speedometers, and camera tracking right at your desk with 1x, 2x, and 5x speeds.
- **HUD Windshield Reflection Mode**: Pure OLED black, horizontally mirrored HUD mode for night dashboard reflection.
- **Automatic Off-Route Rerouting**: Detects perpendicular cross-track deviations (>35m) and recalculates routes automatically.
- **Long-Press to Drop Pin**: Long-press anywhere on the map to reverse-geocode and drop a marker.

## Project Directory Layout
```
OfflineMapProject/
├── LICENSE
├── README.md
├── DOCUMENTATION.md               # Complete architecture, file reference & history
├── .gitignore
├── data/                          # Offline data assets & extracts
│   ├── alaska_tiles.tar           # Regional binned & indexed Valhalla tiles
│   ├── north-america.pmtiles      # Offline vector tile archive (MapLibre)
│   ├── search_index.db            # Offline SQLite FTS5 geocoding index
│   ├── tile_weights.tsv.gz        # Regional tile weights
│   ├── valhalla_tiles.tar         # Full continental Valhalla archive
│   └── sources/                   # Natural Earth and shoreline polygons
├── tools/                         # Tile generation & pipeline utilities
│   └── planetiler.jar             # OpenMapTiles PMTiles generator
└── MyOfflineMapApp/               # iOS Swift Application
    ├── project.yml                # XcodeGen project specification
    ├── MyOfflineMapApp.xcodeproj/ # Xcode project & shared schemes
    ├── Resources/                 # App bundle assets, plists & configs
    │   ├── Assets.xcassets/       # AppIcon, AccentColor
    │   ├── Info.plist             # Background modes, permissions
    │   ├── MyOfflineMapApp.entitlements
    │   ├── PrivacyInfo.xcprivacy  # Apple Privacy Manifest
    │   ├── style.json             # MapLibre offline vector style
    │   └── valhalla.json          # Valhalla mobile routing configuration
    ├── Sources/                   # Application Swift source files
    │   ├── MyOfflineMapApp.swift  # App entry point
    │   ├── ContentView.swift      # Google Maps UI, turn-by-turn banner, sheets
    │   ├── MapView.swift          # MapLibre UIViewRepresentable & route styling
    │   ├── LocationManager.swift  # CoreLocation & telemetry
    │   ├── RoutingService.swift   # Valhalla navigation engine & voice guidance
    │   ├── SearchService.swift    # SQLite FTS5 geocoder
    │   └── OfflineDataManager.swift # Asset resolution & backup management
    └── Tests/
        └── MyOfflineMapAppTests/  # XCTest suite (style, search, routing)
```

## Architecture & Data Storage
- **Map Vector Tiles**: `data/north-america.pmtiles` read directly via MapLibre's native `pmtiles://file://` protocol.
- **Turn-by-Turn Routing Engine**: Embedded `Valhalla` C++ library with regional tile extracts (`data/alaska_tiles.tar`).
- **Offline Search Database**: `data/search_index.db` using SQLite FTS5 and memory-mapped queries (`PRAGMA mmap_size = 268435456`).
- **Storage Policy**: Large data files are placed in Application Support with `isExcludedFromBackup = true` to prevent iCloud backup bloat and adhere to App Store Review guidelines.

## Build Requirements
- Xcode 15.0+ / Xcode 16.0+
- iOS 17.0+ deployment target
- Swift 5.10 / 6.0 with strict concurrency checking enabled
- XcodeGen (`brew install xcodegen`)

## Regenerating the Xcode Project
```bash
cd MyOfflineMapApp
xcodegen generate
open MyOfflineMapApp.xcodeproj
```

## Attribution & Licenses
- Map data: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL)
- Vector tile schema: © [OpenMapTiles](https://openmaptiles.org/)
- Map rendering: MapLibre Native (BSD)
- Routing: Valhalla (MIT)
- Database: SQLite.swift (MIT)

