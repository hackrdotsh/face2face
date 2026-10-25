import Face2FaceCore
import Foundation
import Observation

/// Walks through the unanswered onboarding fields one at a time, saving each before moving on.
@MainActor
@Observable
final class OnboardingModel {
    var form: OnboardingForm?
    private(set) var step = 0
    /// True after the last move went forward, so steps can slide in from the matching side.
    private(set) var movedForward = true
    private(set) var fieldErrors: [String: String] = [:]
    let activity = Activity()

    private let session: SessionModel

    init(session: SessionModel) {
        self.session = session
    }

    var currentField: OnboardingField? {
        guard let fields = form?.fields, fields.indices.contains(step) else { return nil }
        return fields[step]
    }

    var stepCount: Int { form?.fields.count ?? 0 }
    var isLastStep: Bool { step == stepCount - 1 }

    /// A required field has to have input before the person can move past it.
    var canContinue: Bool {
        guard let form, let field = currentField else { return false }
        return !field.required || form.values()[field.key] != nil
    }

    func load() async {
        await activity.run {
            self.form = OnboardingForm(state: try await self.session.client().onboarding())
            self.step = 0
        }
    }

    /// Saves the current step. Finishes onboarding after the last one. Returns true when the next step should show.
    func saveCurrentStep() async -> Bool {
        guard let form, let field = currentField else { return false }
        fieldErrors[field.key] = nil
        var showNext = false
        await activity.run {
            if let value = form.values()[field.key] {
                do {
                    _ = try await self.session.client().updateOnboarding([field.key: value])
                } catch APIError.invalidFields(let errors) {
                    self.fieldErrors = errors
                    return
                }
            }
            if self.isLastStep {
                try await self.finish()
            } else {
                showNext = true
            }
        }
        return showNext
    }

    func forward() {
        guard step < stepCount - 1 else { return }
        movedForward = true
        step += 1
    }

    func back() {
        guard step > 0 else { return }
        movedForward = false
        step -= 1
    }

    func signOut() async {
        await session.signOut()
    }

    private func finish() async throws {
        let state = try await session.client().onboarding()
        guard state.complete else {
            form = OnboardingForm(state: state)
            step = 0
            return
        }
        try await session.refreshAccount()
    }
}
