import XCTest
@testable import SwiftFileRunner

final class InterpreterLimitsTests: XCTestCase {
    private let interpreter = SwiftFileInterpreter()

    func testAcceptsSourceAt512000ByteLimit() throws {
        let view = #"Text("ok")"#
        let source = String(repeating: " ", count: 512_000 - view.utf8.count) + view

        XCTAssertEqual(source.utf8.count, 512_000)
        XCTAssertEqual(try interpreter.parse(source).label, "ok")
    }

    func testRejectsSourceAbove512000ByteLimit() {
        let source = String(repeating: " ", count: 512_001)

        XCTAssertThrowsError(try interpreter.parse(source)) { error in
            XCTAssertEqual(error as? InterpreterError, .limit("source files must be 512 KB or smaller"))
        }
    }

    func testAcceptsExactly20000Tokens() throws {
        // App { contributes two tokens, each Text contributes four, each
        // separator contributes one, and the final brace contributes one.
        // 3,999 Text views therefore produce 19,997 tokens; three newlines
        // (which the custom lexer counts) reach the exact 20,000-token limit.
        let views = Array(repeating: #"Text("x")"#, count: 3_999).joined(separator: ";")
        let source = "App {\(views)\n\n\n}"

        let root = try interpreter.parse(source)
        XCTAssertEqual(root.children.count, 3_999)
    }

    func testRejectsMoreThan20000Tokens() {
        let views = Array(repeating: #"Text("x")"#, count: 4_000).joined(separator: ";")
        let source = "App {\(views)}"

        XCTAssertThrowsError(try interpreter.parse(source)) { error in
            XCTAssertEqual(error as? InterpreterError, .limit("a file may contain at most 20,000 tokens"))
        }
    }

    func testAccepts64NestedViews() throws {
        let source = String(repeating: "VStack {", count: 63)
            + #"Text("deep")"#
            + String(repeating: "}", count: 63)

        var node = try interpreter.parse(source)
        var depth = 1
        while let child = node.children.first {
            node = child
            depth += 1
        }
        XCTAssertEqual(depth, 64)
    }

    func testRejects65NestedViews() {
        let source = String(repeating: "VStack {", count: 64)
            + #"Text("too deep")"#
            + String(repeating: "}", count: 64)

        XCTAssertThrowsError(try interpreter.parse(source)) { error in
            XCTAssertEqual(error as? InterpreterError, .limit("view nesting is limited to 64 levels"))
        }
    }

    func testRejectsUnsupportedViewAndModifier() {
        assertUnsupported("ForEach(items) { Text(\"item\") }")
        assertUnsupported(#"Text("Hello").onTapGesture(perform: {})"#)
    }

    func testRejectsMalformedClosingDelimitersWithSyntaxDiagnostic() {
        for source in [
            "App { VStack { Text(\"missing close\") }",
            "App { Text(\"extra close\") }}"
        ] {
            XCTAssertThrowsError(try interpreter.parse(source)) { error in
                guard case .some(.unexpected(let message)) = error as? InterpreterError else {
                    return XCTFail("Expected a Swift syntax diagnostic, got: \(error)")
                }
                XCTAssertTrue(message.contains("Swift syntax error"), message)
            }
        }
    }

    private func assertUnsupported(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try interpreter.parse(source), file: file, line: line) { error in
            guard case .some(.unsupported) = error as? InterpreterError else {
                return XCTFail("Expected unsupported syntax, got: \(error)", file: file, line: line)
            }
        }
    }
}
