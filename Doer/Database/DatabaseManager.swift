import Foundation
import GRDB

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    private let dbPool: DatabasePool

    private init() {
        // Prefer bootstrap path so a file masquerading as Library/Application Support
        // is repaired before GRDB opens the pool (avoids NSCocoaErrorDomain 512 / ENOTDIR).
        let appSupport = AppStorageBootstrap.applicationSupportDirectoryURL()
        // Legacy filename — renaming would orphan existing forum records.
        let dbURL = appSupport.appendingPathComponent("dexo.sqlite")

        func openAndMigrate() throws -> DatabasePool {
            let pool = try DatabasePool(path: dbURL.path)
            try Self.migrator.migrate(pool)
            return pool
        }

        let pool: DatabasePool
        do {
            pool = try openAndMigrate()
        } catch {
            // A corrupt or half-migrated database must not crash-loop the app
            // on every launch (fatalError here used to make the only recovery
            // deleting the app, which also loses everything else). Park the
            // broken file beside the original and start fresh; the user keeps
            // a recoverable copy instead of a boot loop.
            #if DEBUG
            print("[DatabaseManager] init failed, recovering fresh: \(error)")
            #endif
            let backupURL = appSupport.appendingPathComponent("dexo.corrupt-\(Int(Date().timeIntervalSince1970)).sqlite")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: dbURL, to: backupURL)
            // GRDB also keeps WAL/SHM sidecars. Move them along with the
            // backup (instead of deleting) so un-checkpointed committed
            // transactions stay recoverable, and the new pool cannot try to
            // recover from the broken database's journal.
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: dbURL.path + suffix)
                let backupSidecar = URL(fileURLWithPath: backupURL.path + suffix)
                if FileManager.default.fileExists(atPath: sidecar.path) {
                    try? FileManager.default.removeItem(at: backupSidecar)
                    try? FileManager.default.moveItem(at: sidecar, to: backupSidecar)
                }
            }
            do {
                pool = try openAndMigrate()
            } catch {
                // Even a fresh pool failed (disk full / sandbox broken) — there
                // is nothing recoverable to do here.
                fatalError("Database initialization failed: \(error)")
            }
        }
        dbPool = pool
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "forumInstance") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("baseURL", .text).notNull()
                t.column("iconURL", .text)
                t.column("addedAt", .datetime).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "forumInstance") { t in
                t.add(column: "username", .text)
            }
        }

        return migrator
    }

    // MARK: - Forum CRUD

    func defaultForum() -> ForumInstance {
        do {
            return try ensureDefaultForum()
        } catch {
            assertionFailure("Failed to prepare default forum: \(error)")
            return ForumInstance.linuxDoDefault()
        }
    }

    func ensureDefaultForum() throws -> ForumInstance {
        try dbPool.write { db in
            let forums = try ForumInstance.fetchAll(db)
            if var forum = forums.first(where: { $0.isLinuxDoDefault }) {
                if forum.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    forum.title = ForumInstance.linuxDoTitle
                    try forum.save(db)
                }
                return forum
            }

            var forum = ForumInstance.linuxDoDefault()
            try forum.save(db)
            return forum
        }
    }

    func fetchAllForums() throws -> [ForumInstance] {
        try dbPool.read { db in
            try ForumInstance.order(Column("sortOrder").asc, Column("addedAt").asc).fetchAll(db)
        }
    }

    @discardableResult
    func saveForum(_ forum: inout ForumInstance) throws -> ForumInstance {
        try dbPool.write { db in
            try forum.save(db)
            return forum
        }
    }

    func deleteForum(_ forum: ForumInstance) throws {
        try dbPool.write { db in
            _ = try forum.delete(db)
        }
    }
}
