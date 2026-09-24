# Swift File Runner

An iOS app that imports a supported `.swift` file and renders its view description as interactive, native SwiftUI controls. Open `SwiftFileRunner.xcodeproj` in Xcode, select an iOS 17 or later simulator/device, and run the `SwiftFileRunner` target.

Tap **Edit** to change the built-in example, **Import** to choose a `.swift` file in Files, and **Run** to parse and render it. `Examples/Counter.swift` is an importable sample.

## Supported source subset

The interpreter accepts a root `App { ... }`, a view expression, or a conventional SwiftUI `View` type with a `var body: some View` property. It reads literal `@State` declarations and supports these views:

- `VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `NavigationStack`, `Form`, and `Spacer` (including stack spacing)
- `Text("...")` with `\(variable)` interpolation
- SF Symbols through `Image(systemName: "...")`, plus `Divider`
- `Button("...") { ... }`
- `TextField("...", text: $name)`
- `SecureField("...", text: $password)`
- `Toggle("...", isOn: $enabled)`
- `Slider(value: $level, in: 0...100)` and the labeled prototype form
- `Stepper("...", value: $count, in: 0...10)`
- Boolean `if flag { ... } else { ... }` view branches
- `.padding()`, `.padding(number)`, `.font(.title)`, `.foregroundStyle(.blue)`, `.buttonStyle(...)`, `.disabled(...)`, `.navigationTitle(...)`, and `.accessibilityLabel(...)`
- Multiline button actions with numeric `+=` / `-=`, literal assignments, string append, and Boolean `.toggle()`

The example is a conventional `ContentView`-style `.swift` source file with `@State` properties. The runner reads the supported view tree and turns each node into actual SwiftUI controls; edits and button actions update bound state live. The interpreter does not execute imported frameworks or arbitrary Swift statements, build a new app binary, or launch a separately signed app bundle. Unsupported syntax produces an error instead of being executed.

## Project layout

- `SwiftFileRunner/Interpreter.swift` — bounded SwiftSyntax source selection, supported-subset parser, literal `@State` reader, and safe action evaluator
- SwiftParser 603.0.1 — validates imported source and locates the actual `View.body` and `@State` declarations before lowering the supported subset
- `SwiftFileRunner/RunnerApp.swift` — iOS app, source editor/importer, and native SwiftUI renderer
- `SwiftFileRunnerTests/` — syntax selection, view parsing, action behavior, and parser limit tests
- `SwiftFileRunnerUITests/` — simulator check that the sample renders and its button updates live state

Run the parser and action tests on a machine with Swift installed using `swift test`. Build and run the iOS host app from Xcode.
