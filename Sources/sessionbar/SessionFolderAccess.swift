import Foundation
import AppKit

@MainActor
final class SessionFolderAccess {
    private var scopes: [URL] = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func restore() async {
        let bookmarks = defaults.dictionary(forKey: "sessionbar.folderBookmarks") as? [String: Data] ?? [:]
        let restored = await Task.detached(priority: .utility) {
            bookmarks.values.compactMap { data -> URL? in
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                         relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }.value
        scopes.append(contentsOf: restored)
    }

    func connect(_ url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = defaults.dictionary(forKey: "sessionbar.folderBookmarks") as? [String: Data] ?? [:]
            bookmarks[url.path] = data
            defaults.set(bookmarks, forKey: "sessionbar.folderBookmarks")
            scopes.append(url)
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    func disconnect(path: String) {
        for url in scopes where url.path == path { url.stopAccessingSecurityScopedResource() }
        scopes.removeAll { $0.path == path }
        var bookmarks = defaults.dictionary(forKey: "sessionbar.folderBookmarks") as? [String: Data] ?? [:]
        bookmarks.removeValue(forKey: path)
        defaults.set(bookmarks, forKey: "sessionbar.folderBookmarks")
    }
}
