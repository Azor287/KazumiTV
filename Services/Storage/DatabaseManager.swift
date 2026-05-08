//
//  DatabaseManager.swift
//  KazumiTV
//
//  SQLite Database Manager using SQLite.swift
//

import Foundation
import SQLite

actor DatabaseManager {
    static let shared = DatabaseManager()

    private var db: Connection?

    // MARK: - Tables
    // Collectibles table
    private let collectibles = Table("collectibles")
    private let colId = SQLite.Expression<String>("id")
    private let colBangumiId = SQLite.Expression<Int>("bangumi_id")
    private let colName = SQLite.Expression<String>("name")
    private let colNameCn = SQLite.Expression<String>("name_cn")
    private let colImageURL = SQLite.Expression<String>("image_url")
    private let colEps = SQLite.Expression<Int>("eps")
    private let colAiredEps = SQLite.Expression<Int>("aired_eps")
    private let colAddedAt = SQLite.Expression<Date>("added_at")
    private let colLastWatchedAt = SQLite.Expression<Date?>("last_watched_at")
    private let colLastWatchedEpisode = SQLite.Expression<Int?>("last_watched_episode")
    private let colType = SQLite.Expression<Int>("type")
    private let colWatchProgressJSON = SQLite.Expression<String>("watch_progress_json")

    // Histories table
    private let histories = Table("histories")
    private let colHistoryId = SQLite.Expression<String>("id")
    private let colEpisodeId = SQLite.Expression<Int>("episode_id")
    private let colEpisodeNumber = SQLite.Expression<Int>("episode_number")
    private let colEpisodeName = SQLite.Expression<String>("episode_name")
    private let colBangumiName = SQLite.Expression<String>("bangumi_name")
    private let colBangumiImage = SQLite.Expression<String>("bangumi_image")
    private let colProgress = SQLite.Expression<Double>("progress")
    private let colDuration = SQLite.Expression<Double>("duration")
    private let colLastWatchedTime = SQLite.Expression<Date>("last_watched_time")
    private let colSource = SQLite.Expression<String>("source")
    private let colSourceURL = SQLite.Expression<String?>("source_url")
    private let colSourceName = SQLite.Expression<String?>("source_name")

    // Downloads table
    private let downloads = Table("downloads")
    private let colDownloadId = SQLite.Expression<String>("id")
    private let colM3U8URL = SQLite.Expression<String>("m3u8_url")
    private let colQuality = SQLite.Expression<String>("quality")
    private let colPluginName = SQLite.Expression<String>("plugin_name")
    private let colStatus = SQLite.Expression<Int>("status")
    private let colDownloadProgress = SQLite.Expression<Double>("progress")
    private let colTotalBytes = SQLite.Expression<Int64>("total_bytes")
    private let colDownloadedBytes = SQLite.Expression<Int64>("downloaded_bytes")
    private let colLocalPath = SQLite.Expression<String?>("local_path")
    private let colCreatedAt = SQLite.Expression<Date>("created_at")
    private let colUpdatedAt = SQLite.Expression<Date>("updated_at")

    private init() {}

    // MARK: - Setup
    func setup() async throws {
        if db != nil { return }

        let dbURL = try writableDatabaseURL()
        db = try Connection(dbURL.path)

        try await createTables()
    }

    private func writableDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        var directoryCandidates: [URL] = []

        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            directoryCandidates.append(applicationSupportURL)
            directoryCandidates.append(applicationSupportURL.appendingPathComponent("KazumiTV", isDirectory: true))
        }

        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            directoryCandidates.append(documentsURL.appendingPathComponent("KazumiTV", isDirectory: true))
        }

        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directoryCandidates.append(cachesURL.appendingPathComponent("KazumiTV", isDirectory: true))
        }

        var failures: [String] = []
        for directoryURL in directoryCandidates {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                return directoryURL.appendingPathComponent("kazumi.sqlite3")
            } catch {
                failures.append("\(directoryURL.path): \(error.localizedDescription)")
            }
        }

        throw DatabaseManagerError.storageUnavailable(failures.joined(separator: "; "))
    }

    private func createTables() async throws {
        guard let db = db else { return }

        // Create collectibles table
        try db.run(collectibles.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: true)
            t.column(colBangumiId)
            t.column(colName)
            t.column(colNameCn)
            t.column(colImageURL)
            t.column(colEps)
            t.column(colAiredEps)
            t.column(colAddedAt)
            t.column(colLastWatchedAt)
            t.column(colLastWatchedEpisode)
            t.column(colType)
            t.column(colWatchProgressJSON)
        })

        // Create histories table
        try db.run(histories.create(ifNotExists: true) { t in
            t.column(colHistoryId, primaryKey: true)
            t.column(colBangumiId)
            t.column(colEpisodeId)
            t.column(colEpisodeNumber)
            t.column(colEpisodeName)
            t.column(colBangumiName)
            t.column(colBangumiImage)
            t.column(colProgress)
            t.column(colDuration)
            t.column(colLastWatchedTime)
            t.column(colSource)
            t.column(colSourceURL)
            t.column(colSourceName)
        })
        try migrateHistoriesTable(using: db)
        try deduplicateHistories(using: db)

        // Create downloads table
        try db.run(downloads.create(ifNotExists: true) { t in
            t.column(colDownloadId, primaryKey: true)
            t.column(colBangumiId)
            t.column(colBangumiName)
            t.column(colEpisodeNumber)
            t.column(colEpisodeName)
            t.column(colM3U8URL)
            t.column(colQuality)
            t.column(colPluginName)
            t.column(colStatus)
            t.column(colDownloadProgress)
            t.column(colTotalBytes)
            t.column(colDownloadedBytes)
            t.column(colLocalPath)
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
        })
    }

    private func migrateHistoriesTable(using db: Connection) throws {
        var existingColumns = try columnNames(in: "histories", using: db)

        if !existingColumns.contains("source_url") {
            try db.run(histories.addColumn(colSourceURL))
            existingColumns.insert("source_url")
        }

        if !existingColumns.contains("source_name") {
            try db.run(histories.addColumn(colSourceName))
            existingColumns.insert("source_name")
        }
    }

    private func columnNames(in tableName: String, using db: Connection) throws -> Set<String> {
        let escapedTableName = tableName.replacingOccurrences(of: "\"", with: "\"\"")
        let columnName = SQLite.Expression<String>("name")

        return Set(try db.prepareRowIterator("PRAGMA table_info(\"\(escapedTableName)\")").map { row in
            row[columnName]
        })
    }

    // MARK: - Collectibles CRUD
    func insertCollectible(_ item: CollectedBangumi) async throws {
        guard let db = db else { return }

        let encoder = JSONEncoder()
        let progressData = try encoder.encode(item.watchProgress)
        let progressString = String(data: progressData, encoding: .utf8) ?? "{}"

        let insert = collectibles.insert(or: .replace,
            colId <- item.id,
            colBangumiId <- item.bangumiId,
            colName <- item.name,
            colNameCn <- item.nameCn,
            colImageURL <- item.imageURL,
            colEps <- item.eps,
            colAiredEps <- item.airedEps,
            colAddedAt <- item.addedAt,
            colLastWatchedAt <- item.lastWatchedAt,
            colLastWatchedEpisode <- item.lastWatchedEpisode,
            colType <- item.type,
            colWatchProgressJSON <- progressString
        )
        try db.run(insert)
    }

    func getCollectibles() async throws -> [CollectedBangumi] {
        guard let db = db else { return [] }

        var result: [CollectedBangumi] = []
        let decoder = JSONDecoder()

        for row in try db.prepare(collectibles) {
            var progressDict: [Int: Double] = [:]
            if let data = row[colWatchProgressJSON].data(using: .utf8) {
                progressDict = (try? decoder.decode([Int: Double].self, from: data)) ?? [:]
            }

            let item = CollectedBangumi(
                id: row[colId],
                bangumiId: row[colBangumiId],
                name: row[colName],
                nameCn: row[colNameCn],
                imageURL: row[colImageURL],
                eps: row[colEps],
                airedEps: row[colAiredEps],
                addedAt: row[colAddedAt],
                lastWatchedAt: row[colLastWatchedAt],
                lastWatchedEpisode: row[colLastWatchedEpisode],
                watchProgress: progressDict,
                type: row[colType]
            )
            result.append(item)
        }

        return result
    }

    func getCollectible(bangumiId: Int) async throws -> CollectedBangumi? {
        guard let db = db else { return nil }

        let query = collectibles.filter(colBangumiId == bangumiId)
        let decoder = JSONDecoder()

        for row in try db.prepare(query) {
            var progressDict: [Int: Double] = [:]
            if let data = row[colWatchProgressJSON].data(using: .utf8) {
                progressDict = (try? decoder.decode([Int: Double].self, from: data)) ?? [:]
            }

            return CollectedBangumi(
                id: row[colId],
                bangumiId: row[colBangumiId],
                name: row[colName],
                nameCn: row[colNameCn],
                imageURL: row[colImageURL],
                eps: row[colEps],
                airedEps: row[colAiredEps],
                addedAt: row[colAddedAt],
                lastWatchedAt: row[colLastWatchedAt],
                lastWatchedEpisode: row[colLastWatchedEpisode],
                watchProgress: progressDict,
                type: row[colType]
            )
        }

        return nil
    }

    func deleteCollectible(id: String) async throws {
        guard let db = db else { return }
        let item = collectibles.filter(colId == id)
        try db.run(item.delete())
    }

    // MARK: - Histories CRUD
    func insertHistory(_ item: History) async throws {
        guard let db = db else { return }

        let insert = histories.insert(or: .replace,
            colHistoryId <- item.id,
            colBangumiId <- item.bangumiId,
            colEpisodeId <- item.episodeId,
            colEpisodeNumber <- item.episodeNumber,
            colEpisodeName <- item.episodeName,
            colBangumiName <- item.bangumiName,
            colBangumiImage <- item.bangumiImage,
            colProgress <- item.progress,
            colDuration <- item.duration,
            colLastWatchedTime <- item.lastWatchedAt,
            colSource <- item.source,
            colSourceURL <- nonEmptyStringOrNil(item.sourceURL),
            colSourceName <- nonEmptyStringOrNil(item.sourceName)
        )
        try db.transaction {
            try db.run(histories.filter(colBangumiId == item.bangumiId).delete())
            try db.run(insert)
        }
    }

    func getHistories(limit: Int = 100) async throws -> [History] {
        guard let db = db else { return [] }

        var result: [History] = []
        let query = histories.order(colLastWatchedTime.desc).limit(limit)

        for row in try db.prepare(query) {
            let item = History(
                id: row[colHistoryId],
                bangumiId: row[colBangumiId],
                episodeId: row[colEpisodeId],
                episodeNumber: row[colEpisodeNumber],
                episodeName: row[colEpisodeName],
                bangumiName: row[colBangumiName],
                bangumiImage: row[colBangumiImage],
                progress: row[colProgress],
                duration: row[colDuration],
                lastWatchedAt: row[colLastWatchedTime],
                source: row[colSource],
                sourceURL: row[colSourceURL] ?? "",
                sourceName: row[colSourceName] ?? ""
            )
            result.append(item)
        }

        return result
    }

    func deleteHistory(id: String) async throws {
        guard let db = db else { return }
        let item = histories.filter(colHistoryId == id)
        try db.run(item.delete())
    }

    func clearHistories() async throws {
        guard let db = db else { return }
        try db.run(histories.delete())
    }

    private func nonEmptyStringOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func deduplicateHistories(using db: Connection) throws {
        var keptBangumiIds = Set<Int>()
        var idsToDelete: [String] = []
        let query = histories.order(colLastWatchedTime.desc)

        for row in try db.prepare(query) {
            let historyId = row[colHistoryId]
            let bangumiId = row[colBangumiId]

            guard row[colProgress] > 0 else {
                idsToDelete.append(historyId)
                continue
            }

            if keptBangumiIds.contains(bangumiId) {
                idsToDelete.append(historyId)
            } else {
                keptBangumiIds.insert(bangumiId)
            }
        }

        guard !idsToDelete.isEmpty else { return }

        try db.transaction {
            for historyId in idsToDelete {
                try db.run(histories.filter(colHistoryId == historyId).delete())
            }
        }
    }

    // MARK: - Downloads CRUD
    func insertDownload(_ item: DownloadEpisode) async throws {
        guard let db = db else { return }

        let insert = downloads.insert(or: .replace,
            colDownloadId <- item.id,
            colBangumiId <- item.bangumiId,
            colBangumiName <- item.bangumiName,
            colEpisodeNumber <- item.episodeNumber,
            colEpisodeName <- item.episodeName,
            colM3U8URL <- item.m3u8URL.absoluteString,
            colQuality <- item.quality,
            colPluginName <- item.pluginName,
            colStatus <- item.status.rawValue,
            colDownloadProgress <- item.progress,
            colTotalBytes <- item.totalBytes,
            colDownloadedBytes <- item.downloadedBytes,
            colLocalPath <- item.localPath?.absoluteString,
            colCreatedAt <- item.createdAt,
            colUpdatedAt <- item.updatedAt
        )
        try db.run(insert)
    }

    func getDownloads() async throws -> [DownloadEpisode] {
        guard let db = db else { return [] }

        var result: [DownloadEpisode] = []
        let query = downloads.order(colCreatedAt.desc)

        for row in try db.prepare(query) {
            let item = DownloadEpisode(
                id: row[colDownloadId],
                bangumiId: row[colBangumiId],
                bangumiName: row[colBangumiName],
                episodeNumber: row[colEpisodeNumber],
                episodeName: row[colEpisodeName],
                m3u8URL: URL(string: row[colM3U8URL])!,
                quality: row[colQuality],
                pluginName: row[colPluginName],
                status: DownloadEpisode.DownloadStatus(rawValue: row[colStatus]) ?? .pending,
                progress: row[colDownloadProgress],
                totalBytes: row[colTotalBytes],
                downloadedBytes: row[colDownloadedBytes],
                localPath: row[colLocalPath].flatMap { URL(string: $0) },
                createdAt: row[colCreatedAt],
                updatedAt: row[colUpdatedAt]
            )
            result.append(item)
        }

        return result
    }

    func updateDownload(_ item: DownloadEpisode) async throws {
        try await insertDownload(item)
    }

    func deleteDownload(id: String) async throws {
        guard let db = db else { return }
        let item = downloads.filter(colDownloadId == id)
        try db.run(item.delete())
    }
}

enum DatabaseManagerError: LocalizedError {
    case storageUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .storageUnavailable(let detail):
            return "本地数据库目录不可写：\(detail)"
        }
    }
}
