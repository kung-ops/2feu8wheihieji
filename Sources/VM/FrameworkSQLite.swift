import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

// android.database.sqlite on top of the SQLite that ships with iOS:
// SQLiteOpenHelper, SQLiteDatabase, Cursor, ContentValues, SQLiteStatement.
// Databases live in the app's private folder (databases/).

private let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])

    var string: String? {
        switch self {
        case .null: return nil
        case .int(let v): return String(v)
        case .real(let d): return Boxed.javaDouble(d)
        case .text(let s): return s
        case .blob(let b): return String(decoding: b, as: UTF8.self)
        }
    }
    var int64: Int64 {
        switch self {
        case .int(let v): return v
        case .real(let d): return Int64(d)
        case .text(let s): return Int64(s) ?? Int64(Double(s) ?? 0)
        default: return 0
        }
    }
    var double: Double {
        switch self {
        case .int(let v): return Double(v)
        case .real(let d): return d
        case .text(let s): return Double(s) ?? 0
        default: return 0
        }
    }
}

final class SQLiteDBBox {
    var db: OpaquePointer?
    let path: String
    var inTransaction = 0
    var transactionOK = false
    var version: Int32 = 0
    init(db: OpaquePointer?, path: String) {
        self.db = db
        self.path = path
    }
    func close() {
        if let d = db { sqlite3_close_v2(d) }
        db = nil
    }
    deinit { close() }
}

final class SQLiteHelperBox {
    let name: String?
    let version: Int32
    var open: JObject?
    init(name: String?, version: Int32) {
        self.name = name
        self.version = version
    }
}

final class CursorBox {
    var columns: [String] = []
    var rows: [[SQLValue]] = []
    var position = -1
    var closed = false
    var current: [SQLValue]? { return position >= 0 && position < rows.count ? rows[position] : nil }
}

final class ContentValuesBox {
    var items: [(String, SQLValue)] = []
    func set(_ k: String, _ v: SQLValue) {
        if let i = items.firstIndex(where: { $0.0 == k }) { items[i].1 = v } else { items.append((k, v)) }
    }
}

final class SQLStatementBox {
    let db: SQLiteDBBox
    let sql: String
    var binds: [Int: SQLValue] = [:]
    init(db: SQLiteDBBox, sql: String) {
        self.db = db
        self.sql = sql
    }
}

extension Framework {

    // MARK: - Low level

    static func sqlError(_ vm: VM, _ db: SQLiteDBBox, _ what: String) -> JavaThrow {
        let msg = db.db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "database is closed"
        return vm.throwable("Landroid/database/sqlite/SQLiteException;", "\(msg) (\(what))")
    }

    /// Value of a Java object for binding (String, Integer, Long, Double, byte[], null…).
    static func sqlValue(_ vm: VM, _ v: Value) -> SQLValue {
        guard let o = v.o else { return .null }
        switch o.native {
        case let s as String: return .text(s)
        case let b as Boxed:
            switch b.kind {
            case .double, .float: return .real(b.asDouble)
            case .long: return .int(b.value.j)
            case .bool: return .int(b.value.i != 0 ? 1 : 0)
            default: return .int(Int64(b.value.i))
            }
        case let a as JArray where a.type == "[B": return .blob(a.byteValues)
        default: return .text((try? vm.stringOf(o)) ?? "")
        }
    }

