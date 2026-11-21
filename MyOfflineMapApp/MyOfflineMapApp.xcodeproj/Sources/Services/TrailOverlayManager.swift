import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(MapLibre)
import MapLibre
#else
// Standalone declarations when MapLibre framework is not linked (e.g. macOS test runner)
public class MLNStyle {
    public var layers: [MLNStyleLayer] = []
    public var sources: Set<MLNSource> = []
    
    public init(layers: [MLNStyleLayer] = []) {
        self.layers = layers
    }
    
    public func layer(withIdentifier identifier: String) -> MLNStyleLayer? {
        return layers.first { $0.identifier == identifier }
    }
    
    public func source(withIdentifier identifier: String) -> MLNSource? {
        return sources.first { $0.identifier == identifier }
    }
    
    public func addSource(_ source: MLNSource) {
        sources.insert(source)
    }
    
    public func removeSource(_ source: MLNSource) {
        sources.remove(source)
    }
    
    public func addLayer(_ layer: MLNStyleLayer) {
        layers.append(layer)
    }
    
    public func insertLayer(_ layer: MLNStyleLayer, below sibling: MLNStyleLayer) {
        if let idx = layers.firstIndex(where: { $0.identifier == sibling.identifier }) {
            layers.insert(layer, at: idx)
        } else {
            layers.append(layer)
        }
    }
    
    public func insertLayer(_ layer: MLNStyleLayer, above sibling: MLNStyleLayer) {
        if let idx = layers.firstIndex(where: { $0.identifier == sibling.identifier }) {
            layers.insert(layer, at: idx + 1)
        } else {
            layers.append(layer)
        }
    }
    
    public func removeLayer(_ layer: MLNStyleLayer) {
        layers.removeAll { $0.identifier == layer.identifier }
    }
}

public class MLNSource: Hashable {
    public let identifier: String
    public init(identifier: String) {
        self.identifier = identifier
    }
    public static func == (lhs: MLNSource, rhs: MLNSource) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

public class MLNShapeSource: MLNSource {
    public var url: URL?
    public var shape: Any?
    public init(identifier: String, url: URL?, options: [String: Any]? = nil) {
        self.url = url
        super.init(identifier: identifier)
    }
    public init(identifier: String, shape: Any?, options: [String: Any]? = nil) {
        self.shape = shape
        super.init(identifier: identifier)
    }
}

public class MLNStyleLayer {
    public let identifier: String
    public init(identifier: String) {
        self.identifier = identifier
    }
}

public class MLNVectorStyleLayer: MLNStyleLayer {
    public var sourceIdentifier: String?
    public var sourceLayerIdentifier: String?
    public var predicate: NSPredicate?
    public init(identifier: String, source: MLNSource) {
        self.sourceIdentifier = source.identifier
        super.init(identifier: identifier)
    }
}

public class MLNLineStyleLayer: MLNVectorStyleLayer {
    public var lineColor: NSExpression?
    public var lineWidth: NSExpression?
    public var lineDashPattern: NSExpression?
    public var lineCap: NSExpression?
    public var lineJoin: NSExpression?
    public var lineOpacity: NSExpression?
}

public class MLNSymbolStyleLayer: MLNVectorStyleLayer {}

#if !canImport(UIKit)
public class UIColor {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat
    
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    public static let black = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
    public func withAlphaComponent(_ alpha: CGFloat) -> UIColor {
        return UIColor(red: self.red, green: self.green, blue: self.blue, alpha: alpha)
    }
}
#endif
#endif

/// Manages MapLibre overlay rendering for downloaded regional trails and programmatic basemap restyling.
@MainActor
public class TrailOverlayManager {
    public static let shared = TrailOverlayManager()
    
    // Unique source and layer identifiers
    public static let overlaySourceIdentifier = "downloaded-regional-trails-source"
    public static let casingLayerIdentifier = "downloaded-trails-casing"
    public static let orangeLineLayerIdentifier = "downloaded-trails-orange"
    
    // High-contrast orange: #FC4C02 (252, 76, 2)
    public static let trailOrangeColor = UIColor(red: 252.0 / 255.0, green: 76.0 / 255.0, blue: 2.0 / 255.0, alpha: 1.0)
    public static let casingColor = UIColor.black.withAlphaComponent(0.6)
    public static let defaultDashPattern: [Double] = [2.0, 2.0]
    
    public init() {}
    
