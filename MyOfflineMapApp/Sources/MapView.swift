import SwiftUI
import MapLibre

struct MapView: UIViewRepresentable {
    let pmtilesURL: URL
    
    func makeUIView(context: Context) -> MLNMapView {
        // Use .zero so SwiftUI handles the layout constraints perfectly
        let mapView = MLNMapView(frame: .zero)
        mapView.logoView.isHidden = true
        
        let centerCoordinate = CLLocationCoordinate2D(latitude: 45.5152, longitude: -122.6784)
        mapView.setCenter(centerCoordinate, zoomLevel: 12, animated: false)
        
        // 1. The Bulletproof Offline Style
        // This removes ALL dead external links for fonts and icons that were causing the crash.
        let localPMTilesURI = "pmtiles://" + pmtilesURL.absoluteString
        
        let offlineStyle = """
        {
          "version": 8,
          "name": "Offline Map",
          "sources": {
            "openmaptiles": {
              "type": "vector",
              "url": "\(localPMTilesURI)"
            }
          },
          "layers": [
            {
              "id": "background",
              "type": "background",
              "paint": { "background-color": "#f2f2f2" }
            },
            {
              "id": "water",
              "type": "fill",
              "source": "openmaptiles",
              "source-layer": "water",
              "paint": { "fill-color": "#a0c8f0" }
            },
            {
              "id": "roads",
              "type": "line",
              "source": "openmaptiles",
              "source-layer": "transportation",
              "paint": { "line-color": "#ffffff", "line-width": 2 }
            }
          ]
        }
        """
        
        do {
            let tempStyleURL = FileManager.default.temporaryDirectory.appendingPathComponent("offline_style.json")
            try offlineStyle.write(to: tempStyleURL, atomically: true, encoding: .utf8)
            mapView.styleURL = tempStyleURL
        } catch {
            print("Failed to write offline style: \(error)")
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MLNMapView, context: Context) {}
}
