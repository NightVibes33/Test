import XCTest
@testable import SwiftSourcePlayground

final class ActionStateTests: XCTestCase {
    private let actions = ActionInterpreter()

    func testNumericAssignmentAndCompoundMutations() throws {
        var state: [String: RuntimeValue] = ["count": .number(4), "level": .number(1.25)]

        try actions.apply(["count", "+=", "3"], to: &state)
        try actions.apply(["level", "-=", "0.5"], to: &state)
        try actions.apply(["count", "=", "-2.5"], to: &state)

        XCTAssertEqual(state["count"], .number(-2.5))
        XCTAssertEqual(state["level"], .number(0.75))
    }

    func testMissingNumericVariableStartsAtZeroAndPreservesOtherState() throws {
        var state: [String: RuntimeValue] = ["name": .string("Ada")]

        try actions.apply(["visits", "+=", "1"], to: &state)

        XCTAssertEqual(state["visits"], .number(1))
        XCTAssertEqual(state["name"], .string("Ada"))
    }

    func testStringAssignmentAndAppend() throws {
        var state: [String: RuntimeValue] = ["name": .string("Sam")]

        try actions.apply(["name", "=", "\"Taylor\""], to: &state)
        try actions.apply(["name", "+=", "\"!\""], to: &state)

        XCTAssertEqual(state["name"], .string("Taylor!"))
    }

    func testBooleanAssignmentNegationAndToggle() throws {
        var state: [String: RuntimeValue] = ["enabled": .bool(false)]

        try actions.apply(["enabled", "=", "true"], to: &state)
        try actions.apply(["mirror", "=", "!", "enabled"], to: &state)
        try actions.apply(["enabled", ".", "toggle", "(", ")"], to: &state)

        XCTAssertEqual(state["enabled"], .bool(false))
        XCTAssertEqual(state["mirror"], .bool(false))
    }

    func testEmptyAndSemicolonOnlyActionLeavesStateUnchanged() throws {
        var state: [String: RuntimeValue] = ["count": .number(9)]

        try actions.apply([], to: &state)
        try actions.apply([";", ";"], to: &state)

        XCTAssertEqual(state, ["count": .number(9)])
    }

    func testRejectsUnsupportedAndMalformedActions() {
        let cases: [([String], String)] = [
            (["count", "*", "2"], "action operator"),
            (["count", "=", "other"], "assignment to count"),
            (["count", "+=", "\"two\""], "count +="),
            (["name", "-=", "1"], "name -="),
            (["enabled", ".", "toggle", "(", ")"], "toggle() requires a Boolean"),
            (["missing", ".", "toggle", "(", ")"], "toggle() requires a Boolean"),
            (["count"], "Unexpected token")
        ]

        for (tokens, expectedMessage) in cases {
            var state: [String: RuntimeValue] = ["count": .number(2), "name": .string("A")]
            XCTAssertThrowsError(try actions.apply(tokens, to: &state), "Expected rejection for \(tokens)") { error in
                XCTAssertTrue(error.localizedDescription.contains(expectedMessage), "Unexpected error for \(tokens): \(error)")
            }
        }
    }

    func testRejectsInvalidStateIdentifier() {
        var state: [String: RuntimeValue] = [:]

        XCTAssertThrowsError(try actions.apply(["1count", "=", "1"], to: &state)) { error in
            XCTAssertEqual(error as? InterpreterError, .unsupported("1count"))
        }
        XCTAssertTrue(state.isEmpty)
    }

    func testButtonActionsAreTokenizedAcrossStatementsAndLines() throws {
        let source = #"""
        App {
            Button("Update") {
                count += 2
                enabled.toggle()
                name = "Done"
            }
        }
        """#
        let root = try SwiftFileInterpreter().parse(source)
        let button = try XCTUnwrap(root.children.first)
        XCTAssertEqual(button.kind, .button)
        XCTAssertTrue(button.action.contains(";"))

        var state: [String: RuntimeValue] = [
            "count": .number(3),
            "enabled": .bool(true),
            "name": .string("Before")
        ]
        try actions.apply(button.action, to: &state)

        XCTAssertEqual(state["count"], .number(5))
        XCTAssertEqual(state["enabled"], .bool(false))
        XCTAssertEqual(state["name"], .string("Done"))
    }

    func testMultipleParsedButtonsMutateTheSameState() throws {
        let root = try SwiftFileInterpreter().parse(#"App { VStack { Button("Add") { count += 1 }; Button("Reset") { count = 0 } } }"#)
        let buttons = try XCTUnwrap(root.children.first).children
        XCTAssertEqual(buttons.map(\.kind), [.button, .button])

        var state: [String: RuntimeValue] = ["count": .number(4)]
        try actions.apply(buttons[0].action, to: &state)
        XCTAssertEqual(state["count"], .number(5))
        try actions.apply(buttons[1].action, to: &state)
        XCTAssertEqual(state["count"], .number(0))
    }

    func testParsedNegativeButtonAssignment() throws {
        let root = try SwiftFileInterpreter().parse(#"App { Button("Set negative") { count = -2.5 } }"#)
        let button = try XCTUnwrap(root.children.first)
        var state: [String: RuntimeValue] = [:]

        try actions.apply(button.action, to: &state)

        XCTAssertEqual(state["count"], .number(-2.5))
    }

    func testRuntimeValueDisplayFormatting() {
        XCTAssertEqual(RuntimeValue.number(3).display, "3")
        XCTAssertEqual(RuntimeValue.number(3.25).display, "3.2")
        XCTAssertEqual(RuntimeValue.string("hello").display, "hello")
        XCTAssertEqual(RuntimeValue.bool(true).display, "true")
    }
}
