import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RunnerModel: ObservableObject {
    @Published var source = """
    import SwiftUI

    struct ContentView: View {
        @State private var count = 0
        @State private var name = "friend"
        @State private var enabled = true
        @State private var volume = 35.0

        var body: some View {
            VStack(spacing: 14) {
                Text("Tiny Native App").font(.title)
                Text("Hello, \\(name)!")
                Text("Taps: \\(count)")
                TextField("Your name", text: $name)
                Toggle("Notifications", isOn: $enabled)
                Text("Volume: \\(volume)")
                Slider(value: $volume, in: 0...100)
                Button("Add one") { count += 1 }
                Button("Reset") { count = 0 }
            }
            .padding()
        }
    }
    """
    @Published var program: ProgramNode?
    @Published var state: [String: RuntimeValue] = ["count": .number(0), "name": .string("friend"), "enabled": .bool(true), "volume": .number(35)]
    @Published var error: String?
    @Published var isShowingImporter = false
    @Published var isEditing = false
    private let interpreter = SwiftFileInterpreter()
    private let actions = ActionInterpreter()

    func run() {
        do {
            let parsed = try interpreter.parse(source)
            program = parsed
            state = parsed.initialState
            error = nil
            isEditing = false
        }
        catch { program = nil; self.error = error.localizedDescription }
    }

    func perform(_ tokens: [String]) {
        do { try actions.apply(tokens, to: &state); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func value(_ key: String, default fallback: RuntimeValue) -> RuntimeValue { state[key] ?? fallback }
    func set(_ value: RuntimeValue, for key: String) { state[key] = value }

    func importSource(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            source = try String(contentsOf: url, encoding: .utf8)
            isEditing = true
        } catch { self.error = "Could not open file: \(error.localizedDescription)" }
    }
}

@main
struct SwiftFileRunnerApp: App {
    var body: some Scene { WindowGroup { RunnerView() } }
}

struct RunnerView: View {
    @StateObject private var model = RunnerModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Label("Swift File Runner", systemImage: "swift")
                        .font(.headline)
                    Spacer()
                    Button { model.isShowingImporter = true } label: { Image(systemName: "folder") }
                        .accessibilityLabel("Import Swift file")
                    Button { model.isEditing.toggle() } label: { Image(systemName: model.isEditing ? "rectangle.on.rectangle" : "chevron.left.forwardslash.chevron.right") }
                        .accessibilityLabel(model.isEditing ? "Show preview" : "Edit source")
                    Button("Run", systemImage: "play.fill") { model.run() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red).padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.isEditing {
                    TextEditor(text: $model.source)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(.horizontal, 8)
                } else if let program = model.program {
                    ScrollView { NativeView(node: program, model: model).padding(24).frame(maxWidth: .infinity, alignment: .topLeading) }
                } else {
                    ContentUnavailableView("Run a Swift file", systemImage: "swift", description: Text("Import a .swift file or edit the sample, then tap Run."))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $model.isShowingImporter, allowedContentTypes: [UTType(filenameExtension: "swift") ?? .sourceCode], allowsMultipleSelection: false, onCompletion: model.importSource)
            .onAppear { model.run() }
        }
    }
}

private struct NativeView: View {
    let node: ProgramNode
    @ObservedObject var model: RunnerModel

    var body: some View { applyModifiers(to: makeBaseView()) }

