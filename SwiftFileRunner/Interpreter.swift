import Foundation
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public struct ProgramNode: Equatable {
    public enum Kind: Equatable { case app, vstack, hstack, zstack, scrollView, list, navigationStack, form, conditional, text, image, button, textField, secureField, toggle, slider, stepper, divider, spacer }
    public enum Modifier: Equatable {
        case padding(Double), font(String), foreground(String), buttonStyle(String)
        case accessibilityLabel(String), navigationTitle(String), disabled(Bool)
    }
    public var kind: Kind
    public var label: String = ""
    public var variable: String = ""
    public var action: [String] = []
    public var range: ClosedRange<Double> = 0...1
    public var children: [ProgramNode] = []
    public var alternateChildren: [ProgramNode] = []
    public var conditionExpected = true
    public var initialState: [String: RuntimeValue] = [:]
    public var modifiers: [Modifier] = []
    public var spacing: Double = 14

    public init(kind: Kind) { self.kind = kind }
}

public enum InterpreterError: Error, LocalizedError, Equatable {
    case unexpected(String)
    case unsupported(String)
    case expected(String)
    case limit(String)

    public var errorDescription: String? {
        switch self {
        case .unexpected(let value): return "Unexpected token: \(value)"
        case .unsupported(let value): return "Unsupported view or expression: \(value)"
        case .expected(let value): return "Expected \(value)"
        case .limit(let value): return "Input limit exceeded: \(value)"
        }
    }
}

/// Parses a deliberately small, non-executable SwiftUI-shaped language.
/// It never compiles or evaluates arbitrary Swift code.
public struct SwiftFileInterpreter {
    public init() {}

