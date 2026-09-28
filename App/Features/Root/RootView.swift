import SwiftUI

enum AppTab: Hashable {
    case today, progress, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .today
    @State private var isScanning = false

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
        .animation(Theme.spring, value: model.profile == nil)
        .fullScreenCover(isPresented: $isScanning) {
            ScanFlowView()
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView(onScan: { isScanning = true })
            }
            Tab("Progress", systemImage: "chart.line.downtrend.xyaxis", value: AppTab.progress) {
                ProgressScreen()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            Button {
                isScanning = true
            } label: {
                Label("Scan a meal", systemImage: "camera.viewfinder")
                    .font(.rounded(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("scanAccessory")
        }
    }
}
