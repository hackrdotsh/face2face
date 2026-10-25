import Foundation
import Testing

@testable import Face2FaceCore

private let stateJSON = #"""
    {"complete":false,"fields":[
      {"key":"name","type":"text","label":"Name","required":true,"value":"Sam","constraints":{"maxLength":80}},
      {"key":"birthDate","type":"date","label":"Date of birth","required":true,"value":null,
       "constraints":{"earliestDate":"1900-01-01","latestDate":"2008-10-24"}},
      {"key":"gender","type":"singleChoice","label":"Gender","required":true,
       "value":{"optionId":"other","description":"Genderfluid"},
       "options":[{"id":"male","label":"Male","allowsDescription":false},
                  {"id":"other","label":"Other","allowsDescription":true}]},
      {"key":"interests","type":"multiChoice","label":"Interests","required":false,"value":["a"]}
    ]}
    """#

@Test func decodesEachFieldTypeAndKeepsUnknownTypes() throws {
    let state = try JSONDecoder().decode(OnboardingState.self, from: Data(stateJSON.utf8))
    #expect(state.complete == false)
    #expect(state.fields.map(\.type) == [.text, .date, .singleChoice, .unsupported("multiChoice")])
    #expect(state.fields[0].value == .text("Sam"))
    #expect(state.fields[0].constraints?.maxLength == 80)
    #expect(state.fields[1].value == nil)
    #expect(state.fields[1].constraints?.latestDate == "2008-10-24")
    #expect(state.fields[2].value == .choice(ChoiceValue(optionId: "other", description: "Genderfluid")))
    #expect(state.fields[2].options.map(\.id) == ["male", "other"])
    #expect(state.fields[3].value == nil)
}

@Test func sendsOnboardingValuesInTheServerShape() async throws {
    let transport = StubTransport([response(json: #"{"complete":true,"fields":[]}"#)])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    let state = try await client.updateOnboarding([
        "name": .text("Sam"), "birthDate": .date("1995-02-03"),
        "gender": .choice(ChoiceValue(optionId: "other", description: "Agender")),
    ])
    #expect(state.complete)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "PATCH")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
    let values = try #require(body?["values"] as? [String: Any])
    #expect(values["name"] as? String == "Sam")
    #expect(values["birthDate"] as? String == "1995-02-03")
    #expect((values["gender"] as? [String: String]) == ["optionId": "other", "description": "Agender"])
}

@Test func reportsFieldErrorsFromTheServer() async throws {
    let transport = StubTransport([
        response(400, json: #"{"error":"invalid_fields","fields":{"birthDate":"You must be 18 or older."}}"#)
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    await #expect(throws: APIError.invalidFields(["birthDate": "You must be 18 or older."])) {
        try await client.updateOnboarding(["birthDate": .date("2015-01-01")])
    }
}
