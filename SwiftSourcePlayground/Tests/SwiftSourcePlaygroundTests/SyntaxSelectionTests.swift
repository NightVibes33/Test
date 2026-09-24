import XCTest
@testable import SwiftSourcePlayground

final class SyntaxSelectionTests: XCTestCase {
    func testValidSwiftSyntaxCanIncludeImportsAndUnrelatedDeclarations() throws {
        let source = #"""
        import SwiftUI

        private func helper() -> String { "not a view" }

        struct ContentView: View {
            var body: some View { Text("Selected") }
        }
        """#

        let root = try SwiftFileInterpreter().parse(source)
        XCTAssertEqual(root.kind, .text)
        XCTAssertEqual(root.label, "Selected")
    }

    func testInvalidSwiftSyntaxReportsParserDiagnosticAndLocation() {
        let source = #"""
        import SwiftUI
        struct ContentView: View {
            var body: some View { VStack( }
        }
        """#

        XCTAssertThrowsError(try SwiftFileInterpreter().parse(source)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Swift syntax error"))
            XCTAssertTrue(error.localizedDescription.contains("line 3"))
        }
    }

    func testSelectsContentViewBodyInsteadOfEarlierPreviewView() throws {
        let source = #"""
        import SwiftUI

        struct PreviewView: View {
            var body: some View { Text("Preview only") }
        }

        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Actual app")
                }
            }
        }
        """#

        let root = try SwiftFileInterpreter().parse(source)
        XCTAssertEqual(root.kind, .vstack)
        XCTAssertEqual(root.children.map(\.label), ["Actual app"])
    }

    func testNestedViewDeclarationAndCommentsDoNotReplaceOuterBody() throws {
        let source = #"""
        import SwiftUI
        struct ContentView: View {
            // var body: some View { Text("Comment") }
            struct NestedPreview: View {
                var body: some View { Text("Nested") }
            }
            var body: some View { Text("Outer") }
        }
        """#

        let root = try SwiftFileInterpreter().parse(source)
        XCTAssertEqual(root.kind, .text)
        XCTAssertEqual(root.label, "Outer")
    }

    func testStateLiteralsComeOnlyFromSelectedViewAndDirectMembers() throws {
        let source = #"""
        import SwiftUI
        struct Helpers {
            @State var unrelated = 41
        }

        struct ContentView: View {
            @State private var count = 4
            @State private var enabled = true
            @State private var title = "Hello"
            @State private var offset = -12.5
            @State private var derived = makeValue()

            struct NestedHelper {
                @State var nested = 99
            }

            var body: some View { Text("State selection") }
        }
        """#

        let root = try SwiftFileInterpreter().parse(source)
        XCTAssertEqual(root.initialState, [
            "count": .number(4),
            "enabled": .bool(true),
            "title": .string("Hello"),
            "offset": .number(-12.5)
        ])
    }

    func testDirectViewExpressionUsesFallbackWithoutInventingState() throws {
        let root = try SwiftFileInterpreter().parse(#"App { VStack { Text("Direct") } }"#)

        XCTAssertEqual(root.kind, .app)
        XCTAssertEqual(root.children.first?.kind, .vstack)
        XCTAssertEqual(root.children.first?.children.first?.label, "Direct")
        XCTAssertTrue(root.initialState.isEmpty)
    }
}
