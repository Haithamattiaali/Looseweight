import Foundation

/// Prompt, tools and output schema for the meal analysis. Kept byte-stable so the prefix caches well.
public enum AnalysisPrompt {
    public static let system = """
    You estimate what is on a plate for a weight-loss food log. People plan their eating on these numbers, so \
    accuracy matters more than speed, and an honest range beats a confident guess.

    What you receive
    - Image 1: the meal photo. All coordinates are pixels of image 1, origin at the top-left.
    - Image 2 (when present): the same photo with the numbered regions the phone found on the device, and a 5 cm scale bar.
    - Further images (when present): the same plate from other angles, picked from a short capture sweep. Use them \
    to see sides, heights, hidden items and counts. Each food is still one item, and coordinates stay in image 1.
    - An on-device report. The phone measured the scene itself: the table plane from ARKit, depth from LiDAR on \
    Pro iPhones, the camera height and tilt, the pixel scale, and per-region area, volume and heights. These are \
    physical measurements; prefer them over visual impressions. A region usually holds a whole dish (plate plus \
    food), so split it into foods yourself.

    How to work
    0. First check that the photo shows food or drink. When it shows none (a person, a pet, a room, a screen, \
    an empty plate, a document), set no_food true, give no_food_reason in a few plain words (for example \
    "a laptop on a desk"), return an empty items list and stop: call no tools. Otherwise set no_food false and \
    no_food_reason null.
    1. List every food and drink you can see, including sauces, dressings, oils, toppings, bread and drinks. Split \
    mixed plates into components you can weigh (for example rice, chicken, cooking oil). Log a dish as one item \
    only when it cannot be split (soup, pizza, a sandwich).
    2. Call search_foods for each item and choose the match that fits the food as served (cooked or raw, fried or \
    grilled, with or without skin). Search again with other words when no candidate fits. Use food_id null only \
    when nothing reasonable exists. Some rows show an energy range because they merge several variants; choose \
    per_100g values inside that range that fit what you see.
    3. Weigh each item:
       - Depth available: call measure_foods once per dish with one polygon per food. grams = volume above the \
    plate floor × density. Subtract bones, shells, peel and empty space; the floor comes from bare plate around \
    the food, so check it against the plate rim height.
       - Table plane but no depth: call measure_foods for real areas, estimate the thickness, and use \
    grams = area × thickness × density.
       - No measurements: use visual scale (a standard dinner plate is 26–28 cm, a fork 18–20 cm, a teaspoon \
    13–15 cm, the pixel scale when given) and count pieces where you can.
       - Packaged food with readable label text or a barcode product: use those values and the pack size.
    1b. Drinks are items too. Detect every drink in view: water, juice, soda, coffee, tea, milk, smoothies, \
    shakes, and soups served to be drunk from a cup or mug. Give each item kind "drink" or "food". For a drink \
    set drink_unit to its natural unit (glass, can, bottle, mug, cup; sip only when it is a small taste) and \
    ml_per_unit to the volume one such unit holds as you see it (a can 330, a mug 300, a glass 250); grams is \
    what is in it now (mL × density), not the empty container. Include added sugar, milk or syrup as their own \
    items. For food set drink_unit and ml_per_unit null.
    4. Add hidden ingredients as their own items with is_hidden_ingredient true when you see signs of them: oil \
    sheen, deep-fried or pan-fried surfaces, butter, dressing, sugar in drinks. Do not add hidden items without \
    a visual reason.
    5. Call zoom_photo when the identity or the amount depends on detail you cannot see well.
    6. For every item give grams_low and grams_high as a realistic 80% range, and a confidence from 0 to 1.

    Typical bulk densities as served, g per mL (loose → packed):
    cooked rice 0.65–0.85; rice dishes such as kabsa, biryani, mandi 0.70–0.90; cooked pasta 0.55–0.75; \
    couscous, bulgur, quinoa 0.65–0.80; mashed potato 0.85–1.00; potato chunks 0.60–0.75; French fries 0.30–0.45; \
    leafy salad 0.08–0.20; chopped raw vegetables 0.40–0.60; cooked vegetables 0.55–0.75; cooked beans, lentils, \
    chickpeas 0.70–0.85; hummus and thick dips 1.00–1.10; solid meat, chicken or fish pieces 0.95–1.10; shredded \
    or diced meat 0.55–0.75; cooked mince 0.60–0.80; scrambled eggs 0.85–0.95; sliced bread 0.22–0.35; \
    flatbread 0.35–0.50; cake 0.30–0.50; hard cheese 1.05–1.15; grated cheese 0.40–0.50; yogurt, soup, sauce, \
    drinks 1.00–1.05; oil 0.92; fruit pieces 0.55–0.70; whole nuts 0.55–0.65; breakfast flakes 0.12–0.20; \
    pizza 0.55–0.75.

    Answer with the final JSON only. Use short plain English food names, such as "Basmati rice" or \
    "Grilled chicken breast". Notes, warnings and the clarifying question are shown to the person, who never \
    sees weights: describe amounts there in pieces, bites, cups or plain words, never in grams.
    """

