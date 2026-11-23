/// A command's completions in Fig's model: subcommands, options and positional arguments. The Fig adapter
/// translates its specs into this; Smalti's own logic never sees JavaScript.
public struct CompletionSpec: Equatable, Hashable, Sendable {
    public let name: [String]
    public let description: String?
    public let subcommands: [CompletionSpec]
    public let options: [OptionSpec]
    public let args: [ArgSpec]

    public init(
        name: [String], description: String? = nil, subcommands: [CompletionSpec] = [], options: [OptionSpec] = [],
        args: [ArgSpec] = []
    ) {
        self.name = name
        self.description = description
        self.subcommands = subcommands
        self.options = options
        self.args = args
    }
}

public struct OptionSpec: Equatable, Hashable, Sendable {
    public let names: [String]
    public let description: String?
    public let args: [ArgSpec]

    public init(names: [String], description: String? = nil, args: [ArgSpec] = []) {
        self.names = names
        self.description = description
        self.args = args
    }
}

public enum ArgTemplate: Hashable, Sendable {
    case filepaths
    case folders
}

/// Names one generator inside a loaded spec: the adapter keeps the JavaScript, the domain only this key.
public struct GeneratorID: Hashable, Sendable {
    public let spec: String
    public let path: [String]
    public let ordinal: Int

    public init(spec: String, path: [String], ordinal: Int) {
        self.spec = spec
        self.path = path
        self.ordinal = ordinal
    }
}

public struct ArgSpec: Equatable, Hashable, Sendable {
    public let name: String?
    public let suggestions: [Suggestion]
    public let templates: Set<ArgTemplate>
    public let generators: [GeneratorID]
    /// A variadic argument takes every remaining word: the walk stays on it.
    public let isVariadic: Bool

    public init(
        name: String? = nil, suggestions: [Suggestion] = [], templates: Set<ArgTemplate> = [],
        generators: [GeneratorID] = [], isVariadic: Bool = false
    ) {
        self.name = name
        self.suggestions = suggestions
        self.templates = templates
        self.generators = generators
        self.isVariadic = isVariadic
    }
}

public struct Suggestion: Equatable, Hashable, Sendable {
    public let name: String
    public let description: String?
    /// What goes into the line instead of `name`; `{cursor}` marks where the cursor ends.
    public let insertValue: String?

    public init(name: String, description: String? = nil, insertValue: String? = nil) {
        self.name = name
        self.description = description
        self.insertValue = insertValue
    }
}
