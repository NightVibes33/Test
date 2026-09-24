import XCTest
@testable import SwiftFileRunner

final class InterpreterTests: XCTestCase {
    func testParsesInteractiveNativeViewTree() throws {
        let source = #"App { VStack { Text("Hi"); Button("Tap") { count += 1 }; TextField("Name", text: $name); Toggle("On", isOn: $enabled); Slider("Level", value: $level, in: 0...10) } }"#
        let root = try SwiftFileInterpreter().parse(source)
        XCTAssertEqual(root.kind, .app)
        XCTAssertEqual(root.children.first?.children.map(\.kind), [.text, .button, .textField, .toggle, .slider])
    }

    func testButtonActionUpdatesState() throws {
        var state: [String: RuntimeValue] = ["count": .number(3), "enabled": .bool(true)]
        let source = #"""
        App { Button("Tap") {
            count += 2
            enabled.toggle()
        } }
        """#
        let root = try SwiftFileInterpreter().parse(source)
        try ActionInterpreter().apply(root.children[0].action, to: &state)
        XCTAssertEqual(state["count"], .number(5))
        XCTAssertEqual(state["enabled"], .bool(false))
        try ActionInterpreter().apply(["name", "=", "\"Sam\""], to: &state)
        try ActionInterpreter().apply(["name", "+=", "\"!\""], to: &state)
        XCTAssertEqual(state["name"], .string("Sam!"))
    }

    func testParsesNormalSwiftUIViewAndStateDeclarations() throws {
        let source = #"""
        import SwiftUI
        struct CounterView: View {
            @State private var count = 7
            @State private var enabled = true
            var body: some View {
                VStack(spacing: 10) {
                    Text("Count: \(count)").font(.title)
                    Button("Add") { count += 1 }
                }
                .padding()
            }
        }
        """#
        let root = try SwiftFileInterpreter().parse(source)
        XCTAssertEqual(root.kind, .vstack)
        XCTAssertEqual(root.initialState["count"], .number(7))
        XCTAssertEqual(root.initialState["enabled"], .bool(true))
        XCTAssertEqual(root.spacing, 10)
        XCTAssertEqual(root.modifiers, [.padding(12)])
        XCTAssertEqual(root.children.first?.modifiers, [.font("title")])
    }

    func testFindsViewBodyAndStateFromSyntaxNodesOnly() throws {
        let source = #"""
        import SwiftUI
        // var body: some View { Text("Not the app") }
        struct Helpers {
            var body: String { "also not the app" }
            var count = 100
        }
        struct ContentView: View {
            @State private var count = 4
            var body: some View {
                VStack {
                    Text("Count")
                    Button("Add") { count += 1 }
                }
            }
        }
        """#

        let root = try SwiftFileInterpreter().parse(source)
        XCTAssertEqual(root.kind, .vstack)
        XCTAssertEqual(root.children.map(\.kind), [.text, .button])
        XCTAssertEqual(root.initialState, ["count": .number(4)])
    }

    func testRejectsArbitrarySwift() {
        XCTAssertThrowsError(try SwiftFileInterpreter().parse("import UIKit"))
    }

    func testUsesSwiftParserToRejectMalformedSyntax() {
        XCTAssertThrowsError(try SwiftFileInterpreter().parse("App { VStack( }")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Swift syntax error"))
        }
    }

    func testParsesMoreNativeViews() throws {
        let root = try SwiftFileInterpreter().parse(#"App { ScrollView { ZStack { Image(systemName: "heart.fill"); SecureField("Password", text: $password); Stepper("Age", value: $age, in: 0...120); Divider(); if enabled { Text("On") } else { Text("Off") } } } }"#)
        XCTAssertEqual(root.children.first?.kind, .scrollView)
        XCTAssertEqual(root.children.first?.children.first?.children.map(\.kind), [.image, .secureField, .stepper, .divider, .conditional])
        XCTAssertEqual(root.children.first?.children.first?.children.last?.alternateChildren.first?.label, "Off")
    }
}
