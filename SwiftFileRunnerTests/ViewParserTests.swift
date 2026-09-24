import XCTest
@testable import SwiftFileRunner

final class ViewParserTests: XCTestCase {
    func testEverySupportedContainerAndAlias() throws {
        let cases: [(String, ProgramNode.Kind)] = [
            ("App", .app), ("Group", .app),
            ("VStack", .vstack), ("LazyVStack", .vstack),
            ("HStack", .hstack), ("LazyHStack", .hstack),
            ("ZStack", .zstack), ("ScrollView", .scrollView),
            ("List", .list), ("NavigationStack", .navigationStack), ("Form", .form)
        ]

        for (name, expectedKind) in cases {
            let root = try SwiftFileInterpreter().parse("\(name) { Text(\"child\") }")
            XCTAssertEqual(root.kind, expectedKind, "\(name) should map to \(expectedKind)")
            XCTAssertEqual(root.children.map(\.kind), [.text], "\(name) should parse its content")
            XCTAssertEqual(root.children.first?.label, "child")
            XCTAssertEqual(root.spacing, 14, "\(name) should retain default spacing")
        }
    }

    func testContainerSpacingArgumentAndClamping() throws {
        let explicit = try SwiftFileInterpreter().parse("VStack(spacing: 6.5) { Text(\"x\") }")
        XCTAssertEqual(explicit.spacing, 6.5)

        let clamped = try SwiftFileInterpreter().parse("HStack(spacing: 100) { Text(\"x\") }")
        XCTAssertEqual(clamped.spacing, 80)

        let negative = try SwiftFileInterpreter().parse("ZStack(spacing: -2) { Text(\"x\") }")
        XCTAssertEqual(negative.spacing, 0)
    }

