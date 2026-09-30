import LooseweightKit
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today, inbox, progress, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .today
    @State private var isScanning = false
    @State private var reminder: PlannedMealRecord?
    @Namespace private var scanSpace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PlannedMealRecord> { $0.isPending == true }) private var pendingPlans: [PlannedMealRecord]

    var body: some View {
        Group {
            if model.profile == nil {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                tabs
                    .transition(.opacity)
            }
        }
        .animation(Theme.settle, value: model.profile == nil)
        .tint(Theme.leaf)
        .fullScreenCover(isPresented: $isScanning) {
            ScanFlowView(onPlanned: { tab = .inbox })
                .navigationTransition(.zoom(sourceID: "scan", in: scanSpace))
        }
        .sheet(item: $reminder) { record in
            PlanReminderSheet(record: record, onConfirm: { confirmation in
                Store.confirm(record, as: confirmation, in: context)
                PlanReminders.cancel(for: record)
                reminder = nil
            }, onLater: { reminder = nil })
            .presentationDetents([.height(340)])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { remindIfNeeded() }
        }
        .task { remindIfNeeded() }
    }

    /// Gentle reminder at the next app open (or once a plan is about an hour old). Never during UI tests.
    private func remindIfNeeded() {
        guard !model.isUITest, model.profile != nil, reminder == nil, !isScanning else { return }
        let lastOpen = model.lastAppOpen
        model.lastAppOpen = Date()
        let byID = Dictionary(pendingPlans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let due = PlanInbox.reminders(pendingPlans.compactMap(\.planned), lastAppOpen: lastOpen)
        if let first = due.first, let record = byID[first.id] {
            reminder = record
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "circle.circle", value: AppTab.today) {
                TodayView(onScan: { isScanning = true })
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                InboxView()
            }
            .badge(pendingPlans.count)
            Tab("Progress", systemImage: "chart.line.downtrend.xyaxis", value: AppTab.progress) {
                ProgressScreen()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            ScanAccessoryButton(namespace: scanSpace) { isScanning = true }
        }
    }
}

/// The scan orb docked as the tab bar's bottom accessory; it grows into the camera (zoom transition).
private struct ScanAccessoryButton: View {
    var namespace: Namespace.ID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AIOrb(size: 22, isActive: false)
                Text("Scan a meal")
                    .font(.rounded(.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "scan", in: namespace)
        .accessibilityLabel("Scan a meal")
        .accessibilityIdentifier("scanAccessory")
    }
}
