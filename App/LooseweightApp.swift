import LooseweightKit
import SwiftData
import SwiftUI

@main
struct LooseweightApp: App {
    @State private var model = AppModel()
    private let container: ModelContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let inMemory = arguments.contains("-uiTest")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: Schema(LooseweightSchema.models), configurations: [configuration])
        } catch {
            fatalError("Looseweight could not open its database: \(error)")
        }
        // Warm the food table off the main thread; the first search would otherwise pay for it.
        Task.detached(priority: .utility) { _ = FoodDatabase.shared.records.count }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.unitsMode, model.unitsMode)
                .task { prepareForUITestsIfNeeded() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func prepareForUITestsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedDemoData") {
            DemoContent.seed(into: container.mainContext, model: model)
        }
    }
}