    public func parse(_ source: String) throws -> ProgramNode {
        guard source.utf8.count <= 512_000 else { throw InterpreterError.limit("source files must be 512 KB or smaller") }
        // Parse with the same SwiftSyntax parser used by Swift's tooling before
        // lowering the currently supported UI subset. This gives malformed
        // Swift real parser diagnostics and removes tokenizer guesswork from
        // the syntax-validation boundary. Evaluation remains interpreted and
        // allowlisted; no source is compiled or loaded as executable code.
        let syntaxTree = SwiftParser.Parser.parse(source: source)
        let syntaxDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntaxTree)
        if !syntaxDiagnostics.isEmpty {
            let converter = SourceLocationConverter(fileName: "Imported.swift", tree: syntaxTree)
            let messages = syntaxDiagnostics.map { diagnostic in
                let location = diagnostic.location(converter: converter)
                return "line \(location.line), column \(location.column): \(diagnostic.message)"
            }.joined(separator: "\n")
            throw InterpreterError.unexpected("Swift syntax error: \(messages)")
        }
        let selection = Self.selectSource(in: syntaxTree)
        let interpretedSource = selection.body ?? source
        let tokens = Lexer(interpretedSource).tokens()
        guard tokens.count <= 20_000 else { throw InterpreterError.limit("a file may contain at most 20,000 tokens") }
        var parser = Parser(tokens: tokens)
        let node: ProgramNode
        node = try parser.view()
        if !parser.isAtEnd { throw InterpreterError.unexpected(parser.peek) }
        var result = node
        result.initialState = selection.initialState
        return result
    }

    /// Selects a real `body` property and `@State` declarations from the
    /// parsed syntax tree. Source outside that view declaration is no longer
    /// searched for matching words, so comments and unrelated declarations
    /// cannot accidentally become the rendered UI.
    private static func selectSource(in tree: SourceFileSyntax) -> (body: String?, initialState: [String: RuntimeValue]) {
        var firstViewBody: (body: String, initialState: [String: RuntimeValue])?
        for item in tree.statements {
            guard case .decl(let declaration) = item.item,
                  let structure = declaration.as(StructDeclSyntax.self) else { continue }

            var body: String?
            var state: [String: RuntimeValue] = [:]
            let conformsToView = structure.inheritanceClause?.inheritedTypes.contains { inheritedType in
                inheritedType.type.trimmedDescription.split(separator: ".").last == "View"
            } ?? false
            for member in structure.memberBlock.members {
                guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
                let isState = variable.attributes.contains { element in
                    guard let attribute = element.as(AttributeSyntax.self) else { return false }
                    return attribute.attributeName.trimmedDescription == "State"
                }

                for binding in variable.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    let returnsView = binding.typeAnnotation?.type.trimmedDescription.contains("View") ?? false
                    if name == "body", (conformsToView || returnsView), let accessor = binding.accessorBlock {
                        let items: CodeBlockItemListSyntax
                        switch accessor.accessors {
                        case .getter(let getterItems): items = getterItems
                        case .accessors(let accessors):
                            guard let getter = accessors.first(where: { $0.accessorSpecifier.text == "get" }),
                                  let getterBody = getter.body else { continue }
                            items = getterBody.statements
                        }
                        let expression = items.map(\.trimmedDescription).filter { !$0.isEmpty }.joined(separator: "\n")
                        if !expression.isEmpty { body = expression }
                    }

                    guard isState, let initializer = binding.initializer else { continue }
                    let literalTokens = Lexer(initializer.value.trimmedDescription).tokens()
                    guard let literal = literalTokens.first else { continue }
                    if literal.first == "\"", literal.last == "\"" {
                        state[name] = .string(String(literal.dropFirst().dropLast()))
                    } else if literal == "true" || literal == "false" {
                        state[name] = .bool(literal == "true")
                    } else if let number = Double(literal) {
                        state[name] = .number(number)
                    }
                }
            }
            if let body {
                // Conventional source files often declare a PreviewView or a
                // reusable component before the app's ContentView. Prefer the
                // conventional root name while retaining first-View fallback
                // for files that use another root type name.
                if structure.name.text == "ContentView" { return (body, state) }
                if firstViewBody == nil { firstViewBody = (body, state) }
            }
        }
        if let firstViewBody { return (firstViewBody.body, firstViewBody.initialState) }
        return (nil, [:])
    }

    private struct Lexer {
        let chars: [Character]
        init(_ source: String) { chars = Array(source) }

        func tokens() -> [String] {
            var result: [String] = []
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "\n" { result.append("__linebreak"); i += 1; continue }
                if c.isWhitespace { i += 1; continue }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                    continue
                }
                if c == "\"" {
                    i += 1
                    var value = ""
                    while i < chars.count {
                        if chars[i] == "\\", i + 1 < chars.count {
                            value.append(chars[i]); value.append(chars[i + 1]); i += 2
                        } else if chars[i] == "\"" { i += 1; break }
                        else { value.append(chars[i]); i += 1 }
                    }
                    result.append("\"\(value)\"")
                    continue
                }
                if c == "-", i + 1 < chars.count, chars[i + 1].isNumber {
                    var value = String(c); i += 1
                    while i < chars.count, chars[i].isNumber { value.append(chars[i]); i += 1 }
                    if i + 1 < chars.count, chars[i] == ".", chars[i + 1].isNumber {
                        value.append(chars[i]); i += 1
                        while i < chars.count, chars[i].isNumber { value.append(chars[i]); i += 1 }
                    }
                    result.append(value); continue
                }
                if c.isNumber {
                    var value = String(c); i += 1
                    while i < chars.count, chars[i].isNumber { value.append(chars[i]); i += 1 }
                    if i + 1 < chars.count, chars[i] == ".", chars[i + 1].isNumber {
                        value.append(chars[i]); i += 1
                        while i < chars.count, chars[i].isNumber { value.append(chars[i]); i += 1 }
                    }
                    result.append(value); continue
                }
                if c.isLetter || c == "_" || c == "$" {
                    var value = String(c); i += 1
                    while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { value.append(chars[i]); i += 1 }
                    result.append(value); continue
                }
                if c == "+" || c == "-", i + 1 < chars.count, chars[i + 1] == "=" {
                    result.append(String([c, "="])); i += 2; continue
                }
                if c == ".", i + 2 < chars.count, chars[i + 1] == ".", chars[i + 2] == "." {
                    result.append("..."); i += 3; continue
                }
                result.append(String(c)); i += 1
            }
            return result
        }
    }

    private struct Parser {
        var tokens: [String]
        var index = 0
        var nestingDepth = 0
        var nextIndex: Int {
            var result = index
            while result < tokens.count && tokens[result] == "__linebreak" { result += 1 }
            return result
        }
        var isAtEnd: Bool { nextIndex >= tokens.count }
        var peek: String { isAtEnd ? "<end>" : tokens[nextIndex] }
        mutating func take() -> String { index = nextIndex; defer { index += 1 }; return peek }
        mutating func accept(_ value: String) -> Bool { guard peek == value else { return false }; _ = take(); return true }
        mutating func expect(_ value: String) throws { guard accept(value) else { throw InterpreterError.expected("'\(value)', found '\(peek)'") } }

        mutating func view() throws -> ProgramNode {
            guard nestingDepth < 64 else { throw InterpreterError.limit("view nesting is limited to 64 levels") }
            nestingDepth += 1
            defer { nestingDepth -= 1 }
            var node = try baseView()
            while accept(".") {
                let modifier = take()
                try expect("(")
                switch modifier {
                case "padding":
                    if accept(")") { node.modifiers.append(.padding(12)) }
                    else {
                        guard let amount = Double(take()) else { throw InterpreterError.expected("a numeric padding amount") }
                        try expect(")"); node.modifiers.append(.padding(max(0, min(amount, 80))))
                    }
                case "font", "foregroundStyle", "buttonStyle":
                    _ = accept(".")
                    let value = take(); try expect(")")
                    if modifier == "font" { node.modifiers.append(.font(value)) }
                    else if modifier == "foregroundStyle" { node.modifiers.append(.foreground(value)) }
                    else { node.modifiers.append(.buttonStyle(value)) }
                case "accessibilityLabel", "navigationTitle":
                    let value = try stringArgument(); try expect(")")
                    node.modifiers.append(modifier == "accessibilityLabel" ? .accessibilityLabel(value) : .navigationTitle(value))
                case "disabled":
                    let literal = take()
                    guard literal == "true" || literal == "false" else { throw InterpreterError.expected("true or false for disabled") }
                    try expect(")"); node.modifiers.append(.disabled(literal == "true"))
                default: throw InterpreterError.unsupported("modifier .\(modifier)")
                }
            }
            return node
        }

        mutating func baseView() throws -> ProgramNode {
            let name = take()
            switch name {
            case "App", "Group": return try container(.app)
            case "VStack", "LazyVStack": return try container(.vstack)
            case "HStack", "LazyHStack": return try container(.hstack)
            case "ZStack": return try container(.zstack)
            case "ScrollView": return try container(.scrollView)
            case "List": return try container(.list)
            case "NavigationStack": return try container(.navigationStack)
            case "Form": return try container(.form)
            case "if": return try conditional()
            case "Text":
                try expect("("); let label = try stringArgument(); try expect(")")
                var node = ProgramNode(kind: .text); node.label = label; return node
            case "Image":
                try expect("("); try expect("systemName"); try expect(":")
                let symbol = try stringArgument(); try expect(")")
                var node = ProgramNode(kind: .image); node.label = symbol; return node
            case "Button":
                try expect("("); let label = try stringArgument(); try expect(")"); try expect("{")
                var node = ProgramNode(kind: .button); node.label = label; node.action = try actionBlock(); return node
            case "TextField":
                try expect("("); let label = try stringArgument(); try expect(","); try expect("text"); try expect(":")
                let variable = try binding(); try expect(")")
                var node = ProgramNode(kind: .textField); node.label = label; node.variable = variable; return node
            case "SecureField":
                try expect("("); let label = try stringArgument(); try expect(","); try expect("text"); try expect(":")
                let variable = try binding(); try expect(")")
                var node = ProgramNode(kind: .secureField); node.label = label; node.variable = variable; return node
            case "Toggle":
                try expect("("); let label = try stringArgument(); try expect(","); try expect("isOn"); try expect(":")
                let variable = try binding(); try expect(")")
                var node = ProgramNode(kind: .toggle); node.label = label; node.variable = variable; return node
            case "Slider":
                try expect("(")
                let label: String
                if peek.first == "\"" { label = try stringArgument(); try expect(",") } else { label = "" }
                try expect("value"); try expect(":")
                let variable = try binding(); try expect(","); try expect("in"); try expect(":")
                guard let low = Double(take()) else { throw InterpreterError.expected("a numeric lower range bound") }
                try expect("...")
                guard let high = Double(take()) else { throw InterpreterError.expected("a numeric upper range bound") }
                try expect(")")
                var node = ProgramNode(kind: .slider); node.label = label; node.variable = variable; node.range = min(low, high)...max(low, high); return node
            case "Stepper":
                try expect("("); let label = try stringArgument(); try expect(","); try expect("value"); try expect(":")
                let variable = try binding(); try expect(","); try expect("in"); try expect(":")
                guard let low = Double(take()) else { throw InterpreterError.expected("a numeric lower range bound") }
                try expect("...")
                guard let high = Double(take()) else { throw InterpreterError.expected("a numeric upper range bound") }
                try expect(")")
                var node = ProgramNode(kind: .stepper); node.label = label; node.variable = variable; node.range = min(low, high)...max(low, high); return node
            case "Divider":
                if accept("(") { try expect(")") }
                return ProgramNode(kind: .divider)
            case "Spacer":
                if accept("(") { try expect(")") }
                return ProgramNode(kind: .spacer)
            default: throw InterpreterError.unsupported(name)
            }
        }

        mutating func container(_ kind: ProgramNode.Kind) throws -> ProgramNode {
            var node = ProgramNode(kind: kind)
            if accept("(") {
                while !accept(")") {
                    if isAtEnd { throw InterpreterError.expected("')'") }
                    if accept("spacing") {
                        try expect(":")
                        guard let value = Double(take()) else { throw InterpreterError.expected("a numeric spacing value") }
                        node.spacing = max(0, min(value, 80))
                    } else { throw InterpreterError.unsupported("container argument \(peek)") }
                    _ = accept(",")
                }
            }
            try expect("{")
            while !accept("}") {
                if isAtEnd { throw InterpreterError.expected("'}'") }
                if accept(";") { continue }
                node.children.append(try view())
                _ = accept(";")
            }
            return node
        }

        mutating func conditional() throws -> ProgramNode {
            let variable = take()
            guard variable.first?.isLetter == true || variable.first == "_" else {
                throw InterpreterError.expected("a Boolean state variable after if")
            }
            var node = ProgramNode(kind: .conditional)
            node.variable = variable
            try expect("{")
            while !accept("}") {
                if isAtEnd { throw InterpreterError.expected("'}' after if branch") }
                if accept(";") { continue }
                node.children.append(try view()); _ = accept(";")
            }
            if accept("else") {
                try expect("{")
                while !accept("}") {
                    if isAtEnd { throw InterpreterError.expected("'}' after else branch") }
                    if accept(";") { continue }
                    node.alternateChildren.append(try view()); _ = accept(";")
                }
            }
            return node
        }

        mutating func stringArgument() throws -> String {
            let token = take()
            guard token.first == "\"", token.last == "\"" else { throw InterpreterError.expected("a quoted string") }
            return String(token.dropFirst().dropLast())
        }

        mutating func binding() throws -> String {
            let value = take()
            guard value.first == "$", value.count > 1 else { throw InterpreterError.expected("a state binding such as $name") }
            return String(value.dropFirst())
        }

        mutating func actionBlock() throws -> [String] {
            var body: [String] = []; var depth = 0
            while !isAtEnd {
                if index < tokens.count, tokens[index] == "__linebreak" {
                    if !body.isEmpty, body.last != ";", body.last != "{" { body.append(";") }
                    index += 1
                    continue
                }
                if peek == "}" { if depth == 0 { _ = take(); return body }; depth -= 1 }
                let token = take()
                if token == "{" { depth += 1 }
                body.append(token)
            }
            throw InterpreterError.expected("'}' after button action")
        }
    }
}