    func testNegativeNumericLiteralsArePreserved() throws {
        let root = try SwiftFileInterpreter().parse(#"App { Slider(value: $level, in: -2.5...3); Stepper("Offset", value: $offset, in: -4...4) }"#)

        XCTAssertEqual(root.children[0].range, -2.5...3)
        XCTAssertEqual(root.children[1].range, -4...4)
    }

    func testEverySupportedControlAndItsArguments() throws {
        let root = try SwiftFileInterpreter().parse(#"App { Text("Hello"); Image(systemName: "heart.fill"); Button("Tap") { count += 1 }; TextField("Name", text: $name); SecureField("Password", text: $password); Toggle("Enabled", isOn: $enabled); Slider("Level", value: $level, in: 2...9); Stepper("Age", value: $age, in: 1...120); Divider(); Spacer() }"#)
        let views = root.children

        XCTAssertEqual(views.map(\.kind), [.text, .image, .button, .textField, .secureField, .toggle, .slider, .stepper, .divider, .spacer])
        XCTAssertEqual(views[0].label, "Hello")
        XCTAssertEqual(views[1].label, "heart.fill")
        XCTAssertEqual(views[2].label, "Tap")
        XCTAssertEqual(views[2].action, ["count", "+=", "1"])
        XCTAssertEqual(views[3].label, "Name")
        XCTAssertEqual(views[3].variable, "name")
        XCTAssertEqual(views[4].label, "Password")
        XCTAssertEqual(views[4].variable, "password")
        XCTAssertEqual(views[5].label, "Enabled")
        XCTAssertEqual(views[5].variable, "enabled")
        XCTAssertEqual(views[6].label, "Level")
        XCTAssertEqual(views[6].variable, "level")
        XCTAssertEqual(views[6].range.lowerBound, 2)
        XCTAssertEqual(views[6].range.upperBound, 9)
        XCTAssertEqual(views[7].label, "Age")
        XCTAssertEqual(views[7].variable, "age")
        XCTAssertEqual(views[7].range.lowerBound, 1)
        XCTAssertEqual(views[7].range.upperBound, 120)
    }

    func testOptionalControlArgumentsAndRangeNormalization() throws {
        let root = try SwiftFileInterpreter().parse(#"App { Slider(value: $volume, in: 10...0); Stepper("Count", value: $count, in: 8...3); Divider(); Divider(); Spacer(); Spacer() }"#)

        XCTAssertEqual(root.children[0].label, "")
        XCTAssertEqual(root.children[0].range, 0...10)
        XCTAssertEqual(root.children[1].range, 3...8)
        XCTAssertEqual(root.children.filter { $0.kind == .divider }.count, 2)
        XCTAssertEqual(root.children.filter { $0.kind == .spacer }.count, 2)
    }

    func testSupportedModifiersAndDefaults() throws {
        let root = try SwiftFileInterpreter().parse(#"Text("Title").padding().font(.title).foregroundStyle(.red).buttonStyle(.bordered).accessibilityLabel("Heading").navigationTitle("Screen").disabled(true)"#)

        XCTAssertEqual(root.modifiers, [
            .padding(12), .font("title"), .foreground("red"), .buttonStyle("bordered"),
            .accessibilityLabel("Heading"), .navigationTitle("Screen"), .disabled(true)
        ])

        let bounded = try SwiftFileInterpreter().parse(#"Text("Body").padding(100)"#)
        XCTAssertEqual(bounded.modifiers, [.padding(80)])
        let lowerBounded = try SwiftFileInterpreter().parse(#"Text("Body").padding(-1)"#)
        XCTAssertEqual(lowerBounded.modifiers, [.padding(0)])
    }

    func testNestedContainersAndBothConditionalBranches() throws {
        let root = try SwiftFileInterpreter().parse(#"VStack { ScrollView { if enabled { HStack { Text("On"); Spacer() } } else { Form { Text("Off") } } } }"#)
        let conditional = try XCTUnwrap(root.children.first?.children.first)

        XCTAssertEqual(root.kind, .vstack)
        XCTAssertEqual(conditional.kind, .conditional)
        XCTAssertEqual(conditional.variable, "enabled")
        XCTAssertEqual(conditional.children.first?.kind, .hstack)
        XCTAssertEqual(conditional.children.first?.children.map(\.kind), [.text, .spacer])
        XCTAssertEqual(conditional.alternateChildren.first?.kind, .form)
        XCTAssertEqual(conditional.alternateChildren.first?.children.first?.label, "Off")
    }

    func testConditionalWithoutElseAndNestedConditionals() throws {
        let root = try SwiftFileInterpreter().parse(#"App { if outer { if inner { Text("nested") } } }"#)
        let outer = try XCTUnwrap(root.children.first)
        let inner = try XCTUnwrap(outer.children.first)

        XCTAssertEqual(outer.kind, .conditional)
        XCTAssertEqual(outer.variable, "outer")
        XCTAssertTrue(outer.alternateChildren.isEmpty)
        XCTAssertEqual(inner.kind, .conditional)
        XCTAssertEqual(inner.variable, "inner")
        XCTAssertEqual(inner.children.first?.label, "nested")
    }

    func testUnsupportedViewsAndModifiersFailClosed() {
        XCTAssertThrowsError(try SwiftFileInterpreter().parse("Map { Text(\"x\") }")) { error in
            XCTAssertEqual(error as? InterpreterError, .unsupported("Map"))
        }
        XCTAssertThrowsError(try SwiftFileInterpreter().parse(#"Text("x").onTapGesture()"#)) { error in
            XCTAssertEqual(error as? InterpreterError, .unsupported("modifier .onTapGesture"))
        }
    }

    func testMalformedSupportedViewArgumentsAreRejected() {
        let invalidSources = [
            #"Text(123)"#,
            #"Image("heart")"#,
            #"Button("Tap")"#,
            #"TextField("Name", text: name)"#,
            #"Toggle("Enabled", isOn: enabled)"#,
            #"Slider(value: level, in: 0...1)"#,
            #"Stepper("Count", value: $count)"#,
            #"VStack(alignment: .center) { Text("unsupported argument") }"#,
            #"VStack(spacing: "wide") { Text("bad spacing") }"#,
            #"Slider(value: $level, in: low...10)"#,
            #"Text("bad padding").padding("large")"#,
            #"Text("bad disabled").disabled(maybe)"#,
            "VStack { Text(\"missing close\")"
        ]

        for source in invalidSources {
            XCTAssertThrowsError(try SwiftFileInterpreter().parse(source), "Expected rejection for: \(source)")
        }
    }
}
