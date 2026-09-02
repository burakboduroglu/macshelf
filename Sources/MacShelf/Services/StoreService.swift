import Foundation
import SQLite3

/// Owns the on-disk location of the SwiftData store and keeps the SQLite file
/// from growing without bound.
enum StoreService {
    private static let directoryName = "MacShelf"
    private static let storeName = "MacShelf.store"

    /// SQLite keeps a write-ahead log and a shared-memory index beside the
    /// database. Anything that moves or deletes the store must carry these too.
    private static let sidecarSuffixes = ["", "-wal", "-shm"]

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var directoryURL: URL {
        applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var storeURL: URL {
        directoryURL.appendingPathComponent(storeName)
    }

    /// Where SwiftData put the store before we passed it an explicit URL:
    /// straight into `~/Library/Application Support`, a directory shared with
    /// every other non-sandboxed app on the system.
    private static var legacyStoreURL: URL {
        applicationSupport.appendingPathComponent("default.store")
    }

    /// Create the store directory and adopt a store left behind by an earlier
    /// version. Safe to call on every launch; does nothing once migrated.
    static func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // Only migrate into an empty slot, so we can never clobber a store the
        // current version is already using.
        guard fm.fileExists(atPath: legacyStoreURL.path),
              !fm.fileExists(atPath: storeURL.path) else { return }

        for suffix in sidecarSuffixes {
            let from = URL(fileURLWithPath: legacyStoreURL.path + suffix)
            let to = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            do {
                try fm.moveItem(at: from, to: to)
            } catch {
                NSLog("MacShelf: could not migrate \(from.lastPathComponent): \(error)")
            }
        }
    }

    /// Remove the store and its sidecars. Used when the persisted schema can no
    /// longer be opened.
    static func deleteStore() {
        let fm = FileManager.default
        for suffix in sidecarSuffixes {
            try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    // MARK: - Compaction

    /// Return disk space left behind by pruned items.
    ///
    /// SwiftData opens the store with `auto_vacuum = INCREMENTAL`, which parks
    /// the pages of deleted rows on SQLite's free list but never hands them
    /// back to the filesystem, and nothing else in the app runs the vacuum. One
    /// large copy therefore keeps its pages reserved for the life of the store:
    /// copying 10 MB of text grew the file to 18 MB, and pruning that item left
    /// it at 18 MB with 4007 of 4029 pages free.
    ///
    /// Must run before `ModelContainer` opens the store — this takes its own
    /// SQLite connection and two writers on one file is asking for trouble.
    ///
    /// - Parameter freeRatioThreshold: Fraction of the file that must be dead
    ///   space before compacting is worth the launch-time cost.
    static func compact(freeRatioThreshold: Double = 0.25) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        var handle: OpaquePointer?
        guard sqlite3_open(storeURL.path, &handle) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            return
        }
        defer { sqlite3_close(db) }

        let pageCount = scalar(db, "PRAGMA page_count;")
        let freeCount = scalar(db, "PRAGMA freelist_count;")
        guard pageCount > 0, Double(freeCount) / Double(pageCount) >= freeRatioThreshold else {
            return
        }

        // The vacuum moves the free pages out of the b-tree; in WAL mode the
        // shrunken file only reaches disk once the log is checkpointed.
        execute(db, "PRAGMA incremental_vacuum;")
        execute(db, "PRAGMA wal_checkpoint(TRUNCATE);")
        NSLog("MacShelf: compacted store, reclaimed \(freeCount) of \(pageCount) pages")
    }

    private static func scalar(_ db: OpaquePointer, _ sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {}
    }
}
