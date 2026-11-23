import JavaScriptCore
import SmaltiCore

/// Turns a Fig spec object into a `CompletionSpec`, following `loadSpec` and registering each generator under a
/// `GeneratorID` (the spec, the subcommand path and its order of appearance) so it can be run later.
struct FigSpecTranslator {
    /// Loads another spec's object by name, for `loadSpec`.
    let load: (String) -> JSValue?
    let specName: String
    private(set) var generators: [GeneratorID: JSValue] = [:]
    private var ordinal = 0
    /// Specs being expanded right now: a `loadSpec` back to one of them (`simctl` loads itself) is not followed.
    private var expanding: [String]

    init(specName: String, load: @escaping (String) -> JSValue?) {
        self.specName = specName
        self.load = load
        expanding = [specName]
    }

    mutating func spec(from value: JSValue, path: [String] = []) -> CompletionSpec {
        let names = Self.names(of: value["name"])
        let target = value["loadSpec"].isString ? value["loadSpec"].toString() : nil
        let followed = target.flatMap { name in expanding.contains(name) ? nil : load(name).map { (name, $0) } }
        let body = followed?.1 ?? value
        let here = path + (names.first.map { [$0] } ?? [])
        if let name = followed?.0 { expanding.append(name) }
        defer { if followed != nil { expanding.removeLast() } }
        return CompletionSpec(
            name: names, description: Self.text(value["description"]) ?? Self.text(body["description"]),
            subcommands: Self.elements(of: body["subcommands"]).map { spec(from: $0, path: here) },
            options: Self.elements(of: body["options"]).map { option(from: $0, path: here) },
            args: Self.elements(of: body["args"]).map { arg(from: $0, path: here) })
    }

    private mutating func option(from value: JSValue, path: [String]) -> OptionSpec {
        OptionSpec(
            names: Self.names(of: value["name"]), description: Self.text(value["description"]),
            args: Self.elements(of: value["args"]).map { arg(from: $0, path: path) },
            isRepeatable: value["isRepeatable"].toBool(), requiresSeparator: value["requiresSeparator"].toBool())
    }

    private mutating func arg(from value: JSValue, path: [String]) -> ArgSpec {
        ArgSpec(
            name: Self.text(value["name"]),
            suggestions: Self.elements(of: value["suggestions"]).compactMap(Self.suggestion(from:)),
            templates: Self.templates(of: value["template"]),
            generators: Self.elements(of: value["generators"]).map { register($0, path: path) },
            isOptional: value["isOptional"].toBool(), isVariadic: value["isVariadic"].toBool())
    }

    private mutating func register(_ generator: JSValue, path: [String]) -> GeneratorID {
        let id = GeneratorID(spec: specName, path: path, ordinal: ordinal)
        ordinal += 1
        generators[id] = generator
        return id
    }

    static func suggestion(from value: JSValue) -> Suggestion? {
        if value.isString { return Suggestion(name: value.toString()) }
        guard value.isObject, let name = names(of: value["name"]).first else { return nil }
        return Suggestion(name: name, description: text(value["description"]), insertValue: text(value["insertValue"]))
    }

    /// A Fig field that may be one value or an array of them.
    static func elements(of value: JSValue?) -> [JSValue] {
        guard let value, !value.isUndefined, !value.isNull else { return [] }
        guard value.isArray else { return [value] }
        let count = Int(value["length"].toInt32())
        return (0..<count).compactMap { value.atIndex($0) }
    }

    static func names(of value: JSValue?) -> [String] {
        elements(of: value).filter(\.isString).map { $0.toString() }
    }

    static func text(_ value: JSValue?) -> String? {
        guard let value, value.isString else { return nil }
        return value.toString()
    }

    private static func templates(of value: JSValue?) -> Set<ArgTemplate> {
        Set(
            names(of: value).compactMap { name in
                switch name {
                case "filepaths": .filepaths
                case "folders": .folders
                default: nil
                }
            })
    }
}

extension JSValue {
    fileprivate subscript(_ key: String) -> JSValue { forProperty(key) }
}
