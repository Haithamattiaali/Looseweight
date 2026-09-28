import LooseweightKit
import SwiftData
import SwiftUI
import Vision
import VisionKit

/// Packaged food: scan the barcode on the device, fetch exact per-100 g values, weigh or pick a portion.
struct BarcodeFlowView: View {
    let mealType: MealType
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var code: String?
    @State private var product: FoodRecord?
    @State private var lookupFailed = false
    @State private var grams = 100.0

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let product {
                    productCard(product)
                } else if code != nil {
                    ProgressView(lookupFailed ? "Not found in Open Food Facts" : "Looking up the product…")
                        .padding(.top, 40)
                    if lookupFailed {
                        Button("Scan again") { code = nil; lookupFailed = false }.buttonStyle(.glass)
                    }
                } else if scannerAvailable {
                    BarcodeScanner { payload in
                        code = payload
                        Task { await lookUp(payload) }
                    }
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .padding(.horizontal, 16)
                    Text("Point at the barcode on the pack").font(.rounded(.subheadline)).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Barcode scanning needs a camera", systemImage: "barcode.viewfinder",
                                           description: Text("Use a real iPhone to scan packaged food."))
                }
                Spacer(minLength: 0)
            }
            .background { AmbientBackground() }
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func productCard(_ product: FoodRecord) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(product.name).font(.rounded(.title3, weight: .bold))
                Text("Per 100 g: \(Int(product.per100g.kcal)) kcal · P \(product.per100g.protein.oneDecimal) g · C \(product.per100g.carbs.oneDecimal) g · F \(product.per100g.fat.oneDecimal) g")
                    .font(.rounded(.caption)).foregroundStyle(.secondary)
                HStack {
                    TextField("Grams", value: $grams, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.rounded(.title2, weight: .bold))
                        .frame(maxWidth: 120)
                    Text("g eaten").foregroundStyle(.secondary)
                    Spacer()
                    Text(product.per100g.amount(forGrams: grams).kcal.kcalText).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.teal)
                }
                Button {
                    let item = EstimatedItem(name: product.name, grams: grams, gramsLow: grams, gramsHigh: grams, per100g: product.per100g,
                                             food: FoodMatch(id: product.id, name: product.name, source: product.source), method: .label, confidence: 1)
                    Store.save(MealEstimate(title: product.name, items: [item], overallConfidence: 1, clarifyingQuestion: nil, warnings: [], modelID: nil, usedDepth: false),
                               mealType: mealType, photo: nil, source: "barcode", in: context)
                    dismiss()
                    onSaved()
                } label: {
                    Label("Save to \(mealType.title)", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Text("Data: Open Food Facts (ODbL)").font(.rounded(.caption2)).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }

    private func lookUp(_ payload: String) async {
        if let found = try? await OpenFoodFactsClient().product(barcode: payload) {
            product = found
        } else {
            lookupFailed = true
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var reported = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !reported else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    reported = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onFound(payload)
                    return
                }
            }
        }
    }
}
