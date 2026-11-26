import Foundation
import SmaltiCore
import Synchronization
import Testing

/// `ProjectFiles` in memory: which folders have a project file or `.git`, the layouts and their fingerprints. It
/// records every folder asked about and every write.
public final class InMemoryProjectFiles: ProjectFiles, @unchecked Sendable {
    // Unchecked: tests drive it from one task; the mutex only guards against overlapping reads in async tests.
    private let state: Mutex<State>

    struct State {
        var layoutRoots: Set<String>
        var repositoryRoots: Set<String>
        var files: [String: ProjectLayoutFile] = [:]
        var errors: [String: ProjectFileError] = [:]
        var links: [String: String] = [:]
        var looked: [String] = []
        var reads: [String] = []
        var writes: [(root: String, layout: SharedLayout)] = []
        var writeError: ProjectFileError?
    }

    public init(layoutRoots: Set<String> = [], repositoryRoots: Set<String> = []) {
        state = Mutex(State(layoutRoots: layoutRoots, repositoryRoots: repositoryRoots))
    }

    /// Every folder `hasLayout(in:)` was asked about, in order.
    public var looked: [String] { state.withLock { $0.looked } }
    /// Every root `layout(at:)` read, in order.
    public var reads: [String] { state.withLock { $0.reads } }
    public var writes: [(root: String, layout: SharedLayout)] { state.withLock { $0.writes } }

    /// `root` gets a project file with `layout`, read with `fingerprint`.
    public func put(_ layout: SharedLayout, at root: String, fingerprint: String) {
        state.withLock {
            $0.layoutRoots.insert(root)
            $0.files[root] = ProjectLayoutFile(layout: layout, fingerprint: fingerprint)
            $0.errors[root] = nil
        }
    }

    public func fail(at root: String, with error: ProjectFileError) {
        state.withLock {
            $0.layoutRoots.insert(root)
            $0.errors[root] = error
        }
    }

    public func remove(at root: String) {
        state.withLock {
            $0.layoutRoots.remove(root)
            $0.files[root] = nil
        }
    }

    public func link(_ path: String, to real: String) { state.withLock { $0.links[path] = real } }

    public func failWrites(with error: ProjectFileError?) { state.withLock { $0.writeError = error } }

    public func hasLayout(in directory: String) -> Bool {
        state.withLock {
            $0.looked.append(directory)
            return $0.layoutRoots.contains(directory)
        }
    }

    public func isRepositoryRoot(_ directory: String) -> Bool {
        state.withLock { $0.repositoryRoots.contains(directory) }
    }

    public func realPath(_ path: String) -> String { state.withLock { $0.links[path] ?? path } }

    public func layout(at root: String) throws(ProjectFileError) -> ProjectLayoutFile {
        let result: Result<ProjectLayoutFile, ProjectFileError> = state.withLock {
            $0.reads.append(root)
            if let error = $0.errors[root] { return .failure(error) }
            guard $0.layoutRoots.contains(root), let file = $0.files[root] else {
                return .failure(.missing(root: root))
            }
            return .success(file)
        }
        return try result.get()
    }

    public func write(_ layout: SharedLayout, to root: String) throws(ProjectFileError) -> String {
        let result: Result<String, ProjectFileError> = state.withLock {
            if let error = $0.writeError { return .failure(error) }
            $0.writes.append((root, layout))
            let fingerprint = "written-\($0.writes.count)"
            $0.layoutRoots.insert(root)
            $0.files[root] = ProjectLayoutFile(layout: layout, fingerprint: fingerprint)
            return .success(fingerprint)
        }
        return try result.get()
    }
}

/// `ProjectRecords` in memory, for use cases and the shared contract.
public final class InMemoryProjectRecords: ProjectRecords, @unchecked Sendable {
    // Unchecked: guarded by the mutex.
    private let state: Mutex<(records: [ProjectRecord], writes: Int, error: ProjectFileError?)>

    public init(_ records: [ProjectRecord] = []) {
        state = Mutex((records, 0, nil))
    }

    public var writes: Int { state.withLock { $0.writes } }

    public func failWrites(with error: ProjectFileError?) { state.withLock { $0.error = error } }

    public func all() -> [ProjectRecord] { state.withLock { $0.records } }

    public func replace(with records: [ProjectRecord]) throws(ProjectFileError) {
        let error: ProjectFileError? = state.withLock {
            if let error = $0.error { return error }
            $0.records = records
            $0.writes += 1
            return nil
        }
        if let error { throw error }
    }
}

/// Behaviour every `ProjectRecords` must have (F8.5).
public enum ProjectRecordsContract {
    public static func verify(_ make: () -> some ProjectRecords) throws {
        #expect(make().all().isEmpty, "a new store has no projects")
        let records = make()
        let approval = ProjectApproval(
            fingerprint: "abc", approvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            commands: [
                PlannedCommand(command: "npm run dev", place: "web"), PlannedCommand(command: "ls", place: nil),
            ],
            paneCount: 3, layout: "columns")
        let saved = [
            ProjectRecord(
                root: "/Users/ana/dev/b", name: "b", lastOpened: Date(timeIntervalSince1970: 1_800_000_100),
                approval: approval),
            ProjectRecord(
                root: "/Users/ana/dev/a", name: "a", lastOpened: Date(timeIntervalSince1970: 1_800_000_000),
                approval: nil),
        ]
        try records.replace(with: saved)
        #expect(records.all() == saved, "replacing then reading returns the records in their order")
        try records.replace(with: [])
        #expect(records.all().isEmpty, "replacing with nothing empties it")
    }
}