    public static let searchTool = JSONValue.obj([
        "name": .string("search_foods"),
        "description": .string("Search the app's nutrition table (USDA SR Legacy based; values per 100 g). Call it for every food before answering, with a few words for the food as served, for example 'rice white cooked', 'chicken breast roasted', 'hummus'. Returns up to 8 candidates with ids. Search again with other words when none fits."),
        "input_schema": .obj([
            "type": .string("object"),
            "properties": .obj([
                "query": .obj(["type": .string("string"), "description": .string("Short food description")]),
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false),
        ]),
        "strict": .bool(true),
    ])

    public static let measureTool = JSONValue.obj([
        "name": .string("measure_foods"),
        "description": .string("Measure food portions with the phone's own sensors (ARKit table plane, LiDAR depth when the phone has it). Give one polygon per food in image 1 pixels. Put all foods of one plate or bowl in a single call and name the on-device region that holds them, so the plate floor can be read from the bare plate around them. Returns area in cm², volume in mL above the table and above the plate floor, heights in mm, plate diameter and rim height."),
        "input_schema": .obj([
            "type": .string("object"),
            "properties": .obj([
                "container_region": .obj([
                    "anyOf": .array([.obj(["type": .string("integer")]), .obj(["type": .string("null")])]),
                    "description": .string("Number of the on-device region (plate, bowl, tray) holding these foods, or null"),
                ]),
                "items": .obj([
                    "type": .string("array"),
                    "items": .obj([
                        "type": .string("object"),
                        "properties": .obj([
                            "label": .obj(["type": .string("string")]),
                            "polygon": .obj([
                                "type": .string("array"),
                                "description": .string("Outline as [x, y] points in image 1 pixels"),
                                "items": .obj(["type": .string("array"), "items": .obj(["type": .string("number")])]),
                            ]),
                        ]),
                        "required": .array([.string("label"), .string("polygon")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
            ]),
            "required": .array([.string("container_region"), .string("items")]),
            "additionalProperties": .bool(false),
        ]),
        "strict": .bool(true),
    ])

    public static let zoomTool = JSONValue.obj([
        "name": .string("zoom_photo"),
        "description": .string("Look at part of the original full-resolution photo. Use it when the identity or the amount depends on detail you cannot see well (texture, sauce, seeds, number of pieces). Coordinates are image 1 pixels."),
        "input_schema": .obj([
            "type": .string("object"),
            "properties": .obj([
                "x": .obj(["type": .string("number")]),
                "y": .obj(["type": .string("number")]),
                "width": .obj(["type": .string("number")]),
                "height": .obj(["type": .string("number")]),
            ]),
            "required": .array([.string("x"), .string("y"), .string("width"), .string("height")]),
            "additionalProperties": .bool(false),
        ]),
        "strict": .bool(true),
    ])

    private static func nullable(_ type: String) -> JSONValue {
        .obj(["anyOf": .array([.obj(["type": .string(type)]), .obj(["type": .string("null")])])])
    }

    public static let outputSchema: JSONValue = {
        let per100g = JSONValue.obj([
            "type": .string("object"),
            "properties": .obj([
                "kcal": .obj(["type": .string("number")]),
                "protein_g": .obj(["type": .string("number")]),
                "carbs_g": .obj(["type": .string("number")]),
                "fat_g": .obj(["type": .string("number")]),
            ]),
            "required": .array(["kcal", "protein_g", "carbs_g", "fat_g"].map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
        let item = JSONValue.obj([
            "type": .string("object"),
            "properties": .obj([
                "name": .obj(["type": .string("string")]),
                "food_id": nullable("string"),
                "grams": .obj(["type": .string("number")]),
                "grams_low": .obj(["type": .string("number")]),
                "grams_high": .obj(["type": .string("number")]),
                "method": .obj([
                    "type": .string("string"),
                    "enum": .array(PortionMethod.allCases.map { .string($0.rawValue) }),
                ]),
                "volume_ml": nullable("number"),
                "density_g_per_ml": nullable("number"),
                "per_100g": per100g,
                "confidence": .obj(["type": .string("number")]),
                "region_numbers": .obj(["type": .string("array"), "items": .obj(["type": .string("integer")])]),
                "polygon": .obj([
                    "type": .string("array"),
                    "items": .obj(["type": .string("array"), "items": .obj(["type": .string("number")])]),
                ]),
                "is_hidden_ingredient": .obj(["type": .string("boolean")]),
                "notes": .obj(["type": .string("string")]),
                "kind": .obj([
                    "type": .string("string"),
                    "enum": .array(FoodKind.allCases.map { .string($0.rawValue) }),
                ]),
                "drink_unit": .obj(["anyOf": .array([
                    .obj(["type": .string("string"), "enum": .array(DrinkUnit.allCases.map { .string($0.rawValue) })]),
                    .obj(["type": .string("null")]),
                ])]),
                "ml_per_unit": nullable("number"),
            ]),
            "required": .array([
                "name", "food_id", "grams", "grams_low", "grams_high", "method", "volume_ml", "density_g_per_ml",
                "per_100g", "confidence", "region_numbers", "polygon", "is_hidden_ingredient", "notes",
                "kind", "drink_unit", "ml_per_unit",
            ].map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
        return .obj([
            "type": .string("object"),
            "properties": .obj([
                "meal_title": .obj(["type": .string("string")]),
                "items": .obj(["type": .string("array"), "items": item]),
                "overall_confidence": .obj(["type": .string("number")]),
                "clarifying_question": nullable("string"),
                "warnings": .obj(["type": .string("array"), "items": .obj(["type": .string("string")])]),
                "no_food": .obj(["type": .string("boolean")]),
                "no_food_reason": nullable("string"),
            ]),
            "required": .array(["meal_title", "items", "overall_confidence", "clarifying_question", "warnings", "no_food", "no_food_reason"].map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }()

    // MARK: User message

    static func number(_ value: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f", value)
    }

    /// The on-device report placed next to the images.
    public static func report(for insights: CaptureInsights) -> String {
        var lines: [String] = []
        lines.append("Image 1 is \(insights.photoWidth)×\(insights.photoHeight) pixels.")
        if let scale = insights.scale {
            var capture = "Capture: ARKit table plane found. Camera \(number(scale.cameraHeightCm)) cm above the table, tilted \(number(scale.tiltDegrees))° from straight down. Scale on the table near the image centre: \(number(scale.pixelsPerCmAtTable, digits: 1)) px per cm."
            if scale.hasDepth {
                capture += " LiDAR depth fused from \(scale.depthFramesFused) frames"
                if let coverage = scale.depthCoverage { capture += " (\(number(coverage * 100))% of the table area measured)" }
                capture += "."
            } else {
                capture += insights.deviceHasLiDAR ? " LiDAR depth was not available for this shot." : " This phone has no LiDAR, so areas are real but heights are not measured."
            }
            lines.append(capture)
        } else {
            lines.append("Capture: no table plane or depth for this photo (for example it came from the photo library). Use visual scale.")
        }

        if !insights.regions.isEmpty {
            lines.append("On-device regions (numbered in image 2):")
            for region in insights.regions {
                var line = "#\(region.number)"
                if let box = region.mask.normalizedBounds {
                    let x = Int(box.x * Double(insights.photoWidth)), y = Int(box.y * Double(insights.photoHeight))
                    let w = Int(box.width * Double(insights.photoWidth)), h = Int(box.height * Double(insights.photoHeight))
                    line += " box x \(x), y \(y), w \(w), h \(h)"
                }
                if let m = region.measurement {
                    line += "; area \(number(m.areaCm2)) cm²"
                    if let diameter = m.container?.diameterCm { line += ", width \(number(diameter, digits: 1)) cm" }
                    if let volume = m.volumeAboveTableMl { line += ", volume above table \(number(volume)) mL" }
                    if let median = m.medianHeightMm, let maxHeight = m.maxHeightMm {
                        line += ", height median \(number(median)) mm, max \(number(maxHeight)) mm"
                    }
                }
                lines.append("  " + line)
            }
        }
        if !insights.classifierLabels.isEmpty {
            let labels = insights.classifierLabels.prefix(6).map { "\($0.label) \(number($0.confidence, digits: 2))" }
            lines.append("On-device image labels (Apple Vision, hints only): " + labels.joined(separator: ", ") + ".")
        }
        if !insights.recognizedText.isEmpty {
            let text = insights.recognizedText.prefix(40).joined(separator: " | ")
            lines.append("Text read on the device: \"\(String(text.prefix(1200)))\"")
        }
        for barcode in insights.barcodes {
            if let product = barcode.product {
                let n = product.per100g
                lines.append("Barcode \(barcode.payload): \(product.name) — per 100 g: \(number(n.kcal)) kcal, protein \(number(n.protein, digits: 1)) g, carbs \(number(n.carbs, digits: 1)) g, fat \(number(n.fat, digits: 1)) g (Open Food Facts; use food_id \"\(product.id)\").")
            } else {
                lines.append("Barcode \(barcode.payload): product not found.")
            }
        }
        if !insights.qualityWarnings.isEmpty {
            lines.append("Photo quality notes: " + insights.qualityWarnings.joined(separator: "; ") + ".")
        }
        var context: [String] = []
        if let meal = insights.mealName { context.append("meal: \(meal)") }
        if let time = insights.localTime { context.append("local time: \(time)") }
        if let cuisine = insights.cuisineHint { context.append("usual cuisine: \(cuisine)") }
        if !context.isEmpty { lines.append("Context: " + context.joined(separator: ", ") + ".") }
        if !insights.portionHints.isEmpty {
            let hints = insights.portionHints.prefix(12).map { "\($0.food) ≈ \(number($0.typicalGrams)) g (\($0.timesLogged)×)" }
            lines.append("This user's confirmed usual portions: " + hints.joined(separator: "; ") + ". Use them only when the photo agrees.")
        }
        if let note = insights.userNote, !note.isEmpty {
            lines.append("Note from the user: \"\(note)\"")
        }
        lines.append("Analyse the meal.")
        return lines.joined(separator: "\n")
    }

    static func imageBlock(jpeg: Data) -> JSONValue {
        .obj([
            "type": .string("image"),
            "source": .obj([
                "type": .string("base64"),
                "media_type": .string("image/jpeg"),
                "data": .string(jpeg.base64EncodedString()),
            ]),
        ])
    }

    static func userMessage(photoJPEG: Data, overlayJPEG: Data?, extraViewJPEGs: [Data] = [], insights: CaptureInsights) -> JSONValue {
        var content: [JSONValue] = [.obj(["type": .string("text"), "text": .string("Image 1 — meal photo:")]), imageBlock(jpeg: photoJPEG)]
        var number = 2
        if let overlayJPEG {
            content.append(.obj(["type": .string("text"), "text": .string("Image 2 — on-device regions and 5 cm scale bar:")]))
            content.append(imageBlock(jpeg: overlayJPEG))
            number = 3
        }
        for view in extraViewJPEGs.prefix(3) {
            content.append(.obj(["type": .string("text"), "text": .string(
                "Image \(number) — the same plate from another angle during the capture sweep (use it to see hidden sides, "
                    + "heights and counts; do not count any food twice; polygons and regions refer to Image 1 only):")]))
            content.append(imageBlock(jpeg: view))
            number += 1
        }
        content.append(.obj(["type": .string("text"), "text": .string(report(for: insights))]))
        return .obj(["role": .string("user"), "content": .array(content)])
    }
}

public enum PortionMethod: String, Codable, CaseIterable, Sendable {
    case depthVolume = "depth_volume"
    case areaThickness = "area_thickness"
    case visualEstimate = "visual_estimate"
    case count
    case label
    case userNote = "user_note"

    public var title: String {
        switch self {
        case .depthVolume: "Measured with LiDAR"
        case .areaThickness: "Measured area"
        case .visualEstimate: "Visual estimate"
        case .count: "Counted"
        case .label: "From label"
        case .userNote: "From your note"
        }
    }
}