    /// Applies downloaded GeoJSON trails to the given MapLibre style as a unified high-contrast dashed overlay.
    public func applyTrailOverlay(to style: MLNStyle, geoJSONURLs: [URL]) {
        // Remove existing overlay layers and source first to guarantee clean update
        removeTrailOverlay(from: style)
        
        guard !geoJSONURLs.isEmpty else { return }
        
        // 1. Merge features from all GeoJSON URLs into a single combined FeatureCollection
        var combinedFeaturesData: Data? = nil
        if geoJSONURLs.count == 1, let firstURL = geoJSONURLs.first, let data = try? Data(contentsOf: firstURL) {
            combinedFeaturesData = data
        } else {
            var allFeatures: [GeoJSONFeature] = []
            let decoder = JSONDecoder()
            for url in geoJSONURLs {
                if let data = try? Data(contentsOf: url),
                   let collection = try? decoder.decode(GeoJSONFeatureCollection.self, from: data) {
                    allFeatures.append(contentsOf: collection.features)
                }
            }
            if !allFeatures.isEmpty {
                let combinedCollection = GeoJSONFeatureCollection(features: allFeatures)
                combinedFeaturesData = try? JSONEncoder().encode(combinedCollection)
            }
        }
        
        guard let validData = combinedFeaturesData else { return }
        
        // 2. Create MLNShapeSource from combined GeoJSON
        let shapeSource: MLNShapeSource
        #if canImport(MapLibre)
        do {
            let shape = try MLNShape(data: validData, encoding: String.Encoding.utf8.rawValue)
            shapeSource = MLNShapeSource(identifier: Self.overlaySourceIdentifier, shape: shape, options: nil)
        } catch {
            return
        }
        #else
        shapeSource = MLNShapeSource(identifier: Self.overlaySourceIdentifier, shape: validData)
        #endif
        
        style.addSource(shapeSource)
        
        // 3. Dark casing layer (provides contrast against snow, sand, or roads)
        let casingLayer = MLNLineStyleLayer(identifier: Self.casingLayerIdentifier, source: shapeSource)
        casingLayer.lineColor = NSExpression(forConstantValue: Self.casingColor)
        casingLayer.lineWidth = NSExpression(forConstantValue: 4.5)
        casingLayer.lineCap = NSExpression(forConstantValue: "round")
        casingLayer.lineJoin = NSExpression(forConstantValue: "round")
        casingLayer.lineOpacity = NSExpression(forConstantValue: 0.8)
        
        // 4. Primary high-contrast orange dashed layer (#FC4C02)
        let orangeLayer = MLNLineStyleLayer(identifier: Self.orangeLineLayerIdentifier, source: shapeSource)
        orangeLayer.lineColor = NSExpression(forConstantValue: Self.trailOrangeColor)
        orangeLayer.lineWidth = NSExpression(forConstantValue: 3.0)
        orangeLayer.lineDashPattern = NSExpression(forConstantValue: Self.defaultDashPattern)
        orangeLayer.lineCap = NSExpression(forConstantValue: "round")
        orangeLayer.lineJoin = NSExpression(forConstantValue: "round")
        orangeLayer.lineOpacity = NSExpression(forConstantValue: 1.0)
        
        // 5. Position below symbol layers (labels and icons remain visible on top)
        if let firstSymbolLayer = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
            style.insertLayer(casingLayer, below: firstSymbolLayer)
            style.insertLayer(orangeLayer, above: casingLayer)
        } else {
            style.addLayer(casingLayer)
            style.addLayer(orangeLayer)
        }
    }
    
    /// Removes the downloaded trails overlay from the MapLibre style.
    public func removeTrailOverlay(from style: MLNStyle) {
        if let orangeLayer = style.layer(withIdentifier: Self.orangeLineLayerIdentifier) {
            style.removeLayer(orangeLayer)
        }
        if let casingLayer = style.layer(withIdentifier: Self.casingLayerIdentifier) {
            style.removeLayer(casingLayer)
        }
        if let source = style.source(withIdentifier: Self.overlaySourceIdentifier) {
            style.removeSource(source)
        }
    }
    
    /// Programmatic safeguard: Enforces #FC4C02 dashed styling on any path or track layers in the basemap.
    public func applyBasemapTrailRestylingSafeguard(to style: MLNStyle) {
        for layer in style.layers {
            guard let lineLayer = layer as? MLNLineStyleLayer else { continue }
            
            let id = lineLayer.identifier.lowercased()
            let sourceLayer = (lineLayer.sourceLayerIdentifier ?? "").lowercased()
            
            // Match trail, path, or track layers
            let isTrailLayer = id.contains("trail") ||
                               id.contains("path") ||
                               id.contains("track") ||
                               id.contains("footway") ||
                               id.contains("cycleway") ||
                               (sourceLayer == "transportation" && (id.contains("path") || id.contains("track")))
            
            // Skip casing layer from receiving orange color
            if isTrailLayer && !id.contains("casing") {
                lineLayer.lineColor = NSExpression(forConstantValue: Self.trailOrangeColor)
                lineLayer.lineDashPattern = NSExpression(forConstantValue: Self.defaultDashPattern)
                lineLayer.lineCap = NSExpression(forConstantValue: "round")
                lineLayer.lineJoin = NSExpression(forConstantValue: "round")
            }
        }
    }
}
