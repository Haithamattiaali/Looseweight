import SwiftUI

enum AppTab: Hashable {
    case today, progress, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .today
    @State private var isScanning = false
    @Namespace private var scanSpace

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
            ScanFlowView()
                .navigationTransition(.zoom(sourceID: "scan", in: scanSpace))
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "circle.circle", value: AppTab.today) {
                TodayView(onScan: { isScanning = true })
            }
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
                Image(systemName: "circle.inset.filled")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.leaf)
                Text("Scan a meal")
                    .font(.rounded(.body, weight: .semibold))
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
