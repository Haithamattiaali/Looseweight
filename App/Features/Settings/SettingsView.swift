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
    @State private var confirmingDelete = false
    @State private var editingProfile = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Your plan") {
                    if let profile = model.profile, let targets = model.targets {
                        LabeledContent("Daily target", value: targets.kcal.kcalText)
                        LabeledContent("Goal", value: "\(profile.goalWeightKg.oneDecimal) kg at \(profile.weeklyLossKg.oneDecimal) kg/week")
                        ForEach(targets.notes, id: \.self) { note in
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button("Edit profile and goal") { editingProfile = true }
                }

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
                                if testing { Spacer(); ProgressView() }
                            }
                        }
                        if let testResult {
                            Text(testResult).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("AI analysis")
                } footer: {
                    Text("Photos are sent only to the connection you choose. The newest Claude Opus model is picked automatically.")
                }

                Section {
                    TextField("For example: Saudi home cooking", text: $model.cuisineHint)
                    TextField("Model override (advanced)", text: $model.modelOverride)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Hints for the AI")
                }

                Section("Your data") {
                    ShareLink(item: Store.csvExport(in: context), preview: SharePreview("Looseweight export.csv")) {
                        Label("Export meals and weights (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                }

                Section("About") {
                    Text("Nutrition data: USDA FoodData Central SR Legacy (public domain) via the TempoLife food dataset (CC-BY-4.0). Packaged food: Open Food Facts (ODbL).")
                    Text("Looseweight gives estimates to support healthy weight loss. It is not a medical device. Talk to a doctor before large diet changes, when pregnant, or with an eating disorder.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground() }
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

    private func testConnection() async {
        guard let connection = model.connection else {
            testResult = model.connectionProblem
            return
        }
        testing = true
        defer { testing = false }
        do {
            let id = try await model.resolveModel(client: ClaudeClient(connection: connection))
            testResult = "Connected. Using \(id)."
        } catch let error as ClaudeError {
            testResult = error.userMessage
        } catch {
            testResult = error.localizedDescription
        }
    }
}
