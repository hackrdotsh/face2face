import Foundation
import Testing

@testable import Face2FaceCore

private func state(_ json: String) throws -> OnboardingState {
    try JSONDecoder().decode(OnboardingState.self, from: Data(json.utf8))
}

private let newAccount = #"""
    {"complete":false,"fields":[
      {"key":"name","type":"text","label":"Name","required":true,"value":null},
      {"key":"birthDate","type":"date","label":"Date of birth","required":true,"value":null,
       "constraints":{"earliestDate":"1900-01-01","latestDate":"2008-10-24"}},
      {"key":"gender","type":"singleChoice","label":"Gender","required":true,"value":null,
       "options":[{"id":"male","label":"Male","allowsDescription":false},
                  {"id":"other","label":"Other","allowsDescription":true}]}
    ]}
    """#

private var tokyo: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}

@Test func buildsValuesOnlyForFieldsWithInput() throws {
    var form = OnboardingForm(state: try state(newAccount), calendar: tokyo)
    form.drafts["name"]?.text = "  Sam  "
    form.drafts["gender"]?.optionId = "male"
    form.drafts["gender"]?.description = "dropped for options without a description"
    #expect(form.values() == ["name": .text("Sam"), "gender": .choice(ChoiceValue(optionId: "male"))])
}

@Test func keepsTheDescriptionForOptionsThatAllowIt() throws {
    var form = OnboardingForm(state: try state(newAccount))
    form.drafts["gender"]?.optionId = "other"
    form.drafts["gender"]?.description = " Agender "
    #expect(form.values()["gender"] == .choice(ChoiceValue(optionId: "other", description: "Agender")))
    #expect(form.selectedOption(for: form.fields[2])?.allowsDescription == true)
}

@Test func formatsDatesInThePickerCalendar() throws {
    var form = OnboardingForm(state: try state(newAccount), calendar: tokyo)
    let picked = try #require(tokyo.date(from: DateComponents(year: 1995, month: 2, day: 3, hour: 1)))
    form.drafts["birthDate"]?.date = picked
    #expect(form.values()["birthDate"] == .date("1995-02-03"))
    let range = try #require(form.dateRange(for: form.fields[1]))
    #expect(
        tokyo.dateComponents([.year, .month, .day], from: range.upperBound)
            == DateComponents(year: 2008, month: 10, day: 24))
}

@Test func showsOnlyUnansweredFieldsAndFlagsUnsupportedRequiredOnes() throws {
    let returning = try state(
        #"""
        {"complete":false,"fields":[
          {"key":"name","type":"text","label":"Name","required":true,"value":"Sam"},
          {"key":"pronouns","type":"text","label":"Pronouns","required":true,"value":null},
          {"key":"voice","type":"audio","label":"Voice note","required":true,"value":null}
        ]}
        """#)
    let form = OnboardingForm(state: returning)
    #expect(form.fields.map(\.key) == ["pronouns"])
    #expect(form.needsAppUpdate)
}
