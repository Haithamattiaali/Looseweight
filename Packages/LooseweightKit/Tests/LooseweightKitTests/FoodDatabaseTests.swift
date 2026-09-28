import Testing
@testable import LooseweightKit

@Suite("Food database")
struct FoodDatabaseTests {
    let database = FoodDatabase.shared

    @Test func loadsBundledTable() {
        #expect(database.records.count > 6000)
        #expect(database.attribution.contains("CC-BY-4.0"))
        #expect(Set(database.records.map(\.id)).count == database.records.count)
    }

    @Test func valuesArePlausible() {
        for record in database.records {
            #expect(record.per100g.kcal >= 0 && record.per100g.kcal <= 902, "\(record.name)")
            #expect(record.per100g.protein + record.per100g.carbs + record.per100g.fat <= 101, "\(record.name)")
        }
    }

    @Test(arguments: [
        ("white rice cooked", "Rice, white"),
        ("rice white long grain cooked", "Rice, white, long-grain"),
        ("scrambled eggs", "Egg, whole, cooked, scrambled"),
        ("banana", "Banana"),
        ("olive oil", "Olive oil"),
        ("hummus", "Hummus"),
        ("french fries", "Potatoes, french fried"),
        ("chicken breast roasted", "Chicken"),
    ])
    func findsCommonFoods(query: String, expectedPrefix: String) {
        let results = database.search(query, limit: 8)
        #expect(!results.isEmpty)
        #expect(results.prefix(5).contains { $0.record.name.hasPrefix(expectedPrefix) }, "\(query) → \(results.prefix(5).map(\.record.name))")
    }

    @Test func cookedQueryPrefersCookedRows() {
        let top = database.search("white rice cooked", limit: 3)
        #expect(top.first.map { !$0.record.name.lowercased().contains("raw") && !$0.record.name.lowercased().contains("uncooked") } == true)
    }

    @Test func lookupByID() throws {
        let first = try #require(database.records.first)
        #expect(database.record(id: first.id) == first)
        #expect(database.record(id: "does-not-exist") == nil)
    }

    @Test func stemming() {
        #expect(TextNormalizer.stem("potatoes") == "potato")
        #expect(TextNormalizer.stem("berries") == "berry")
        #expect(TextNormalizer.stem("eggs") == "egg")
        #expect(TextNormalizer.stem("glass") == "glass")
        #expect(TextNormalizer.stem("hummus") == "hummus")
    }

    @Test func mergedRowsCarryAnEnergyRange() {
        let ambiguous = database.records.filter { $0.kcalRange != nil }
        #expect(ambiguous.count > 100)
        for record in ambiguous {
            let range = try! #require(record.kcalRange)
            #expect(range.contains(record.per100g.kcal), "\(record.name)")
        }
    }
}
