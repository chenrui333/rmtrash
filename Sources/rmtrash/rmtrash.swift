import Foundation
import ArgumentParser

@main
struct Command: ParsableCommand {
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        commandName: "rmtrash",
        abstract: "Move files and directories to the trash.",
        discussion: "rmtrash is a small utility that will move the file to macOS's Trash rather than obliterating the file (as rm does).",
        version: "0.6.3",
        shouldDisplay: true,
        subcommands: [],
        helpNames: .long
    )
    
    @Flag(name: .shortAndLong, help: "Ignore nonexistant files, and never prompt before removing.")
    var force: Bool = false
    
    @Flag(name: .customShort("i"), help: "Prompt before every removal.")
    var interactiveAlways: Bool = false
    
    @Flag(name: .customShort("I"), help: "Prompt once before removing more than three files, or when removing recursively. This option is less intrusive than -i, but still gives protection against most mistakes.")
    var interactiveOnce: Bool = false
    
    @Option(name: .customLong("interactive"), help: "Prompt according to WHEN: never, once (-I), or always (-i). If WHEN is not specified, then prompt always.")
    var interactive: String?
    
    @Flag(name: [.customLong("one-file-system"), .customShort("x")], help: "When removing a hierarchy recursively, skip any directory that is on a file system different from that of the corresponding command line argument ")
    var oneFileSystem: Bool = false
    
    @Flag(name: .customLong("preserve-root"), inversion: .prefixedNo, help: "Do not remove \"/\" (the root directory), which is the default behavior.")
    var preserveRoot: Bool = true
    
    @Flag(name: [.short, .long, .customShort("R")], help: "Recursively remove directories and their contents.")
    var recursive: Bool = false
    
    @Flag(name: [.customShort("d"), .customLong("dir")], help: "Remove empty directories. This option permits you to remove a directory without specifying -r/-R/--recursive, provided that the directory is empty. In other words, rm -d is equivalent to using rmdir.")
    var emptyDirs: Bool = false
    
    @Flag(name: .shortAndLong, help: "Verbose mode; explain at all times what is being done.")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Display version information, and exit.")
    var version: Bool = false
    
    @Argument(help: "The files or directories to move to trash.")
    var paths: [String] = []
    
    func run() throws {
        guard !version else {
            print("rmtrash version \(Command.configuration.version)")
            return
        }
        let args = try parseArgs()
        Logger.level = args.verbose ? .verbose : .error
        Logger.verbose("Arguments: \(args)")
        if !Trash(config: args).removeMultiple(paths: paths) {
            Command.exit(withError: ExitCode.failure)
        }
    }
    
    func parseArgs() throws -> Trash.Config {
        if paths.isEmpty {
            throw Panic("rmtrash: missing operand\nTry 'rmtrash --help' for more information.")
        }
        var interactiveMode = Trash.Config.InteractiveMode(rawValue: ProcessInfo.processInfo.environment["RMTRASH_INTERACTIVE_MODE"] ?? "never") ?? .never
        if force {
            interactiveMode = .never
        } else if interactiveAlways {
            interactiveMode = .always
        } else if interactiveOnce {
            interactiveMode = .once
        } else if let interactive = interactive {
            if let mode = Trash.Config.InteractiveMode(rawValue: interactive) {
                interactiveMode = mode
            } else {
                throw Panic("rmtrash: invalid argument for --interactive: \(interactive)nTry 'rmtrash --help' for more information.")
            }
        }
        return Trash.Config(
            interactiveMode: interactiveMode,
            force: force,
            recursive: recursive,
            emptyDirs: emptyDirs,
            preserveRoot: preserveRoot,
            oneFileSystem: oneFileSystem,
            verbose: verbose
        )
    }
}

// MARK: - FileManager
extension FileManager {
    func trashItem(at url: URL) throws {
        Logger.verbose("rmtrash: \(url.path)")
        try trashItem(at: url, resultingItemURL: nil)
    }
    
    func isDirectory(_ url: URL) throws -> Bool {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues.isDirectory == true
    }
    
    func isEmptyDirectory(_ url: URL) -> Bool {
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: nil,  options: []) else {
            return true
        }
        for _ in enumerator {
            return false
        }
        return true
    }
    
    func isRootDir(_ url: URL) -> Bool {
        return url.standardizedFileURL.path == "/"
    }
    
    func isCrossMountPoint(_ url: URL) throws -> Bool {
        let cur = URL(fileURLWithPath: currentDirectoryPath)
        let curVol = try cur.resourceValues(forKeys: [URLResourceKey.volumeURLKey])
        let urlVol = try url.resourceValues(forKeys: [URLResourceKey.volumeURLKey])
        return curVol.volume != urlVol.volume
    }
    
}

// MARK: - Logger
struct Logger {
    enum Level: Int {
        case verbose = 0
        case error = 1
    }
    
    static var level: Level = .error
    
    struct StdError: TextOutputStream {
        mutating func write(_ string: String) {
            fputs(string, stderr)
        }
    }
    
    static func verbose(_ message: String) {
        guard level.rawValue <= Level.verbose.rawValue else { return }
        print(message)
    }
    
    static func error(_ message: String) {
        guard level.rawValue <= Level.error.rawValue else { return }
        var stdError = StdError()
        print(message, to: &stdError)
    }
}


// MARK: - Error
struct Panic: Error, CustomDebugStringConvertible {
    let message: String
    var localizedDescription: String { message }
    var debugDescription: String { message }
    init(_ message: String) {
        self.message = message
    }
}

