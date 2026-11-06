# Tools & Utilities

This directory contains build tools and offline pipeline utilities for the offline map project.

---

## Utilities

### `planetiler.jar`
[Planetiler](https://github.com/onthegomap/planetiler) is a fast OpenMapTiles vector tile profile generator used to convert OpenStreetMap `.osm.pbf` extracts into `.pmtiles` archives.

- **Git LFS**: Tracked via Git Large File Storage (Git LFS) as specified in `.gitattributes`.
- **Usage Example**:
  ```bash
  java -Xmx8g -jar tools/planetiler.jar \
    --osm-path=data/alaska-latest.osm.pbf \
    --output=data/alaska.pmtiles \
    --download
  ```
