import Foundation

/// A separate object the phone found on its own (Vision foreground instance segmentation).
public struct OnDeviceRegion: Sendable {
    public var number: Int
    public var mask: RegionMask
    public var measurement: RegionMeasurement?

    public init(number: Int, mask: RegionMask, measurement: RegionMeasurement? = nil) {
        self.number = number
        self.mask = mask
        self.measurement = measurement
    }
}

public struct ClassifierLabel: Hashable, Sendable {
    public var label: String
    public var confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

public struct BarcodeFinding: Hashable, Sendable {
    public var payload: String
    public var product: FoodRecord?

    public init(payload: String, product: FoodRecord? = nil) {
        self.payload = payload
        self.product = product
    }
}

public struct PortionHint: Hashable, Sendable, Codable {
    public var food: String
    public var typicalGrams: Double
    public var timesLogged: Int

    public init(food: String, typicalGrams: Double, timesLogged: Int) {
        self.food = food
        self.typicalGrams = typicalGrams
        self.timesLogged = timesLogged
    }
}

/// Everything the phone learned on the device about one photo, before any AI call.
public struct CaptureInsights: Sendable {
    /// Upright size in pixels of the photo sent to the model (image 1).
    public var photoWidth: Int
    public var photoHeight: Int
    public var deviceHasLiDAR: Bool
    public var scale: ScaleReport?
    public var regions: [OnDeviceRegion]
    public var classifierLabels: [ClassifierLabel]
    public var recognizedText: [String]
    public var barcodes: [BarcodeFinding]
    public var qualityWarnings: [String]
    public var mealName: String?
    public var localTime: String?
    public var userNote: String?
    public var portionHints: [PortionHint]
    public var cuisineHint: String?

    public init(
        photoWidth: Int,
        photoHeight: Int,
        deviceHasLiDAR: Bool = false,
        scale: ScaleReport? = nil,
        regions: [OnDeviceRegion] = [],
        classifierLabels: [ClassifierLabel] = [],
        recognizedText: [String] = [],
        barcodes: [BarcodeFinding] = [],
        qualityWarnings: [String] = [],
        mealName: String? = nil,
        localTime: String? = nil,
        userNote: String? = nil,
        portionHints: [PortionHint] = [],
        cuisineHint: String? = nil
    ) {
        self.photoWidth = photoWidth
        self.photoHeight = photoHeight
        self.deviceHasLiDAR = deviceHasLiDAR
        self.scale = scale
        self.regions = regions
        self.classifierLabels = classifierLabels
        self.recognizedText = recognizedText
        self.barcodes = barcodes
        self.qualityWarnings = qualityWarnings
        self.mealName = mealName
        self.localTime = localTime
        self.userNote = userNote
        self.portionHints = portionHints
        self.cuisineHint = cuisineHint
    }
}
