import Foundation

public struct FoodRecord: Codable, Hashable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case usda
        case curated
        case openFoodFacts
        case label
        case custom
        case aiEstimate
    }

    public let id: String
    public let name: String
    public let category: String
    public let per100g: Nutrients
    public let sugar: Double?
    public let saturatedFat: Double?
    public let sodiumMg: Double?
    public let source: Source
    /// Present when the entry merges several source rows with different energy.
    /// A value chosen for a specific plate must stay inside this range.
    public let kcalRange: ClosedRange<Double>?

    public init(
        id: String,
        name: String,
        category: String,
        per100g: Nutrients,
        sugar: Double? = nil,
        saturatedFat: Double? = nil,
        sodiumMg: Double? = nil,
        source: Source,
        kcalRange: ClosedRange<Double>? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.per100g = per100g
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.sodiumMg = sodiumMg
        self.source = source
        self.kcalRange = kcalRange
    }
}

public struct FoodSearchResult: Hashable, Sendable {
    public let record: FoodRecord
    public let score: Double
}

public enum FoodDatabaseError: Error, Equatable {
    case resourceMissing
    case malformed(String)
}

/// The bundled nutrition table (USDA SR Legacy based) plus an in-memory search index.
public final class FoodDatabase: Sendable {
    public let records: [FoodRecord]
    public let attribution: String
    public let version: String
    private let byID: [String: Int]
    private let index: FoodSearchIndex

    public init(records: [FoodRecord], attribution: String = "", version: String = "custom") {
        self.records = records
        self.attribution = attribution
        self.version = version
        var byID: [String: Int] = [:]
        for (offset, record) in records.enumerated() { byID[record.id] = offset }
        self.byID = byID
        self.index = FoodSearchIndex(names: records.map(\.name))
    }

    /// Loads `foods.json` shipped in the package resources.
    public static func bundled() throws -> FoodDatabase {
        guard let url = Bundle.module.url(forResource: "foods", withExtension: "json") else {
            throw FoodDatabaseError.resourceMissing
        }
        return try FoodDatabase(jsonData: Data(contentsOf: url))
    }

    /// Lazily loaded shared table. Loading takes ~100 ms, so the first access should happen off the main thread.
    public static let shared: FoodDatabase = {
        do {
            return try bundled()
        } catch {
            preconditionFailure("LooseweightKit: bundled food table failed to load: \(error)")
        }
    }()

    public convenience init(jsonData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let categories = root["categories"] as? [String],
              let fields = root["fields"] as? [String],
              let rows = root["foods"] as? [[Any]]
        else { throw FoodDatabaseError.malformed("top level") }

        func column(_ name: String) throws -> Int {
            guard let position = fields.firstIndex(of: name) else { throw FoodDatabaseError.malformed("missing field \(name)") }
            return position
        }
        let cID = try column("id"), cName = try column("name"), cCategory = try column("category")
        let cKcal = try column("kcal"), cProtein = try column("protein"), cCarbs = try column("carbs")
        let cFat = try column("fat"), cFiber = try column("fiber"), cSugar = try column("sugar")
        let cSatFat = try column("saturatedFat"), cSodium = try column("sodiumMg")
        let cSource = try column("source"), cRange = try column("kcalRange")

        func number(_ value: Any) -> Double? {
            (value as? NSNumber)?.doubleValue
        }

        var records: [FoodRecord] = []
        records.reserveCapacity(rows.count)
        for row in rows {
            guard row.count == fields.count,
                  let id = row[cID] as? String,
                  let name = row[cName] as? String,
                  let categoryIndex = number(row[cCategory]).map(Int.init),
                  categories.indices.contains(categoryIndex),
                  let kcal = number(row[cKcal])
            else { throw FoodDatabaseError.malformed("row \(records.count)") }

            var range: ClosedRange<Double>?
            if let bounds = row[cRange] as? [Any], bounds.count == 2,
               let low = number(bounds[0]), let high = number(bounds[1]), low <= high {
                range = low...high
            }
            records.append(FoodRecord(
                id: id,
                name: name,
                category: categories[categoryIndex],
                per100g: Nutrients(
                    kcal: kcal,
                    protein: number(row[cProtein]) ?? 0,
                    carbs: number(row[cCarbs]) ?? 0,
                    fat: number(row[cFat]) ?? 0,
                    fiber: number(row[cFiber]) ?? 0
                ),
                sugar: number(row[cSugar]),
                saturatedFat: number(row[cSatFat]),
                sodiumMg: number(row[cSodium]),
                source: number(row[cSource]) == 0 ? .usda : .curated,
                kcalRange: range
            ))
        }
        self.init(
            records: records,
            attribution: root["attribution"] as? String ?? "",
            version: root["version"] as? String ?? "unknown"
        )
    }

    public func record(id: String) -> FoodRecord? {
        byID[id].map { records[$0] }
    }

    public func search(_ query: String, limit: Int = 8) -> [FoodSearchResult] {
        let hits = index.search(query, limit: max(limit, 1) * 2).map { hit in
            let record = records[hit.index]
            let sourceWeight = record.source == .usda ? 1.0 : 0.97
            return FoodSearchResult(record: record, score: hit.score * sourceWeight)
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }
}
