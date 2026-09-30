import SwiftUI

/// "The plate reads": the captured photo with a light sweeping around it while the steps tick through.
struct AnalysisView: View {
    let meal: CapturedMeal
    let flow: AnalysisFlow
    var onRetry: () -> Void
    var onClose: () -> Void

    private var doneCount: Int { flow.steps.filter { $0.state == .done }.count }
    private var isRunning: Bool { flow.outcome == nil }

    var body: some View {
        ZStack {
            DaylightGround()
            ScrollView {
                VStack(spacing: Theme.xl) {
                    ReadingPhoto(image: meal.image, isRunning: isRunning, sourceTitle: sourceTitle, sourceIcon: sourceIcon)
                    if case let .failure(message)? = flow.outcome {
                        AnalysisFailure(message: message, onRetry: onRetry, onClose: onClose)
                    } else if case .noFood? = flow.outcome {
                        NoFoodFound(onRetake: onRetry, onClose: onClose)
                    } else {
                        stepList
                    }
                }
                .padding(Theme.gutter)
            }
        }
        .sensoryFeedback(.selection, trigger: doneCount)
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: Theme.m) {
            ForEach(flow.steps) { step in
                StepRow(step: step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("analysisSteps")
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
}

/// The full photo (everything captured is analysed, so it is never cropped to a circle), with a
/// light that travels around its edge while the analysis runs.
private struct ReadingPhoto: View {
    let image: UIImage
    var isRunning: Bool
    var sourceTitle: String
    var sourceIcon: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay { sweep }
            .overlay(alignment: .topLeading) {
                GlassPill {
                    Label(sourceTitle, systemImage: sourceIcon)
                        .font(.caption.weight(.semibold))
                }
                .padding(Theme.s)
            }
    }

    @ViewBuilder
    private var sweep: some View {
        if isRunning {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees((t * 90).truncatingRemainder(dividingBy: 360))
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: [.clear, Theme.leaf.opacity(0.9), .white, Theme.leaf.opacity(0.9), .clear, .clear],
                            center: .center,
                            angle: angle
                        ),
                        lineWidth: 4
                    )
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

private struct AnalysisFailure: View {
    var message: String
    var onRetry: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: Theme.m) {
            GlassPill(tint: Theme.ember) {
                Label("Analysis stopped", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: Theme.s) {
                    Button("Try again", action: onRetry).buttonStyle(.glassProminent).tint(Theme.ember)
                    Button("Close", action: onClose).buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The AI found no food or drink in the photo: nothing to review or save, only a retake.
private struct NoFoodFound: View {
    var onRetake: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: Theme.m) {
            GlassPill(tint: Theme.honey) {
                Label("No food found in this photo", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Point the camera at your meal and fit every plate inside the frame.")
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: Theme.s) {
                    Button("Retake", action: onRetake).buttonStyle(.glassProminent).tint(Theme.leaf)
                        .accessibilityIdentifier("noFoodRetake")
                    Button("Close", action: onClose).buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("noFoodFound")
    }
}

private struct StepRow: View {
    let step: AnalysisFlow.Step

    var body: some View {
        HStack(alignment: .top, spacing: Theme.s) {
            icon
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
                .animation(Theme.settle, value: step.state)

            VStack(alignment: .leading, spacing: 3) {
                StepTitle(title: step.title, isRunning: step.state == .running, isWaiting: step.state == .waiting)
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch step.state {
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark")
                .foregroundStyle(Theme.leaf)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "xmark")
                .foregroundStyle(Theme.ember)
        case .skipped:
            Image(systemName: "minus")
                .foregroundStyle(Theme.inkTertiary)
        case .waiting:
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundStyle(Theme.inkTertiary)
        }
    }
}

/// The step title stays a plain static Text (UI tests find "Identifying each food"); the running step breathes.
private struct StepTitle: View {
    var title: String
    var isRunning: Bool
    var isWaiting: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(title)
            .font(.body.weight(isRunning ? .semibold : .regular))
            .foregroundStyle(isWaiting ? Theme.inkTertiary : Theme.ink)
            .phaseAnimator([false, true]) { content, dim in
                content.opacity(isRunning && dim && !reduceMotion ? 0.45 : 1)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }
    }
}
