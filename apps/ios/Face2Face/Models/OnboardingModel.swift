import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    var form: OnboardingForm?
    private(set) var fieldErrors: [String: String] = [:]
    let activity = Activity()

    private let session: SessionModel

    init(session: SessionModel) {
        self.session = session
    }

    func load() async {
        await activity.run {
            self.form = OnboardingForm(state: try await self.session.client().onboarding())
        }
    }

    func submit() async {
        guard let form else { return }
        fieldErrors = [:]
        await activity.run {
            do {
                let state = try await self.session.client().updateOnboarding(form.values())
                guard state.complete else {
                    self.form = OnboardingForm(state: state)
                    return
                }
                try await self.session.refreshAccount()
            } catch APIError.invalidFields(let errors) {
                self.fieldErrors = errors
                throw APIError.invalidFields(errors)
            }
        }
    }
}
