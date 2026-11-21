import SwiftUI
import CoreLocation

public struct RegionalTrailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public let visibleBounds: MLNCoordinateBounds?
    public let downloader: RegionalTrailDownloader
    public var onTrailsUpdated: (([URL]) -> Void)?
    
    @State private var regionName: String = ""
    @State private var isDownloading: Bool = false
    @State private var downloadedFiles: [URL] = []
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    @State private var successNotice: String?
    
    public init(
        visibleBounds: MLNCoordinateBounds? = nil,
        downloader: RegionalTrailDownloader = .shared,
        onTrailsUpdated: (([URL]) -> Void)? = nil
    ) {
        self.visibleBounds = visibleBounds
        self.downloader = downloader
        self.onTrailsUpdated = onTrailsUpdated
    }
    
    private var latSpan: Double? {
        guard let b = visibleBounds else { return nil }
        return abs(b.ne.latitude - b.sw.latitude)
    }
    
    private var lonSpan: Double? {
        guard let b = visibleBounds else { return nil }
        return abs(b.ne.longitude - b.sw.longitude)
    }
    
    private var isWithinSafeLimit: Bool {
        guard let ls = latSpan, let lons = lonSpan else { return false }
        return ls <= RegionalTrailDownloader.maxSpanDegrees && lons <= RegionalTrailDownloader.maxSpanDegrees && ls > 0.0001
    }
    
    private var suggestedRegionName: String {
        guard let b = visibleBounds else {
            return "Region_\(Int(Date().timeIntervalSince1970))"
        }
        let centerLat = (b.ne.latitude + b.sw.latitude) / 2.0
        let centerLon = (b.ne.longitude + b.sw.longitude) / 2.0
        return String(format: "Trail_%.2f_%.2f", centerLat, centerLon)
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Visible Map Area Status
                Section(header: Text("Visible Map Bounding Box")) {
                    if let b = visibleBounds, let ls = latSpan, let lons = lonSpan {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Latitude Span:")
                                Spacer()
                                Text(String(format: "%.3f°", ls))
                                    .foregroundColor(ls > RegionalTrailDownloader.maxSpanDegrees ? .red : .primary)
                            }
                            HStack {
                                Text("Longitude Span:")
                                Spacer()
                                Text(String(format: "%.3f°", lons))
                                    .foregroundColor(lons > RegionalTrailDownloader.maxSpanDegrees ? .red : .primary)
                            }
                            HStack {
                                Text("South-West:")
                                Spacer()
                                Text(String(format: "%.4f, %.4f", b.sw.latitude, b.sw.longitude))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("North-East:")
                                Spacer()
                                Text(String(format: "%.4f, %.4f", b.ne.latitude, b.ne.longitude))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            if isWithinSafeLimit {
                                Label("Safe download area (≤ 0.5° span)", systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                            } else {
                                Label("Area too large! Zoom in closer (max 0.5° span)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No map bounding box available. Navigate map to desired area.")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Section 2: Download New Region
                Section(header: Text("Download Regional Trails")) {
                    #if os(iOS)
                    TextField("Region Name", text: $regionName, prompt: Text(suggestedRegionName))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    #else
                    TextField("Region Name", text: $regionName, prompt: Text(suggestedRegionName))
                    #endif
                    
                    Button {
                        Task {
                            await initiateDownload()
                        }
                    } label: {
                        HStack {
                            if isDownloading {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Querying OpenStreetMap...")
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download Trails for Visible Area")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(isWithinSafeLimit && !isDownloading ? .white : .secondary)
                    }
                    .disabled(!isWithinSafeLimit || isDownloading)
                    #if os(iOS)
                    .listRowBackground(isWithinSafeLimit && !isDownloading ? Color.accentColor : Color(UIColor.systemGray5))
                    #else
                    .listRowBackground(isWithinSafeLimit && !isDownloading ? Color.accentColor : Color.gray.opacity(0.2))
                    #endif
                }
                
                // Section 3: Notice Feedback
                if let notice = successNotice {
                    Section {
                        Label(notice, systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                    }
                }
                
                // Section 4: Downloaded Trail Regions
                Section(header: Text("Downloaded Trail Regions (\(downloadedFiles.count))")) {
                    if downloadedFiles.isEmpty {
                        Text("No downloaded trail regions yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(downloadedFiles, id: \.self) { url in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.headline)
                                HStack {
                                    if let size = fileSizeString(for: url) {
                                        Text(size)
                                    }
                                    if let date = fileDateString(for: url) {
                                        Text("• \(date)")
                                    }
                                    Spacer()
                                    Label("Excluded from Backup", systemImage: "icloud.slash")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete(perform: deleteRegions)
                    }
                }
            }
            .navigationTitle("Offline Trails")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await refreshDownloadedList()
                if regionName.isEmpty {
                    regionName = suggestedRegionName
                }
            }
            .alert("Download Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }
    
    private func refreshDownloadedList() async {
        let files = await downloader.listDownloadedRegions()
        self.downloadedFiles = files
        onTrailsUpdated?(files)
    }
    
    private func initiateDownload() async {
        guard let bounds = visibleBounds else { return }
        let effectiveName = regionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? suggestedRegionName
            : regionName
        
        isDownloading = true
        errorMessage = nil
        successNotice = nil
        
        do {
            let savedURL = try await downloader.downloadTrails(bbox: bounds, regionName: effectiveName)
            await refreshDownloadedList()
            successNotice = "Successfully downloaded \(savedURL.lastPathComponent)"
            regionName = ""
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
        
        isDownloading = false
    }
    
    private func deleteRegions(at offsets: IndexSet) {
        for index in offsets {
            let url = downloadedFiles[index]
            Task {
                try? await downloader.deleteDownloadedRegion(at: url)
                await refreshDownloadedList()
            }
        }
    }
    
    private func fileSizeString(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    private func fileDateString(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
