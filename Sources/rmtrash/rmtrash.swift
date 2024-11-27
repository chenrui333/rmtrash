import Foundation
import ArgumentParser

@main
struct Command: ParsableCommand {
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        commandName: "rmtrash",
        abstract: "Move files and directories to the trash.",
        discussion: "rmtrash is a small utility that will move the file to OS X's Trash rather than obliterating the file (as rm does).",
        version: "0.6.0",
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
    
    @Flag(name: .customLong("preserve-root"), inversion: .prefixedNo, help: "Do not remove \"/\" (the root directory), which is the default behavior.")
    var preserveRoot: Bool = true
    
    @Flag(name: .shortAndLong, help: "Recursively remove directories and their contents.")
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
            try  Trash(config: args).remove(paths: paths)
        } catch let error as Panic {
            Logger.panic(error.message)
        } catch {
            Logger.panic("rmtrash: \(error)")
        }
    }
    
    func parseArgs() throws -> Trash.Config {
        var interactiveMode: Trash.Config.InteractiveMode = .once
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
            verbose: verbose
        )
    }
}

extension FileManager {
    func trashItem(at url: URL) throws {
        try trashItem(at: url, resultingItemURL: nil)
    }
    
    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
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
    
    func checkFileCount(_ url: [URL], greaterThen value: Int) -> Bool {
        var count = 0
        for url in url {
            if !isDirectory(url) {
                count += 1
            }
            if count > value {
                return true
            }
            guard let enumerator = enumerator(at: url, includingPropertiesForKeys: nil,  options: []) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                if !isDirectory(fileURL) {
                    count += 1
                }
                if count > value {
                    return true
                }
            }
        }
        return false
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
        var verbose: Bool
    }
    
    let config: Config
    let fileManager = FileManager.default
    
    init(config: Config) {
        self.config = config
    }
    
    func question(_ message: String) -> Bool {
        print("\(message) (y/n) ", terminator: "")
        let answer = readLine()
        return answer?.lowercased() == "y" || answer?.lowercased() == "yes"
    }
    
    
    func remove(paths: [String]) throws {
        if paths.isEmpty {
            throw Panic("rmtrash: missing operand")
        }
        let urls = paths.map({ URL(fileURLWithPath: $0).standardizedFileURL })
        if config.interactiveMode == .once &&
            fileManager.checkFileCount(urls, greaterThen: 3) &&
            !question("remove multiple files?") {
            return
        }
        for url in urls {
            
            // file exists check
            if !fileManager.fileExists(atPath: url.path) && !config.force {
                throw Panic("rmtrash: \(url.path): No such file or directory")
            }
            
            // root directory check
            if fileManager.isRootDir(url) && config.preserveRoot {
                throw Panic("rmtrash: it is dangerous to operate recursively on '/'")
            }
            
            // directory check
            let isDir = fileManager.isDirectory(url)
            if !config.recursive && isDir {             // 1. is a directory and not recursive
                if config.emptyDirs {                   // 1.1. can remove empty directories
                    if !fileManager.isEmptyDirectory(url) { // 1.1.1. is not empty
                        throw Panic("rmtrash: \(url.path): Directory not empty")
                    }
                } else { // 1.2. can't remove empty directories
                    throw Panic("rmtrash: \(url.path): is a directory")
                    
                }
            }
            
            // interactive check
            if config.interactiveMode == .always &&
                !question("remove \(url.path)?") {
                continue
            }
            
            Logger.verbose("rmtrash: \(url.path)")
            try fileManager.trashItem(at: url)
        }
    }
}
