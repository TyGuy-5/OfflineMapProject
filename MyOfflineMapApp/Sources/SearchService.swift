import Foundation
import SQLite

struct SearchResult: Identifiable {
    let id: Int64
    let name: String
    let lat: Double
    let lon: Double
}

class SearchService {
    private var db: Connection?

    init() {
        let path = OfflineDataManager.url(for: "search_index.db").path
        self.db = try? Connection(path, readonly: true)
    }

    func search(query: String) -> [SearchResult] {
        guard let db = db, !query.isEmpty else { return [] }
        
        // FTS5 Input Sanitization:
        // Strip out existing quotes to prevent SQL injection, then wrap the whole phrase
        // in quotes to escape punctuation, and finally add the wildcard asterisk.
        let safeQuery = query.replacingOccurrences(of: "\"", with: "")
        let searchQuery = "\"\(safeQuery)\"*"
        
        let geocoder = VirtualTable("geocoder")
        let rowid = Expression<Int64>("rowid")
        let name = Expression<String>("name")
        let lat = Expression<Double>("lat")
        let lon = Expression<Double>("lon")
        
        var results: [SearchResult] = []
        
        do {
            let queryExpr = geocoder
                .select(rowid, name, lat, lon)
                .filter(name.match(searchQuery))
                .limit(25)
            
            for row in try db.prepare(queryExpr) {
                results.append(SearchResult(
                    id: row[rowid],
                    name: row[name],
                    lat: row[lat],
                    lon: row[lon]
                ))
            }
        } catch {
            print("Search failed: \(error)")
        }
        return results
    }
}
