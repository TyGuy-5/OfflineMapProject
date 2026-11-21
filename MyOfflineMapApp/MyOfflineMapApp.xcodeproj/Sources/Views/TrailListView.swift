import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI view for viewing, importing, selecting, and deleting GPX trails.
public struct TrailListView: View {
    
    // MARK: - Properties
    
    @ObservedObject public var trailManager: TrailManager
    public var selectedTrail: GPXTrack?
    public var onSelectTrail: ((GPXTrack) -> Void)?
    public var onDismiss: (() -> Void)?
    
    // MARK: - Local State
    
    @State private var isShowingFileImporter: Bool = false
    @State private var trailToDelete: GPXTrack? = nil
    @State private var isShowingDeleteConfirmation: Bool = false
    @State private var activeErrorMessage: String? = nil
    
    // MARK: - Initialization
    
    public init(
        trailManager: TrailManager,
        selectedTrail: GPXTrack? = nil,
        onSelectTrail: ((GPXTrack) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.trailManager = trailManager
        self.selectedTrail = selectedTrail
        self.onSelectTrail = onSelectTrail
        self.onDismiss = onDismiss
    }
    
    // MARK: - Body
    
    public var body: some View {
        NavigationStack {
            ZStack {
                #if os(iOS)
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                #else
                Color.gray.opacity(0.1)
                    .ignoresSafeArea()
                #endif
                
                if trailManager.isLoading && trailManager.importedTrails.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading Trails...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if trailManager.importedTrails.isEmpty {
                    emptyStateView
                } else {
                    trailListContent
                }
            }
            .navigationTitle("GPX Trails")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let dismiss = onDismiss {
                        Button("Done", action: dismiss)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Import GPX", systemImage: "plus.circle.fill")
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: Self.gpxContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleFileImportResult(result)
            }
            .confirmationDialog(
                "Delete Trail",
                isPresented: $isShowingDeleteConfirmation,
                presenting: trailToDelete
            ) { track in
                Button("Delete '\(track.name)'", role: .destructive) {
                    Task {
                        do {
                            try await trailManager.deleteTrail(track)
                        } catch {
                            activeErrorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { track in
                Text("Are you sure you want to delete '\(track.name)'? This removes the file from local storage.")
            }
            .alert("Error", isPresented: Binding(
                get: { activeErrorMessage != nil || trailManager.errorMessage != nil },
                set: { if !$0 { activeErrorMessage = nil; trailManager.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    activeErrorMessage = nil
                    trailManager.errorMessage = nil
                }
            } message: {
                Text(activeErrorMessage ?? trailManager.errorMessage ?? "An unknown error occurred.")
            }
            .refreshable {
                await trailManager.reload()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var trailListContent: some View {
        List {
            Section {
                ForEach(trailManager.importedTrails) { track in
                    trailRow(for: track)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectTrail?(track)
                            onDismiss?()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                trailToDelete = track
                                isShowingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("Imported Tracks (\(trailManager.importedTrails.count))")
            } footer: {
                Text("GPX files stored in Documents/Trails/. Swipe left on a trail to delete it.")
            }
        }
    }
    
    private func trailRow(for track: GPXTrack) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.hiking")
                .font(.title2)
                .foregroundColor(isSelected(track) ? .accentColor : .orange)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(track.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if isSelected(track) {
                        Text("Active")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 12) {
                    Label(formatDistance(track.totalDistance), systemImage: "arrow.left.and.right")
                    Label(formatElevation(track.elevationGain), systemImage: "arrow.up.right")
                    Label("\(track.points.count) pts", systemImage: "point.filled.topleft.down.curvedto.point.bottomright.up")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if let date = track.date {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isSelected(track) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            
            Text("No GPX Trails Found")
                .font(.title2.bold())
            
            Text("Import trails by tapping 'Import GPX' or drop .gpx files directly into Documents/Trails/ in the Files app.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                isShowingFileImporter = true
            } label: {
                Label("Import GPX File", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Helpers
    
    private func isSelected(_ track: GPXTrack) -> Bool {
        return selectedTrail?.id == track.id
    }
    
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                do {
                    let tracks = try await trailManager.importTrails(from: urls)
                    if let first = tracks.first {
                        onSelectTrail?(first)
                    }
                } catch {
                    activeErrorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            activeErrorMessage = error.localizedDescription
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000.0 {
            return String(format: "%.2f km", meters / 1000.0)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
    
    private func formatElevation(_ meters: Double) -> String {
        return String(format: "+%.0f m", meters)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private static var gpxContentTypes: [UTType] {
        var types: [UTType] = [.xml]
        if let gpxType = UTType(filenameExtension: "gpx", conformingTo: .xml) {
            types.insert(gpxType, at: 0)
        }
        return types
    }
}