public enum RuntimeValue: Equatable {
    case string(String), number(Double), bool(Bool)
    public var display: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        case .bool(let value): return value ? "true" : "false"
        }
    }
}

public struct ActionInterpreter {
    public init() {}
    public func apply(_ tokens: [String], to state: inout [String: RuntimeValue]) throws {
        var i = 0
        while i < tokens.count {
            if tokens[i] == ";" { i += 1; continue }
            if i + 4 < tokens.count, tokens[i + 1] == ".", tokens[i + 2] == "toggle", tokens[i + 3] == "(", tokens[i + 4] == ")" {
                let name = tokens[i]
                guard case .some(.bool(let value)) = state[name] else { throw InterpreterError.unsupported("\(name).toggle() requires a Boolean state value") }
                state[name] = .bool(!value); i += 5; continue
            }
            guard i + 2 < tokens.count else { throw InterpreterError.unexpected(tokens[i]) }
            let name = tokens[i]; let op = tokens[i + 1]; let raw = tokens[i + 2]
            guard name.first?.isLetter == true || name.first == "_" else { throw InterpreterError.unsupported(name) }
            let old = state[name] ?? .number(0)
            if op == "+=" || op == "-=" {
                if case .number(let value) = old, let amount = Double(raw) {
                    state[name] = .number(value + (op == "+=" ? amount : -amount))
                } else if op == "+=", case .string(let value) = old, raw.first == "\"", raw.last == "\"" {
                    state[name] = .string(value + String(raw.dropFirst().dropLast()))
                } else { throw InterpreterError.unsupported("\(name) \(op) \(raw)") }
            } else if op == "=" {
                if raw.first == "\"", raw.last == "\"" { state[name] = .string(String(raw.dropFirst().dropLast())) }
                else if raw == "true" || raw == "false" { state[name] = .bool(raw == "true") }
                else if let number = Double(raw) { state[name] = .number(number) }
                else if raw == "!", i + 3 < tokens.count, case .some(.bool(let value)) = state[tokens[i + 3]] {
                    state[name] = .bool(!value); i += 1
                }
                else if i + 4 < tokens.count, tokens[i + 3] == "+", case .some(.number(let value)) = state[raw], let amount = Double(tokens[i + 4]) {
                    state[name] = .number(value + amount); i += 2
                }
                else { throw InterpreterError.unsupported("assignment to \(name)") }
            } else { throw InterpreterError.unsupported("action operator \(op)") }
            i += 3
            if i < tokens.count, tokens[i] != ";" { throw InterpreterError.unsupported("multiple action statements need ';'") }
        }
    }
}
