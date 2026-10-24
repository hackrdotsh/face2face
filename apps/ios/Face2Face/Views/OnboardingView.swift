import Face2FaceCore
import SwiftUI

struct OnboardingView: View {
    @State private var model: OnboardingModel

    init(session: SessionModel) {
        _model = State(initialValue: OnboardingModel(session: session))
    }

    var body: some View {
        Form {
            if let form = Binding($model.form) {
                if form.wrappedValue.needsAppUpdate {
                    Section { Text("Update face2face to finish setting up your profile.") }
                }
                ForEach(form.wrappedValue.fields) { field in
                    Section {
                        OnboardingFieldView(field: field, form: form, error: model.fieldErrors[field.key])
                    }
                }
                Section {
                    Button("Continue") { Task { await model.submit() } }
                }
            }
        }
        .disabled(model.activity.isBusy)
        .activityAlert(model.activity)
        .task { await model.load() }
    }
}