// MARK: - Trash
struct Trash {
    
    struct Config: Codable {
        enum InteractiveMode: String, ExpressibleByArgument, Codable {
            case always
            case once
            case never
        }
        
        var interactiveMode: InteractiveMode
        var force: Bool
        var recursive: Bool
        var emptyDirs: Bool
        var preserveRoot: Bool
        var oneFileSystem: Bool
        var verbose: Bool
    }
    
    let config: Config
    let fileManager = FileManager.default
    
    init(config: Config) {
        self.config = config
    }
    
    private func question(_ message: String) -> Bool {
        print("\(message) (y/n) ", terminator: "")
        let answer = readLine()
        return answer?.lowercased() == "y" || answer?.lowercased() == "yes"
    }
    
    private func canNotRemovePanic(path: String, err: String) -> Panic {
        return Panic("rmtrash: cannot remove '\(path)': \(err)")
    }
    
}

// MARK: Remove handling
extension Trash {
    
    func removeMultiple(paths: [String]) -> Bool {
        guard paths.count > 0 else {
            return true
        }
        if config.interactiveMode == .once {
            if !promptOnceCheck(paths: paths) {
                return true
            }
        }
        var success = true
        for path in paths {
            success = removeOne(path: path) && success
        }
        return success
    }
    
    @discardableResult private func removeOne(path: String) -> Bool {
        do {
            guard case .info(url: let url, isDir: let isDir) = try permissionCheck(path: path) else {
                return true
            }
            switch (config.interactiveMode, isDir) {
            case (.always, true):
                removeDirectory(path)
            case (.always, false):
                if question("remove file \(path)?")  {
                    try fileManager.trashItem(at: url)
                }
            case (.never, _), (.once, _):
                try fileManager.trashItem(at: url)
            }
            return true
        } catch let error as Panic {
            Logger.error(error.message)
        } catch {
            Logger.error("rmtrash: \(error.localizedDescription)")
        }
        return false
    }
    
    
    private func removeDirectory(_ path: String)  {
        let url = URL(fileURLWithPath: path)
        // when directory is empty, no examine needed
        if fileManager.isEmptyDirectory(url) {
            removeEmptyDirectory(path)
            return
        }
        guard question("descend into directory: '\(url.relativePath)'?") else {
            return
        }
        let subs = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
        for sub in subs {
            let subPath = URL(fileURLWithPath: path).appendingPathComponent(sub).relativePath
            removeOne(path: subPath)
        }
        // try to remove the directory after all files in it are removed
        removeEmptyDirectory(path)
    }
    
    private func removeEmptyDirectory(_ path: String) {
        guard question("remove directory '\(path)'?") else {
            return
        }
        var conf = config
        conf.recursive = false          // no recursive anymore
        conf.emptyDirs = true           // but can remove empty directories
        conf.interactiveMode = .never   // and no interactive mode, because did interactive before
        Trash(config: conf).removeOne(path: path)
    }
}


// MARK: Permission Check
extension Trash {
    
    private func promptOnceCheck(paths: [String]) -> Bool {
        var isDirs = [String: Bool]()
        for path in paths {
            guard let res = try? fileManager.isDirectory(URL(fileURLWithPath: path)) else {
                continue
            }
            isDirs[path] = res
        }
        let dirs = isDirs.filter({ $0.value }).keys.map({ $0 })
        let fileCount = isDirs.filter({ $0.value == false }).count
        let dirWord = dirs.count == 1 ? "dir" : "dirs"
        let fileWord = fileCount == 1 ? "file" : "files"
        switch (dirs.count > 0, fileCount > 0) {
        case (true, false):
            return question("recursively remove \(dirs.count) \(dirWord)?")
        case (false, true):
            return fileCount <= 3 || question("remove \(fileCount) \(fileWord)?")
        case (true, true):
            return question("recursively remove \(dirs.count) \(dirWord) and \(fileCount) \(fileWord)?")
        case (false, false):
            return true
        }
    }
    
    private func permissionCheck(path: String) throws -> PermissionCheckResult {
        // file exists check
        if !fileManager.fileExists(atPath: path) {
            if !config.force {
                throw canNotRemovePanic(path: path, err: "No such file or directory")
            }
            return .skip // skip nonexistent files when force is set
        }
        
        let url = URL(fileURLWithPath: path)
        let isDir = try fileManager.isDirectory(url)

        // cross mount point check
        if config.oneFileSystem  {
            let cross = try fileManager.isCrossMountPoint(url)
            if cross {
                throw canNotRemovePanic(path: path, err: "Cross-device link")
            }
        }
        
        // directory check
        if isDir {
            // root directory check
            if fileManager.isRootDir(url) && config.preserveRoot {
                throw canNotRemovePanic(path: path, err: "Preserve root")
            }
            
            // recursive check
            if !config.recursive {
                if config.emptyDirs {
                    if !fileManager.isEmptyDirectory(url) {
                        // can remove empty directory when emptyDirs set but not recursive
                        throw canNotRemovePanic(path: path, err: "Directory not empty")
                    }
                } else {
                    // can not remove directory when not recursive and not emptyDirs
                    throw canNotRemovePanic(path: path, err: "Is a directory")
                    
                }
            }
        }
        
        return .info(url: url, isDir: isDir)
    }
    
    enum PermissionCheckResult {
        case skip
        case info(url: URL, isDir: Bool)
    }
}
