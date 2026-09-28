import SwiftUI

struct AnalysisView: View {
    let meal: CapturedMeal
    let flow: AnalysisFlow
    var onRetry: () -> Void
    var onClose: () -> Void

    @State private var scanPhase = false

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 22) {
                    photo
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(flow.steps) { step in
                                StepRow(step: step)
                            }
                        }
                    }
                    .accessibilityIdentifier("analysisSteps")
                    if case let .failure(message)? = flow.outcome {
                        failure(message)
                    }
                }
                .padding(20)
            }
        }
        .onAppear { scanPhase = true }
    }

    private var photo: some View {
        Image(uiImage: meal.image)
            .resizable()
            .scaledToFill()
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, Theme.mint.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                        .offset(y: scanPhase ? proxy.size.height - 45 : -45)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: scanPhase)
                        .opacity(flow.outcome == nil ? 1 : 0)
                }
                .clipShape(.rect(cornerRadius: Theme.cardRadius))
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                Badge(text: sourceTitle, systemImage: sourceIcon, color: .white)
                    .padding(14)
            }
    }

    private var sourceTitle: String {
        switch meal.source {
        case .camera: meal.geometry?.heightField != nil ? "3D measured" : (meal.geometry != nil ? "Scale measured" : "Photo")
        case .library: "From library"
        case .demo: "Demo"
        }
    }

    private var sourceIcon: String {
        meal.geometry?.heightField != nil ? "cube.transparent" : "camera"
    }

    private func failure(_ message: String) -> some View {
        GlassCard(tint: Theme.coral) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Analysis stopped", systemImage: "exclamationmark.triangle.fill")
                    .font(.rounded(.headline, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text(message).font(.rounded(.subheadline))
                HStack {
                    Button("Try again", action: onRetry).buttonStyle(.glassProminent)
                    Button("Close", action: onClose).buttonStyle(.glass)
                }
            }
        }
    }
}

private struct StepRow: View {
    let step: AnalysisFlow.Step

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                switch step.state {
                case .running:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.coral)
                case .skipped:
                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                case .waiting:
                    Image(systemName: step.systemImage).foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
            .frame(width: 28, height: 28)
            .animation(Theme.spring, value: step.state)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(step.state == .waiting ? .secondary : .primary)
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
