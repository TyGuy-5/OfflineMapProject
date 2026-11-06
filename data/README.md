# Offline Data Directory

This directory stores the offline geospatial assets, vector map tiles, routing graphs, and search databases used by `MyOfflineMapApp`.

> **Note**: Due to their multi-gigabyte sizes, large binary data files (`*.pmtiles`, `*.tar`, `*.db`, `*.zip`) are ignored by Git and should not be committed to source control.

---

## Required Data Assets

| File / Directory | Size | Description |
|------------------|------|-------------|
| `north-america.pmtiles` | ~9.8 GB | OpenMapTiles vector tile archive read directly via MapLibre's `pmtiles://file://` protocol. |
| `search_index.db` | ~5.8 GB | SQLite FTS5 spatial and tokenized geocoding index for place autocomplete and reverse geocoding. |
| `alaska_tiles.tar` | ~64 MB | Pre-binned, indexed Valhalla routing graph extract for Alaska turn-by-turn navigation. |
| `valhalla_tiles.tar` | ~76 GB | Full continental Valhalla routing graph archive. |
| `tile_weights.tsv.gz` | ~5.7 MB | Regional tile weighting metadata for routing optimization. |
| `sources/` | Directory | Upstream geographic boundaries and vector polygons (`natural_earth_vector.sqlite.zip`, `water-polygons-split-3857.zip`). |

---

## Runtime Resolution

At runtime, `OfflineDataManager.swift` resolves these assets following a tiered priority cascade:
1. **Application Support**: Standard on-device container for production downloads.
2. **Documents Directory**: For user-transferred files (AirDrop, Files app, iTunes File Sharing).
3. **Workspace `data/`**: Development, Simulator, and unit test execution environment.
4. **App Bundle / Resources**: Embedded fallback assets.

All files stored or unpacked into on-device application storage are automatically marked with `isExcludedFromBackup = true` to prevent iCloud backup bloat in compliance with Apple App Store Review Guidelines.
