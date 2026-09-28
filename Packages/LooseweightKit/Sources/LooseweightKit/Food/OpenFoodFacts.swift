import Foundation

/// Packaged-food lookup by barcode (Open Food Facts, ODbL). Values are per 100 g.
public struct OpenFoodFactsClient: Sendable {
    public let transport: HTTPTransport
    public var baseURL = URL(string: "https://world.openfoodfacts.org")!

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func product(barcode: String) async throws -> FoodRecord? {
        let digits = barcode.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        let url = baseURL.appendingPathComponent("api/v2/product/\(digits).json")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,serving_quantity")]
        let response = try await transport.send(HTTPRequest(
            method: "GET",
            url: components.url!,
            headers: ["user-agent": "Looseweight/1.0 (iOS calorie app)"],
            timeout: 15
        ))
        guard response.status == 200 else { return nil }
        return Self.parse(response.body, barcode: digits)
    }

    static func parse(_ data: Data, barcode: String) -> FoodRecord? {
        guard let root = try? JSONValue.parse(data),
              root["status"]?.intValue == 1,
              let product = root["product"],
              let nutriments = product["nutriments"]
        else { return nil }

        func value(_ key: String) -> Double? {
            if let number = nutriments[key]?.doubleValue { return number }
            if let text = nutriments[key]?.stringValue { return Double(text) }
            return nil
        }
        let energy = value("energy-kcal_100g") ?? value("energy_100g").map { $0 / 4.184 }
        guard let energy, energy.isFinite, energy >= 0, energy < 950 else { return nil }
        let kcal = (energy * 10).rounded() / 10

        let name = [product["brands"]?.stringValue?.split(separator: ",").first.map(String.init), product["product_name"]?.stringValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        return FoodRecord(
            id: "off:\(barcode)",
            name: name.isEmpty ? "Product \(barcode)" : name,
            category: "Packaged",
            per100g: Nutrients(
                kcal: kcal,
                protein: value("proteins_100g") ?? 0,
                carbs: value("carbohydrates_100g") ?? 0,
                fat: value("fat_100g") ?? 0,
                fiber: value("fiber_100g") ?? 0
            ),
            sugar: value("sugars_100g"),
            saturatedFat: value("saturated-fat_100g"),
            sodiumMg: value("sodium_100g").map { $0 * 1000 },
            source: .openFoodFacts
        )
    }
}
