import LooseweightKit
import PhotosUI
import RealityKit
import SwiftData
import SwiftUI

/// Full-screen flow: camera → on-device + AI analysis → review → save.
struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    private enum Stage {
        case camera
        case analyzing(CapturedMeal, AnalysisFlow)
        case review(CapturedMeal, MealEstimate)
    }

    @State private var stage: Stage = .camera
    @State private var mealType = MealType.suggested()
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var showingBarcode = false

    var body: some View {
        ZStack {
            switch stage {
            case .camera:
                CameraScreen(
                    mealType: $mealType,
                    note: $note,
                    onClose: { dismiss() },
                    onCapture: startAnalysis,
                    onBarcode: { showingBarcode = true }
                )
                .transition(.opacity)
            case let .analyzing(meal, flow):
                AnalysisView(meal: meal, flow: flow, onRetry: { stage = .camera }, onClose: { dismiss() })
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .task(id: meal.id) {
                        await flow.run()
                        if case let .success(estimate)? = flow.outcome {
                            withAnimation(Theme.settle) { stage = .review(meal, estimate) }
                        }
                    }
            case let .review(meal, estimate):
                ReviewView(
                    image: meal.image,
                    estimate: estimate,
                    mealType: $mealType,
                    onSave: { edited in
                        let photo = ImageTools.cgImage(meal.image)
                            .flatMap { ImageTools.resized($0, to: ImageTools.sizeForModel(width: $0.width / 3, height: $0.height / 3)) }
                            .flatMap { ImageTools.jpeg($0, quality: 0.7) }
                        Store.save(edited, mealType: mealType, photo: photo, source: meal.source.rawValue, in: context)
                        dismiss()
                    },
                    onRetake: { withAnimation(Theme.settle) { stage = .camera } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.settle, value: stageKey)
        .sheet(isPresented: $showingBarcode) {
            BarcodeFlowView(mealType: mealType) { dismiss() }
        }
    }

    private var stageKey: Int {
        switch stage {
        case .camera: 0
        case .analyzing: 1
        case .review: 2
        }
    }

    private func startAnalysis(_ meal: CapturedMeal) {
        let flow = AnalysisFlow(
            meal: meal,
            model: model,
            portionHints: Store.portionHints(in: context),
            mealType: mealType,
            userNote: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        withAnimation(Theme.settle) { stage = .analyzing(meal, flow) }
    }
}

// MARK: - Camera

private struct CameraScreen: View {
    @Binding var mealType: MealType
    @Binding var note: String
    var onClose: () -> Void
    var onCapture: (CapturedMeal) -> Void
    var onBarcode: () -> Void

    @State private var controller: ARCaptureController?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var showingNote = false
    @State private var showingFrameHint = true
    @State private var shots = 0

    private var arAvailable: Bool { ARCaptureController.isSupported }
    /// Without AR (simulator, demo) the frame is always "ready".
    private var ready: Bool { controller?.guidance.ready ?? true }

    var body: some View {
        ZStack {
            preview.ignoresSafeArea()
            CaptureFrame(ready: ready, showsHint: showingFrameHint)
            VStack(spacing: Theme.m) {
                topBar
                Spacer()
                guidancePill
                bottomBar
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, Theme.s)
        }
        .background(Color.black)
        .sensoryFeedback(.alignment, trigger: ready) { old, new in !old && new }
        .sensoryFeedback(.impact(weight: .medium), trigger: shots)
        .onAppear {
            if arAvailable, controller == nil { controller = ARCaptureController() }
            controller?.start()
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(Theme.settle) { showingFrameHint = false }
        }
        .onDisappear { controller?.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
        .alert("Couldn't capture", isPresented: Binding(get: { captureError != nil }, set: { if !$0 { captureError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureError ?? "")
        }
        .sheet(isPresented: $showingNote) {
            NoteSheet(note: $note)
                .presentationDetents([.height(260)])
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let controller {
            ARPreview(arView: controller.arView)
        } else {
            Image(uiImage: DemoContent.photo())
                .resizable()
                .scaledToFill()
                .overlay(alignment: .top) {
                    GlassPill {
                        Text("Demo photo — this device has no AR camera")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.top, 110)
                }
        }
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: Theme.s) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close")

                Spacer()

                Menu {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage).tag(type)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(mealType.title)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                }
                .buttonStyle(.glass)

                if controller?.hasLiDAR == true {
                    Image(systemName: "cube.transparent")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .modifier(ControlGlass(tint: nil, shape: Circle()))
                        .accessibilityLabel("LiDAR depth on")
                }
            }
        }
        .padding(.top, Theme.xs)
    }

    private var guidancePill: some View {
        let guidance = controller?.guidance
        return HStack(spacing: 10) {
            LevelBubble(tilt: guidance?.tiltDegrees ?? 0, ready: ready)
                .frame(width: 26, height: 26)
            Text(pillMessage(guidance))
                .font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
            if let distance = guidance?.distanceCm {
                Text("\(Int(distance)) cm")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: distance))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.m)
        .padding(.vertical, 10)
        .modifier(ControlGlass(tint: ready ? Theme.leaf : nil, shape: Capsule()))
        .animation(Theme.settle, value: guidance)
        .animation(Theme.settle, value: showingFrameHint)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guidance")
    }

    private func pillMessage(_ guidance: ARCaptureController.Guidance?) -> String {
        if let guidance { return showingFrameHint && guidance.ready ? "Fit every plate and side inside the frame" : guidance.message }
        return "Tap the shutter to try the demo"
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(alignment: .center, spacing: 28) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.title3)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Choose a photo")

                ShutterButton(ready: ready, isCapturing: isCapturing, action: shoot)

                Menu {
                    Button { showingNote = true } label: { Label("Add a note", systemImage: "text.bubble") }
                    Button(action: onBarcode) { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                } label: {
                    Image(systemName: "square.and.pencil").font(.title3)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("More")
            }
        }
        .padding(.top, Theme.xs)
    }

    private func shoot() {
        guard !isCapturing else { return }
        isCapturing = true
        shots += 1
        Task {
            defer { isCapturing = false }
            if let controller {
                do {
                    onCapture(try await controller.capture())
                } catch {
                    captureError = error.localizedDescription
                }
            } else {
                onCapture(CapturedMeal(image: DemoContent.photo(), geometry: nil, deviceHasLiDAR: false, source: .demo))
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            captureError = "That photo could not be opened."
            return
        }
        onCapture(CapturedMeal(image: image, geometry: nil, deviceHasLiDAR: false, source: .library))
    }
}

/// The shutter: glass orb, inner disc settles to full size when the phone is ready.
private struct ShutterButton: View {
    var ready: Bool
    var isCapturing: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: 66, height: 66)
                    .scaleEffect(ready || reduceMotion ? 1 : 0.92)
                    .animation(Theme.settle, value: ready)
                if isCapturing { ProgressView().tint(.black) }
            }
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(ready ? Theme.leaf : .gray)
        .disabled(isCapturing)
        .accessibilityIdentifier("shutter")
        .accessibilityLabel("Measure the meal")
    }
}

