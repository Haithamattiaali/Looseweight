import LooseweightKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var apiKey = ""
    @State private var proxyToken = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var testSucceeded: Bool?
    @State private var confirmingDelete = false
    @State private var editingProfile = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    if let profile = model.profile, let targets = model.targets {
                        LabeledContent("Daily target", value: targets.kcal.kcalText)
                        LabeledContent("Goal", value: "\(profile.goalWeightKg.oneDecimal) kg at \(profile.weeklyLossKg.oneDecimal) kg/week")
                        ForEach(targets.notes, id: \.self) { note in
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button("Edit profile and goal") { editingProfile = true }
                } header: {
                    LabelText("Your plan")
                }

                UnitsSection(mode: $model.unitsMode)

                Section {
                    Picker("Connection", selection: $model.aiMode) {
                        ForEach(AIMode.allCases) { Text($0.title).tag($0) }
                    }
                    switch model.aiMode {
                    case .demo:
                        Text("Shows a sample result without calling the AI.").font(.footnote).foregroundStyle(.secondary)
                    case .personalKey:
                        SecureField(model.hasAPIKey ? "Key saved in Keychain" : "sk-ant-…", text: $apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Save key") { model.setAPIKey(apiKey); apiKey = "" }
                            .disabled(apiKey.isEmpty)
                    case .cloud:
                        TextField("https://…workers.dev", text: $model.proxyURL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField(model.hasProxyToken ? "Token saved in Keychain" : "App token", text: $proxyToken)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Save token") { model.setProxyToken(proxyToken); proxyToken = "" }
                            .disabled(proxyToken.isEmpty)
                    }
                    Picker("Precision", selection: $model.effort) {
                        ForEach(AnalysisEffort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if model.aiMode != .demo {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack {
                                Text("Test connection")
                                Spacer()
                                Image(systemName: statusSymbol)
                                    .foregroundStyle(statusColor)
                                    .symbolEffect(.pulse, isActive: testing)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        if let testResult {
                            Text(testResult).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    LabelText("AI analysis")
                } footer: {
                    Text("Photos are sent only to the connection you choose. The newest Claude Opus model is picked automatically.")
                }

                Section {
                    TextField("For example: Saudi home cooking", text: $model.cuisineHint)
                    TextField("Model override (advanced)", text: $model.modelOverride)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    LabelText("Hints for the AI")
                }

                Section {
                    ShareLink(item: Store.csvExport(in: context, units: model.unitsMode), preview: SharePreview("Looseweight export.csv")) {
                        Label("Export meals and weights (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                } header: {
                    LabelText("Your data")
                }

                Section {
                    Text("Nutrition data: USDA FoodData Central SR Legacy (public domain) via the TempoLife food dataset (CC-BY-4.0). Packaged food: Open Food Facts (ODbL).")
                    Text("Looseweight gives estimates to support healthy weight loss. It is not a medical device. Talk to a doctor before large diet changes, when pregnant, or with an eating disorder.")
                } header: {
                    LabelText("About")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .scrollContentBackground(.hidden)
            .background { DaylightGround() }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Settings")
            .sheet(isPresented: $editingProfile) {
                OnboardingView(isEditing: true)
            }
            .confirmationDialog("Delete all meals, weights and your profile?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    Store.deleteEverything(in: context)
                    model.profile = nil
                }
            }
        }
    }

    private var statusSymbol: String {
        if testing || testSucceeded == nil { return "antenna.radiowaves.left.and.right" }
        return testSucceeded == true ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        switch testSucceeded {
        case true?: Theme.leaf
        case false?: Theme.ember
        case nil: Theme.inkTertiary
        }
    }

    private func testConnection() async {
        testSucceeded = nil
        guard let connection = model.connection else {
            testResult = model.connectionProblem
            return
        }
        testing = true
        defer { testing = false }
        do {
            let id = try await model.resolveModel(client: ClaudeClient(connection: connection))
            testResult = "Connected. Using \(id)."
            testSucceeded = true
        } catch let error as ClaudeError {
            testResult = error.userMessage
            testSucceeded = false
        } catch {
            testResult = error.localizedDescription
            testSucceeded = false
        }
    }
}

/// "Units: Everyday (bites, sips, pieces) / Precise (grams)" with a one-line explanation.
private struct UnitsSection: View {
    @Binding var mode: UnitsMode

    var body: some View {
        Section {
            Picker("Units", selection: $mode) {
                ForEach(UnitsMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier("unitsPicker")
            Text(mode.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            LabelText("Units")
        }
    }
}
