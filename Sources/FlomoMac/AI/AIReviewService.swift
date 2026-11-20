import Foundation
import Observation

@MainActor
@Observable
final class AIReviewService {
    private static let settingsKey = "ai.review.configuration"
    private static let secretAccount = "ai.review.apiKey"

    private let reportURL: URL
    private var activeRequest: UUID?

    private(set) var configuration: AIReviewConfiguration?
    private(set) var report: AIReviewReport?
    private(set) var errorMessage: String?

    var isGenerating: Bool { activeRequest != nil }

    init(storageDirectory: URL) {
        reportURL = storageDirectory.appendingPathComponent("ai-review.json")
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey) {
            configuration = try? JSONDecoder().decode(AIReviewConfiguration.self, from: data)
        }
        if let data = try? Data(contentsOf: reportURL) {
            report = try? JSONDecoder().decode(AIReviewReport.self, from: data)
        }
    }

    func configure(address: String, model: String, newKey: String) throws {
        let updated = try AIReviewConfiguration(address: address, model: model)
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepExistingKey = key.isEmpty && updated.endpoint == configuration?.endpoint
        if updated.endpoint.host == "api.openai.com",
           key.isEmpty, !keepExistingKey || Keychain.get(Self.secretAccount).isEmpty {
            throw AIReviewError.missingKey
        }

        let data = try JSONEncoder().encode(updated)
        if !keepExistingKey, !Keychain.set(key, for: Self.secretAccount) {
            throw AIReviewError.keychain
        }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
        configuration = updated
        errorMessage = nil
    }

    func generate(batch: AIReviewBatch, configuration confirmed: AIReviewConfiguration) async {
        guard !isGenerating, configuration == confirmed else { return }
        guard batch.sources.count >= 2 else {
            errorMessage = AIReviewError.insufficientNotes.errorDescription
            return
        }
        let key = Keychain.get(Self.secretAccount)
        if confirmed.endpoint.host == "api.openai.com", key.isEmpty {
            errorMessage = AIReviewError.missingKey.errorDescription
            return
        }

        let requestID = UUID()
        activeRequest = requestID
        errorMessage = nil
        defer { if activeRequest == requestID { activeRequest = nil } }

        do {
            let updated = try await AIReviewClient.generate(batch: batch, configuration: confirmed, apiKey: key)
            guard activeRequest == requestID else { return }
            do {
                try JSONEncoder().encode(updated).write(to: reportURL, options: .atomic)
            } catch {
                throw AIReviewError.localStorage
            }
            report = updated
        } catch is CancellationError {
            return
        } catch {
            guard activeRequest == requestID else { return }
            errorMessage = (error as? AIReviewError)?.errorDescription ?? AIReviewError.badResponse.errorDescription
        }
    }

    func clearReport() throws {
        activeRequest = nil
        if FileManager.default.fileExists(atPath: reportURL.path) {
            try FileManager.default.removeItem(at: reportURL)
        }
        report = nil
        errorMessage = nil
    }
}
