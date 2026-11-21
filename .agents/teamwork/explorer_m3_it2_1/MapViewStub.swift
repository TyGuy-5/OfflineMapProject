
import SwiftUI
import CoreLocation

public struct MapView: View {
    public var pmtilesURL: URL?
    public var destinationTitle: String?
    @Binding public var selectedCoordinate: CLLocationCoordinate2D?
    @Binding public var routeCoordinates: [CLLocationCoordinate2D]?
    @Binding public var simulatedUserCoordinate: CLLocationCoordinate2D?
    @Binding public var userLocationCenter: CLLocationCoordinate2D?
    @Binding public var zoomStep: Double?
    public var simulatedHeading: Double?
    public var isNavigating: Bool
    public var mapStyleName: String
    public var onMapTap: (() -> Void)?
    public var onLongPressCoordinate: ((CLLocationCoordinate2D) -> Void)?

    public init(
        pmtilesURL: URL? = nil,
        destinationTitle: String? = nil,
        selectedCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil),
        routeCoordinates: Binding<[CLLocationCoordinate2D]?> = .constant(nil),
        simulatedUserCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil),
        userLocationCenter: Binding<CLLocationCoordinate2D?> = .constant(nil),
        zoomStep: Binding<Double?> = .constant(nil),
        simulatedHeading: Double? = nil,
        isNavigating: Bool = false,
        mapStyleName: String = "standard",
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

    public var body: some View {
        Text("MapViewStub")
    }
}
