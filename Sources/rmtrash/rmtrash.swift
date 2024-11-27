import Foundation
import ArgumentParser

@main
struct Command: ParsableCommand {
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        commandName: "rmtrash",
        abstract: "Move files and directories to the trash.",
        discussion: "rmtrash is a small utility that will move the file to macOS's Trash rather than obliterating the file (as rm does).",
        version: "0.6.2",
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
    var paths: [String]
    
    func run() throws {
        if version {
            print("rmtrash version \(Command.configuration.version)")
            Command.exit()
        }
        do {
            let args = try parseArgs()
            Logger.level = args.verbose ? .verbose : .error
            Logger.verbose("Arguments: \(args)")
            try Trash(config: args).removeMultiple(paths: paths)
        } catch let error as Panic {
            Logger.panic(error.message)
        } catch {
            Logger.panic("rmtrash: \(error.localizedDescription)")
        }
    }
    
    func parseArgs() throws -> Trash.Config {
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
                throw Panic("rmtrash: invalid argument for --interactive: \(interactive)")
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

struct Logger {
    enum Level: Int {
        case verbose = 0
        case error = 1
        case panic = 2
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
    
    static func panic(_ message: String) {
        var stdError = StdError()
        print(message, to: &stdError)
        exit(1)
    }
}

struct Panic: Error {
    let message: String
    var localizedDescription: String { message }
    init(_ message: String) {
        self.message = message
    }
}

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
    
    
    func removeOne(path: String) throws {
        let (url, isDir) = try permissionCheck(path: path)
        switch (config.interactiveMode, isDir) {
        case (.always, true):
            try examineDirectory(url)
        case (.always, false):
            if question("remove \(path)?")  {
                try fileManager.trashItem(at: url)
            }
        case (.never, _), (.once, _):
            try fileManager.trashItem(at: url)
        }
    }
    
    func removeMultiple(paths: [String]) throws {
        if paths.isEmpty {
            throw Panic("rmtrash: missing operand")
        }
        
        if config.interactiveMode == .once {
            if try promptOnceCheck(paths: paths) == false {
                return
            }
        }
        
        for path in paths {
            do {
                try removeOne(path: path)
            } catch let error as Panic {
                Logger.error(error.message)
            } catch {
                throw error
            }
        }
    }
    
    private func promptOnceCheck(paths: [String]) throws -> Bool {
        var isDirs = [String: Bool]()
        for path in paths {
            isDirs[path] = try fileManager.isDirectory(URL(fileURLWithPath: path))
        }
        let dirs = isDirs.filter({ $0.value }).keys.map({ $0 })
        let fileCount = isDirs.filter({ $0.value == false }).count
        switch (dirs.count > 0, fileCount > 0) {
        case (true, false):
            return question("recursively remove \(dirs.count == 1 ? dirs[0] : "\(dirs.count) dirs")?")
        case (false, true):
            return fileCount <= 3 || question("remove \(fileCount) files?")
        case (true, true):
            return question("recursively remove \(dirs.count) dirs and \(fileCount) files?")
        case (false, false):
            return true
        }
    }
    
    private func permissionCheck(path: String) throws -> (url: URL, isDir: Bool) {
        // file exists check
        if !fileManager.fileExists(atPath: path) {
            if !config.force {
                throw Panic("rmtrash: \(path): No such file or directory")
            }
        }
        
        let url = URL(fileURLWithPath: path)
        // cross mount point check
        if config.oneFileSystem  {
            let cross = try fileManager.isCrossMountPoint(url)
            if cross {
                throw Panic("rmtrash: \(path): cross-device link")
            }
        }
        
        // directory check
        let isDir = try fileManager.isDirectory(url)
        
        if isDir {
            // root directory check
            if fileManager.isRootDir(url) && config.preserveRoot {
                throw Panic("rmtrash: it is dangerous to operate recursively on '/'")
            }
            
            // recursive check
            if !config.recursive {  // 1. is a directory and not recursive
                if config.emptyDirs { // 1.1. can remove empty directories
                    if !fileManager.isEmptyDirectory(url) { // 1.1.1. can't remove non-empty directories
                        throw Panic("rmtrash: \(path): Directory not empty")
                    }
                } else {  // 2. can't remove directories
                    throw Panic("rmtrash: \(path): is a directory")
                    
                }
            }
        }
        
        return (url, isDir)
    }
    
    private func examineDirectory(_ url: URL) throws {
        guard question("examine files in directory: \(url.path)?") else {
            return
        }
        guard let fileEnumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) else {
            return
        }
        for case let fileURL as URL in fileEnumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]) else {
                continue
            }
            if resourceValues.isDirectory == false {
                if question("remove \(fileURL.path)?") {
                    try fileManager.trashItem(at: fileURL)
                }
            } else {
                try examineDirectory(fileURL)
            }
        }
        // remove current directory if empty
        if fileManager.isEmptyDirectory(url) {
            try fileManager.trashItem(at: url)
        }
    }
}
