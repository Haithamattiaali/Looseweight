import Foundation

enum TextNormalizer {
    static let stopwords: Set<String> = [
        "and", "or", "of", "in", "the", "a", "an", "to", "for", "from", "on", "as", "by", "with",
        "type", "types", "all", "ns", "nfs", "style", "made",
    ]

    /// Everyday words mapped to the vocabulary the USDA names use.
    static let aliases: [String: [String]] = [
        "fries": ["french", "fried", "potato"],
        "crisps": ["potato", "chips"],
        "soda": ["carbonated", "beverage"],
        "coke": ["carbonated", "cola"],
        "cola": ["carbonated", "cola"],
        "ketchup": ["catsup"],
        "yoghurt": ["yogurt"],
        "aubergine": ["eggplant"],
        "courgette": ["zucchini"],
        "prawn": ["shrimp"],
        "prawns": ["shrimp"],
        "mince": ["ground", "beef"],
        "minced": ["ground"],
        "porridge": ["oatmeal"],
        "oats": ["oat"],
        "chickpea": ["chickpeas"],
        "garbanzo": ["chickpeas"],
        "capsicum": ["peppers", "sweet"],
        "rocket": ["arugula"],
        "biscuit": ["cookie"],
        "biscuits": ["cookies"],
        "steak": ["steak", "beef"],
        "omelette": ["omelet"],
        "laban": ["buttermilk"],
        "labneh": ["yogurt", "strained"],
        "shawarma": ["chicken", "roasted"],
        "kabsa": ["rice", "chicken"],
        "mandi": ["rice", "chicken"],
    ]

    static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var result: [String] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            if !stopwords.contains(current) { result.append(stem(current)) }
            current = ""
        }
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    static func queryTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var expanded: [String] = []
        for raw in folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) {
            if let alias = aliases[raw] {
                expanded.append(contentsOf: alias)
            } else {
                expanded.append(raw)
            }
        }
        var seen = Set<String>()
        return tokens(expanded.joined(separator: " ")).filter { seen.insert($0).inserted }
    }

    static func stem(_ token: String) -> String {
        guard token.count > 3, token.allSatisfy(\.isLetter) else { return token }
        if token.hasSuffix("ies") { return String(token.dropLast(3)) + "y" }
        if token.hasSuffix("oes") || token.hasSuffix("ches") || token.hasSuffix("shes") || token.hasSuffix("xes") || token.hasSuffix("sses") {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("s"), !token.hasSuffix("ss"), !token.hasSuffix("us") { return String(token.dropLast()) }
        return token
    }

    static let cookedWords: Set<String> = [
        "cooked", "boiled", "grilled", "fried", "baked", "roasted", "steamed", "broiled", "braised",
        "stewed", "sauteed", "poached", "toasted", "scrambled", "microwaved", "heated", "prepared", "simmered",
    ]
    static let rawWords: Set<String> = ["raw", "uncooked", "unprepared", "dry"]
}

struct FoodSearchIndex: Sendable {
    struct Hit: Sendable {
        let index: Int
        let score: Double
    }

    private let nameTokens: [[String]]
    private let headTokens: [Set<String>]
    private let postings: [String: [Int]]
    private let vocabulary: [String]
    private let idf: [String: Double]
    private let maxIDF: Double

    init(names: [String]) {
        var nameTokens: [[String]] = []
        var headTokens: [Set<String>] = []
        var postings: [String: [Int]] = [:]
        nameTokens.reserveCapacity(names.count)
        for (offset, name) in names.enumerated() {
            let tokens = TextNormalizer.tokens(name)
            nameTokens.append(tokens)
            let head = name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? name
            headTokens.append(Set(TextNormalizer.tokens(head)))
            for token in Set(tokens) { postings[token, default: []].append(offset) }
        }
        let count = Double(max(names.count, 1))
        var idf: [String: Double] = [:]
        for (token, list) in postings { idf[token] = log(1 + count / Double(list.count)) }
        self.nameTokens = nameTokens
        self.headTokens = headTokens
        self.postings = postings
        self.vocabulary = postings.keys.sorted()
        self.idf = idf
        self.maxIDF = log(1 + count)
    }

    private func vocabulary(withPrefix prefix: String, cap: Int = 60) -> [String] {
        var low = 0, high = vocabulary.count
        while low < high {
            let mid = (low + high) / 2
            if vocabulary[mid] < prefix { low = mid + 1 } else { high = mid }
        }
        var result: [String] = []
        var position = low
        while position < vocabulary.count, vocabulary[position].hasPrefix(prefix), result.count < cap {
            result.append(vocabulary[position])
            position += 1
        }
        return result
    }

    func search(_ query: String, limit: Int) -> [Hit] {
        let queryTokens = TextNormalizer.queryTokens(query)
        guard !queryTokens.isEmpty, limit > 0 else { return [] }

        var candidates = Set<Int>()
        for token in queryTokens {
            if let list = postings[token] { candidates.formUnion(list) }
            if token.count >= 3 {
                for word in vocabulary(withPrefix: token) where word != token {
                    candidates.formUnion(postings[word] ?? [])
                }
            }
        }

        let wantsCooked = queryTokens.contains { TextNormalizer.cookedWords.contains($0) }
        let wantsRaw = queryTokens.contains("raw")
        var hits: [Hit] = []
        hits.reserveCapacity(candidates.count)

        for candidate in candidates {
            let tokens = nameTokens[candidate]
            let tokenSet = Set(tokens)
            var score = 0.0
            var matched = 0
            for token in queryTokens {
                let weight = idf[token] ?? maxIDF
                if tokenSet.contains(token) {
                    score += weight * (headTokens[candidate].contains(token) ? 1.3 : 1.0)
                    matched += 1
                } else if token.count >= 3, tokens.contains(where: { $0.hasPrefix(token) || ($0.count >= 4 && token.hasPrefix($0)) }) {
                    score += weight * 0.6
                    matched += 1
                }
            }
            guard matched > 0 else { continue }
            let coverage = Double(matched) / Double(queryTokens.count)
            score *= 0.35 + 0.65 * coverage * coverage
            score /= 1 + 0.035 * Double(max(0, tokens.count - matched))
            if wantsCooked, tokenSet.contains(where: { TextNormalizer.rawWords.contains($0) }) { score *= 0.55 }
            if wantsRaw, tokenSet.contains(where: { TextNormalizer.cookedWords.contains($0) }) { score *= 0.55 }
            hits.append(Hit(index: candidate, score: score))
        }

        return Array(hits.sorted {
            $0.score != $1.score ? $0.score > $1.score : nameTokens[$0.index].count < nameTokens[$1.index].count
        }.prefix(limit))
    }
}