    private func makeBaseView() -> AnyView {
        switch node.kind {
        case .app: return AnyView(childContent)
        case .vstack:
            return AnyView(VStack(alignment: .leading, spacing: node.spacing) { children })
        case .hstack:
            return AnyView(HStack(spacing: node.spacing) { children })
        case .zstack:
            return AnyView(ZStack { children })
        case .scrollView:
            return AnyView(ScrollView { children })
        case .list:
            return AnyView(List { children })
        case .navigationStack:
            return AnyView(NavigationStack { children })
        case .form:
            return AnyView(Form { children })
        case .conditional:
            return AnyView(branchContent)
        case .text:
            return AnyView(Text(interpolate(node.label)).font(.body))
        case .image:
            return AnyView(Image(systemName: node.label))
        case .button:
            return AnyView(Button(node.label) { model.perform(node.action) }.buttonStyle(.borderedProminent))
        case .textField:
            return AnyView(TextField(node.label, text: Binding(get: { stringValue(node.variable) }, set: { model.set(.string($0), for: node.variable) })).textFieldStyle(.roundedBorder))
        case .secureField:
            return AnyView(SecureField(node.label, text: Binding(get: { stringValue(node.variable) }, set: { model.set(.string($0), for: node.variable) })).textFieldStyle(.roundedBorder))
        case .toggle:
            return AnyView(Toggle(node.label, isOn: Binding(get: { boolValue(node.variable) }, set: { model.set(.bool($0), for: node.variable) })))
        case .slider:
            let control = Slider(value: Binding(get: { numberValue(node.variable) }, set: { model.set(.number($0), for: node.variable) }), in: node.range)
            if node.label.isEmpty { return AnyView(control) }
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                Text("\(node.label): \(numberValue(node.variable).formatted(.number.precision(.fractionLength(0))))")
                control
            })
        case .stepper:
            return AnyView(Stepper("\(node.label): \(numberValue(node.variable).formatted(.number.precision(.fractionLength(0))))", value: Binding(get: { numberValue(node.variable) }, set: { model.set(.number($0), for: node.variable) }), in: node.range))
        case .divider:
            return AnyView(Divider())
        case .spacer: return AnyView(Spacer(minLength: 8))
        }
    }

    private func applyModifiers(to original: AnyView) -> AnyView {
        var result = original
        for modifier in node.modifiers {
            switch modifier {
            case .padding(let amount): result = AnyView(result.padding(amount))
            case .font(let name): result = AnyView(result.font(font(name)))
            case .foreground(let name): result = AnyView(result.foregroundStyle(color(name)))
            case .buttonStyle(let name):
                if name == "bordered" { result = AnyView(result.buttonStyle(.bordered)) }
                else if name == "plain" { result = AnyView(result.buttonStyle(.plain)) }
                else { result = AnyView(result.buttonStyle(.borderedProminent)) }
            case .accessibilityLabel(let label): result = AnyView(result.accessibilityLabel(label))
            case .navigationTitle(let title): result = AnyView(result.navigationTitle(title))
            case .disabled(let value): result = AnyView(result.disabled(value))
            }
        }
        return result
    }

    private func font(_ name: String) -> Font? {
        switch name {
        case "largeTitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "caption": return .caption
        case "callout": return .callout
        default: return .body
        }
    }

    private func color(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "secondary": return .secondary
        default: return .primary
        }
    }

    @ViewBuilder private var childContent: some View { ForEach(node.children.indices, id: \.self) { index in NativeView(node: node.children[index], model: model) } }
    @ViewBuilder private var children: some View { ForEach(node.children.indices, id: \.self) { index in NativeView(node: node.children[index], model: model) } }
    @ViewBuilder private var branchContent: some View {
        let branch = boolValue(node.variable) == node.conditionExpected ? node.children : node.alternateChildren
        ForEach(branch.indices, id: \.self) { index in NativeView(node: branch[index], model: model) }
    }

    private func interpolate(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\\\(([_a-zA-Z][_a-zA-Z0-9]*)\)"#) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        var output = text
        for match in matches {
            let key = ns.substring(with: match.range(at: 1))
            let replacement = model.value(key, default: .string("")).display
            if let range = Range(match.range, in: output) { output.replaceSubrange(range, with: replacement) }
        }
        return output
    }
    private func stringValue(_ key: String) -> String { if case .string(let value) = model.value(key, default: .string("")) { return value }; return "" }
    private func numberValue(_ key: String) -> Double { if case .number(let value) = model.value(key, default: .number(0)) { return value }; return 0 }
    private func boolValue(_ key: String) -> Bool { if case .bool(let value) = model.value(key, default: .bool(false)) { return value }; return false }
}