    /// Runs one statement; returns the rows (for queries) and the change count.
    @discardableResult
    static func sqlRun(_ vm: VM, _ db: SQLiteDBBox, _ sql: String, _ args: [SQLValue]) throws -> CursorBox {
        guard let h = db.db else { throw sqlError(vm, db, sql) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK, let st = stmt else {
            throw sqlError(vm, db, sql)
        }
        defer { sqlite3_finalize(st) }
        for (i, v) in args.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .null: sqlite3_bind_null(st, idx)
            case .int(let n): sqlite3_bind_int64(st, idx, n)
            case .real(let d): sqlite3_bind_double(st, idx, d)
            case .text(let s): sqlite3_bind_text(st, idx, s, -1, SQLITE_TRANSIENT_PTR)
            case .blob(let b):
                _ = b.withUnsafeBytes { sqlite3_bind_blob(st, idx, $0.baseAddress, Int32(b.count), SQLITE_TRANSIENT_PTR) }
            }
        }
        let c = CursorBox()
        let n = sqlite3_column_count(st)
        for i in 0..<n { c.columns.append(sqlite3_column_name(st, i).map { String(cString: $0) } ?? "") }
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw sqlError(vm, db, sql) }
            var row: [SQLValue] = []
            row.reserveCapacity(Int(n))
            for i in 0..<n {
                switch sqlite3_column_type(st, i) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(st, i)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(st, i)))
                case SQLITE_TEXT: row.append(.text(sqlite3_column_text(st, i).map { String(cString: $0) } ?? ""))
                case SQLITE_BLOB:
                    let len = Int(sqlite3_column_bytes(st, i))
                    if let p = sqlite3_column_blob(st, i), len > 0 {
                        row.append(.blob(Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: len))))
                    } else {
                        row.append(.blob([]))
                    }
                default: row.append(.null)
                }
            }
            c.rows.append(row)
            if c.rows.count > 200_000 { break }
        }
        return c
    }

    static func openDatabase(_ vm: VM, path: String) throws -> JObject {
        if path != ":memory:" {
            guard vm.storage.allows(path) else {
                throw vm.throwable("Landroid/database/sqlite/SQLiteCantOpenDatabaseException;", "unknown error (code 14): Could not open database")
            }
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        }
        var h: OpaquePointer?
        guard sqlite3_open_v2(path, &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let x = h { sqlite3_close_v2(x) }
            throw vm.throwable("Landroid/database/sqlite/SQLiteCantOpenDatabaseException;", "Could not open \(path)")
        }
        let box = SQLiteDBBox(db: h, path: path)
        if let v = try? sqlRun(vm, box, "PRAGMA user_version", []).rows.first?.first { box.version = Int32(truncatingIfNeeded: v.int64) }
        return vm.newObject("Landroid/database/sqlite/SQLiteDatabase;", native: box)
    }

    static func stringArgs(_ vm: VM, _ v: Value) -> [SQLValue] {
        guard let arr = v.o?.native as? JArray else { return [] }
        return arr.items.map { sqlValue(vm, $0) }
    }

    static func cursor(_ vm: VM, _ c: CursorBox) -> JObject {
        return vm.newObject("Landroid/database/sqlite/SQLiteCursor;", native: c)
    }

    // MARK: - Constructors & statics

    static func sqliteConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.classDesc {
        case "Landroid/database/sqlite/SQLiteOpenHelper;", "Landroidx/sqlite/db/SupportSQLiteOpenHelper;":
            let p = ref.params
            let name = p.count > 1 ? (a[1].o.flatMap { try? vm.stringOf($0) }) : nil
            let version = p.count > 3 ? a[3].i : 1
            t.native = SQLiteHelperBox(name: name, version: version)
            return .void
        case "Landroid/content/ContentValues;":
            let cv = ContentValuesBox()
            if let src = a.first?.o?.native as? ContentValuesBox { cv.items = src.items }
            t.native = cv
            return .void
        case "Landroid/database/MatrixCursor;":
            let c = CursorBox()
            if let cols = a.first?.o?.native as? JArray { c.columns = cols.items.map { ($0.o?.native as? String) ?? "" } }
            t.native = c
            return .void
        default:
            return nil
        }
    }

    static func sqliteStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.classDesc {
        case "Landroid/database/sqlite/SQLiteDatabase;":
            switch ref.name {
            case "openOrCreateDatabase", "openDatabase":
                var path = ""
                if let f = a.first?.o { path = filePath(f) ?? ((try? vm.stringOf(f)) ?? "") }
                return O(try openDatabase(vm, path: path))
            case "create": return O(try openDatabase(vm, path: ":memory:"))
            case "deleteDatabase":
                guard let f = a.first?.o, let path = filePath(f), vm.storage.allows(path) else { return B(false) }
                return B((try? FileManager.default.removeItem(atPath: path)) != nil)
            default: return nil
            }
        case "Landroid/database/DatabaseUtils;":
            switch ref.name {
            case "queryNumEntries":
                guard let db = a[0].o?.native as? SQLiteDBBox else { throw vm.npe("queryNumEntries") }
                var sql = "SELECT COUNT(*) FROM " + (try vm.stringOf(a[1].o))
                var args: [SQLValue] = []
                if ref.params.count > 2, let w = a[2].o { sql += " WHERE " + (try vm.stringOf(w)); if ref.params.count > 3 { args = stringArgs(vm, a[3]) } }
                return .val(.wide(try sqlRun(vm, db, sql, args).rows.first?.first?.int64 ?? 0))
            case "longForQuery", "stringForQuery":
                guard let db = a[0].o?.native as? SQLiteDBBox else { return nil }
                let r = try sqlRun(vm, db, try vm.stringOf(a[1].o), stringArgs(vm, a.count > 2 ? a[2] : .null)).rows.first?.first
                return ref.name == "longForQuery" ? .val(.wide(r?.int64 ?? 0)) : S(vm, r?.string ?? "")
            case "sqlEscapeString":
                let s = try vm.stringOf(a[0].o)
                return S(vm, "'" + s.replacingOccurrences(of: "'", with: "''") + "'")
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Context.openOrCreateDatabase / getDatabasePath / deleteDatabase / databaseList.
    static func contextDatabase(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let dir = vm.storage.dataDir.appendingPathComponent("databases")
        switch ref.name {
        case "openOrCreateDatabase":
            let name = try vm.stringOf(a[0].o)
            return O(try openDatabase(vm, path: name.hasPrefix("/") ? name : dir.appendingPathComponent(name).path))
        case "deleteDatabase":
            let name = try vm.stringOf(a[0].o)
            return B((try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))) != nil)
        case "databaseList":
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).map { Value.obj(vm.str($0)) }
            return O(vm.newObject("[Ljava/lang/String;", native: JArray(type: "[Ljava/lang/String;", items: names)))
        default:
            return nil
        }
    }

    // MARK: - SQLiteOpenHelper (the app's subclass)

    static func helperMethod(_ vm: VM, _ t: JObject, _ hb: SQLiteHelperBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "getWritableDatabase", "getReadableDatabase":
            if let o = hb.open, (o.native as? SQLiteDBBox)?.db != nil { return O(o) }
            let path = hb.name.map { vm.storage.dataDir.appendingPathComponent("databases").appendingPathComponent($0).path } ?? ":memory:"
            let o = try openDatabase(vm, path: path)
            guard let db = o.native as? SQLiteDBBox else { return O(o) }
            hb.open = o
            let p = ["Landroid/database/sqlite/SQLiteDatabase;"]
            _ = try vm.call(t, "onConfigure", params: p, args: [.obj(o)])
            if db.version != hb.version {
                try sqlRun(vm, db, "BEGIN", [])
                do {
                    if db.version == 0 {
                        _ = try vm.call(t, "onCreate", params: p, args: [.obj(o)])
                    } else if db.version < hb.version {
                        _ = try vm.call(t, "onUpgrade", params: p + ["I", "I"], args: [.obj(o), .int(db.version), .int(hb.version)])
                    } else {
                        _ = try vm.call(t, "onDowngrade", params: p + ["I", "I"], args: [.obj(o), .int(db.version), .int(hb.version)])
                    }
                    try sqlRun(vm, db, "PRAGMA user_version = \(hb.version)", [])
                    db.version = hb.version
                    try sqlRun(vm, db, "COMMIT", [])
                } catch {
                    _ = try? sqlRun(vm, db, "ROLLBACK", [])
                    throw error
                }
            }
            _ = try vm.call(t, "onOpen", params: p, args: [.obj(o)])
            return O(o)
        case "close":
            (hb.open?.native as? SQLiteDBBox)?.close()
            hb.open = nil
            return .void
        case "getDatabaseName": return O(hb.name.map { vm.str($0) })
        case "onConfigure", "onOpen", "setWriteAheadLoggingEnabled", "setIdleConnectionTimeout", "setLookasideConfig":
            return .void
        case "onDowngrade":
            throw vm.throwable("Landroid/database/sqlite/SQLiteException;", "Can't downgrade database from version \(a[1].i) to \(a[2].i)")
        default:
            return nil
        }
    }

    // MARK: - SQLiteDatabase

    static func buildQuery(_ vm: VM, distinct: Bool, table: String, columns: Value, selection: Value,
                           groupBy: Value, having: Value, orderBy: Value, limit: Value) throws -> String {
        var cols = "*"
        if let arr = columns.o?.native as? JArray, !arr.items.isEmpty {
            cols = arr.items.compactMap { $0.o?.native as? String }.joined(separator: ", ")
        }
        var sql = "SELECT " + (distinct ? "DISTINCT " : "") + cols + " FROM " + table
        func part(_ v: Value, _ kw: String) throws {
            if let o = v.o { let s = try vm.stringOf(o); if !s.isEmpty { sql += " " + kw + " " + s } }
        }
        try part(selection, "WHERE")
        try part(groupBy, "GROUP BY")
        try part(having, "HAVING")
        try part(orderBy, "ORDER BY")
        try part(limit, "LIMIT")
        return sql
    }

    static func databaseMethod(_ vm: VM, _ t: JObject, _ db: SQLiteDBBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        switch ref.name {
        case "execSQL":
            try sqlRun(vm, db, try vm.stringOf(a[0].o), p.count > 1 ? stringArgs(vm, a[1]) : [])
            return .void
        case "rawQuery", "rawQueryWithFactory":
            let off = ref.name == "rawQueryWithFactory" ? 1 : 0
            return O(cursor(vm, try sqlRun(vm, db, try vm.stringOf(a[off].o), stringArgs(vm, a[off + 1]))))
        case "query", "queryWithFactory":
            // query(table, cols, sel, args, group, having, order[, limit])
            // query(distinct, table, cols, sel, args, group, having, order, limit)
            var i = 0
            var distinct = false
            if ref.name == "queryWithFactory" { i = 1 }
            if p[i] == "Z" { distinct = a[i].i != 0; i += 1 }
            let table = try vm.stringOf(a[i].o)
            let sql = try buildQuery(vm, distinct: distinct, table: table, columns: a[i + 1], selection: a[i + 2],
                                     groupBy: a[i + 4], having: a[i + 5], orderBy: a[i + 6],
                                     limit: a.count > i + 7 && p[i + 7] == "Ljava/lang/String;" ? a[i + 7] : .null)
            return O(cursor(vm, try sqlRun(vm, db, sql, stringArgs(vm, a[i + 3]))))
        case "insert", "insertOrThrow", "insertWithOnConflict", "replace", "replaceOrThrow":
            let table = try vm.stringOf(a[0].o)
            let cv = (a[2].o?.native as? ContentValuesBox)?.items ?? []
            var verb = "INSERT"
            if ref.name.hasPrefix("replace") { verb = "INSERT OR REPLACE" }
            if ref.name == "insertWithOnConflict" {
                verb = ["INSERT", "INSERT OR ROLLBACK", "INSERT OR ABORT", "INSERT OR FAIL", "INSERT OR IGNORE", "INSERT OR REPLACE"][max(0, min(5, Int(a[3].i)))]
            }
            var sql: String
            if cv.isEmpty {
                let hack = a[1].o.flatMap { try? vm.stringOf($0) } ?? "rowid"
                sql = "\(verb) INTO \(table) (\(hack)) VALUES (NULL)"
            } else {
                sql = "\(verb) INTO \(table) (" + cv.map { $0.0 }.joined(separator: ", ") + ") VALUES (" +
                    cv.map { _ in "?" }.joined(separator: ", ") + ")"
            }
            do {
                try sqlRun(vm, db, sql, cv.map { $0.1 })
            } catch let e as JavaThrow {
                if ref.name.hasSuffix("OrThrow") { throw e }
                vm.log("E/SQLiteDatabase: Error inserting into \(table): \(vm.describeThrowable(e.obj))")
                return .val(.wide(-1))
            }
            return .val(.wide(db.db.map { sqlite3_last_insert_rowid($0) } ?? -1))
        case "update", "updateWithOnConflict":
            let table = try vm.stringOf(a[0].o)
            let cv = (a[1].o?.native as? ContentValuesBox)?.items ?? []
            guard !cv.isEmpty else { return I(0) }
            var sql = "UPDATE \(table) SET " + cv.map { $0.0 + " = ?" }.joined(separator: ", ")
            if let w = a[2].o { let s = try vm.stringOf(w); if !s.isEmpty { sql += " WHERE " + s } }
            try sqlRun(vm, db, sql, cv.map { $0.1 } + stringArgs(vm, a[3]))
            return I(db.db.map { sqlite3_changes($0) } ?? 0)
        case "delete":
            var sql = "DELETE FROM " + (try vm.stringOf(a[0].o))
            if let w = a[1].o { let s = try vm.stringOf(w); if !s.isEmpty { sql += " WHERE " + s } }
            try sqlRun(vm, db, sql, stringArgs(vm, a[2]))
            return I(db.db.map { sqlite3_changes($0) } ?? 0)
        case "beginTransaction", "beginTransactionNonExclusive", "beginTransactionWithListener":
            if db.inTransaction == 0 { try sqlRun(vm, db, "BEGIN", []); db.transactionOK = false }
            db.inTransaction += 1
            return .void
        case "setTransactionSuccessful": db.transactionOK = true; return .void
        case "endTransaction":
            if db.inTransaction > 0 {
                db.inTransaction -= 1
                if db.inTransaction == 0 { try sqlRun(vm, db, db.transactionOK ? "COMMIT" : "ROLLBACK", []) }
            }
            return .void
        case "inTransaction": return B(db.inTransaction > 0)
        case "isOpen": return B(db.db != nil)
        case "isReadOnly", "isDbLockedByCurrentThread", "isWriteAheadLoggingEnabled": return B(false)
        case "close", "releaseReference", "acquireReference": if ref.name == "close" { db.close() }; return .void
        case "getVersion": return I(db.version)
        case "setVersion":
            try sqlRun(vm, db, "PRAGMA user_version = \(a[0].i)", [])
            db.version = a[0].i
            return .void
        case "getPath": return S(vm, db.path)
        case "compileStatement":
            return O(vm.newObject("Landroid/database/sqlite/SQLiteStatement;", native: SQLStatementBox(db: db, sql: try vm.stringOf(a[0].o))))
        case "setForeignKeyConstraintsEnabled":
            try sqlRun(vm, db, "PRAGMA foreign_keys = \(a[0].i != 0 ? "ON" : "OFF")", [])
            return .void
        case "enableWriteAheadLogging": return B(false)
        case "disableWriteAheadLogging", "setLocale", "setMaxSqlCacheSize", "setPageSize", "yieldIfContendedSafely":
            return ref.ret == "Z" ? B(false) : .void
        default:
            return nil
        }
    }

    static func statementMethod(_ vm: VM, _ s: SQLStatementBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        func args() -> [SQLValue] {
            let n = s.binds.keys.max() ?? 0
            return n == 0 ? [] : (1...n).map { s.binds[$0] ?? .null }
        }
        switch ref.name {
        case "bindLong": s.binds[Int(a[0].i)] = .int(a[1].j); return .void
        case "bindDouble": s.binds[Int(a[0].i)] = .real(a[1].d); return .void
        case "bindString": s.binds[Int(a[0].i)] = a[1].o.flatMap { $0.native as? String }.map { .text($0) } ?? .null; return .void
        case "bindNull": s.binds[Int(a[0].i)] = .null; return .void
        case "bindBlob": s.binds[Int(a[0].i)] = .blob((a[1].o?.native as? JArray)?.byteValues ?? []); return .void
        case "bindAllArgsAsStrings":
            for (i, v) in stringArgs(vm, a[0]).enumerated() { s.binds[i + 1] = v }
            return .void
        case "clearBindings": s.binds.removeAll(); return .void
        case "execute": try sqlRun(vm, s.db, s.sql, args()); return .void
        case "executeInsert":
            try sqlRun(vm, s.db, s.sql, args())
            return .val(.wide(s.db.db.map { sqlite3_last_insert_rowid($0) } ?? -1))
        case "executeUpdateDelete":
            try sqlRun(vm, s.db, s.sql, args())
            return I(s.db.db.map { sqlite3_changes($0) } ?? 0)
        case "simpleQueryForLong":
            guard let v = try sqlRun(vm, s.db, s.sql, args()).rows.first?.first else {
                throw vm.throwable("Landroid/database/sqlite/SQLiteDoneException;", "no rows")
            }
            return .val(.wide(v.int64))
        case "simpleQueryForString":
            guard let v = try sqlRun(vm, s.db, s.sql, args()).rows.first?.first else {
                throw vm.throwable("Landroid/database/sqlite/SQLiteDoneException;", "no rows")
            }
            return O(v.string.map { vm.str($0) })
        case "close", "releaseReference": return .void
        default: return nil
        }
    }

    // MARK: - Cursor

    static func cursorMethod(_ vm: VM, _ c: CursorBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        func col(_ i: Int32) throws -> SQLValue {
            guard let row = c.current else {
                throw vm.throwable("Landroid/database/CursorIndexOutOfBoundsException;", "Index \(c.position) requested, with a size of \(c.rows.count)")
            }
            guard i >= 0 && Int(i) < row.count else { return .null }
            return row[Int(i)]
        }
        func move(to p: Int) -> Ret {
            c.position = max(-1, min(p, c.rows.count))
            return B(c.position >= 0 && c.position < c.rows.count)
        }
        switch ref.name {
        case "getCount": return I(Int32(c.rows.count))
        case "getPosition": return I(Int32(c.position))
        case "moveToFirst": return move(to: 0)
        case "moveToLast": return move(to: c.rows.count - 1)
        case "moveToNext": return move(to: c.position + 1)
        case "moveToPrevious": return move(to: c.position - 1)
        case "moveToPosition": return move(to: Int(a[0].i))
        case "move": return move(to: c.position + Int(a[0].i))
        case "isFirst": return B(c.position == 0 && !c.rows.isEmpty)
        case "isLast": return B(c.position == c.rows.count - 1 && !c.rows.isEmpty)
        case "isBeforeFirst": return B(c.rows.isEmpty || c.position < 0)
        case "isAfterLast": return B(c.rows.isEmpty || c.position >= c.rows.count)
        case "getColumnCount": return I(Int32(c.columns.count))
        case "getColumnIndex":
            let n = try vm.stringOf(a[0].o)
            let short = n.split(separator: ".").last.map(String.init) ?? n
            return I(Int32(c.columns.firstIndex { $0.caseInsensitiveCompare(n) == .orderedSame || $0.caseInsensitiveCompare(short) == .orderedSame } ?? -1))
        case "getColumnIndexOrThrow":
            let n = try vm.stringOf(a[0].o)
            guard let i = c.columns.firstIndex(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else {
                throw vm.throwable("Ljava/lang/IllegalArgumentException;", "column '\(n)' does not exist")
            }
            return I(Int32(i))
        case "getColumnName": return S(vm, a[0].i >= 0 && Int(a[0].i) < c.columns.count ? c.columns[Int(a[0].i)] : "")
        case "getColumnNames":
            let items = c.columns.map { Value.obj(vm.str($0)) }
            return O(vm.newObject("[Ljava/lang/String;", native: JArray(type: "[Ljava/lang/String;", items: items)))
        case "getString": return O(try col(a[0].i).string.map { vm.str($0) })
        case "getInt": return I(Int32(truncatingIfNeeded: try col(a[0].i).int64))
        case "getShort": return I(Int32(Int16(truncatingIfNeeded: try col(a[0].i).int64)))
        case "getLong": return .val(.wide(try col(a[0].i).int64))
        case "getDouble": return .val(.double(try col(a[0].i).double))
        case "getFloat": return .val(.float(Float(try col(a[0].i).double)))
        case "getBlob":
            if case .blob(let b) = try col(a[0].i) {
                return O(vm.newObject("[B", native: JArray(type: "[B", items: b.map { .int(Int32(Int8(bitPattern: $0))) })))
            }
            return O(nil)
        case "isNull":
            if case .null = try col(a[0].i) { return B(true) }
            return B(false)
        case "getType":
            switch try col(a[0].i) {
            case .null: return I(0)
            case .int: return I(1)
            case .real: return I(2)
            case .text: return I(3)
            case .blob: return I(4)
            }
        case "close", "deactivate": c.closed = true; return .void
        case "isClosed": return B(c.closed)
        case "requery": return B(true)
        case "addRow":
            // MatrixCursor.addRow(Object[] / Iterable)
            if let arr = a[0].o?.native as? JArray { c.rows.append(arr.items.map { sqlValue(vm, $0) }) }
            else if let l = a[0].o?.native as? ListBox { c.rows.append(l.items.map { sqlValue(vm, $0) }) }
            return .void
        case "registerContentObserver", "unregisterContentObserver", "registerDataSetObserver",
             "unregisterDataSetObserver", "setNotificationUri", "setExtras":
            return .void
        case "getExtras": return O(vm.newObject("Landroid/os/Bundle;"))
        case "getWantsAllOnMoveCalls": return B(false)
        default: return nil
        }
    }

    // MARK: - ContentValues

    static func contentValuesMethod(_ vm: VM, _ t: JObject, _ cv: ContentValuesBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let key = (a.first?.o?.native as? String) ?? ""
        func get() -> SQLValue? { return cv.items.first { $0.0 == key }?.1 }
        switch ref.name {
        case "put":
            if ref.params.count == 1, let other = a[0].o?.native as? ContentValuesBox {
                for (k, v) in other.items { cv.set(k, v) }
            } else {
                cv.set(key, sqlValue(vm, a[1]))
            }
            return .void
        case "putNull": cv.set(key, .null); return .void
        case "putAll":
            if let other = a[0].o?.native as? ContentValuesBox { for (k, v) in other.items { cv.set(k, v) } }
            return .void
        case "get", "getAsString":
            guard let v = get() else { return O(nil) }
            if ref.name == "getAsString" { return O(v.string.map { vm.str($0) }) }
            switch v {
            case .null: return O(nil)
            case .int(let n): return O(vm.box(.wide(n), type: "J"))
            case .real(let d): return O(vm.box(.double(d), type: "D"))
            case .text(let s): return S(vm, s)
            case .blob(let b): return O(vm.newObject("[B", native: JArray(type: "[B", items: b.map { .int(Int32(Int8(bitPattern: $0))) })))
            }
        case "getAsInteger": return O(get().map { vm.box(.int(Int32(truncatingIfNeeded: $0.int64)), type: "I") })
        case "getAsLong": return O(get().map { vm.box(.wide($0.int64), type: "J") })
        case "getAsDouble": return O(get().map { vm.box(.double($0.double), type: "D") })
        case "getAsFloat": return O(get().map { vm.box(.float(Float($0.double)), type: "F") })
        case "getAsBoolean": return O(get().map { vm.box(.int($0.int64 != 0 ? 1 : 0), type: "Z") })
        case "containsKey": return B(get() != nil)
        case "remove": cv.items.removeAll { $0.0 == key }; return .void
        case "clear": cv.items.removeAll(); return .void
        case "size": return I(Int32(cv.items.count))
        case "isEmpty": return B(cv.items.isEmpty)
        case "keySet":
            return O(vm.newObject("Ljava/util/HashSet;", native: ListBox(isSet: true, items: cv.items.map { .obj(vm.str($0.0)) })))
        default: return nil
        }
    }
}