/// Corner brackets around the WHOLE capture area — everything inside the frame is analysed, every plate and side.
/// White while aligning, leaf (and slightly tighter) once level and in range.
private struct CaptureFrame: View {
    var ready: Bool
    var showsHint: Bool

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = ready ? 22 : 16
            let rect = CGRect(x: inset, y: 110, width: proxy.size.width - inset * 2, height: max(proxy.size.height - 320, 100))
            ZStack(alignment: .top) {
                CaptureBrackets(length: ready ? 40 : 32)
                    .stroke(ready ? Theme.leaf : Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: .black.opacity(0.3), radius: 6)
                if showsHint {
                    GlassPill {
                        Text("Fit every plate and side inside the frame")
                            .font(.caption.weight(.semibold))
                    }
                    .position(x: rect.midX, y: rect.minY + 28)
                    .transition(.opacity)
                }
            }
        }
        .animation(Theme.settle, value: ready)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ARPreview: UIViewRepresentable {
    let arView: ARView

    func makeUIView(context: Context) -> ARView { arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Four rounded corner marks around a rectangle.
private struct CaptureBrackets: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l = min(length, rect.width / 3, rect.height / 3)
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * l))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * l, y: corner.y))
        }
        return path
    }
}

/// Bubble level: the dot slides to the centre when the phone is flat.
private struct LevelBubble: View {
    var tilt: Double
    var ready: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(.primary.opacity(0.35), lineWidth: 1.5)
            Circle()
                .fill(ready ? Theme.leaf : Theme.honey)
                .frame(width: 9, height: 9)
                .offset(y: CGFloat(min(tilt, 45) / 45 * 9))
                .animation(Theme.settle, value: tilt)
        }
        .accessibilityLabel(tilt <= 25 ? "Phone is level" : "Tilt the phone flat")
    }
}

private struct NoteSheet: View {
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("For example: cooked with 1 tbsp olive oil", text: $note, axis: .vertical)
                    .lineLimit(3...5)
            }
            .navigationTitle("Note for the AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
