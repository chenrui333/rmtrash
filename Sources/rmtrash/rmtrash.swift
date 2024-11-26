import Foundation
import ArgumentParser

struct RtError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

@main
struct RtCommand: ParsableCommand {
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        commandName: "rmtrash",
        abstract: "Move files and directories to the trash.",
        discussion: "rmtrash is a small utility that will move the file to OS X's Trash rather than obliterating the file (as rm does).",
        version: "0.5.2",
        shouldDisplay: true,
        subcommands: [],
        helpNames: .shortAndLong
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
    var rmEmptyDirs: Bool = false
    
    @Flag(name: .shortAndLong, help: "Verbose mode; explain at all times what is being done.")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Display a help message, and exit.")
    var help: Bool = false
    
    @Flag(name: .long, help: "Display version information, and exit.")
    var version: Bool = false
    
    @Argument(help: "The files or directories to move to trash.")
    var paths: [String]
    
    func run() throws {
        if help {
            print(RtCommand.helpMessage())
        } else if version {
            print("rmtrash version \(RtCommand.configuration.version)")
        } else {
            let args = try parseArgs()
            try Trash(config: args).remove(paths: paths)
        }
    }
    
    func parseArgs() throws -> Trash.Config {
        var interactiveMode: Trash.Config.InteractiveMode = .always
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
                throw RtError("rmtrash: invalid argument for --interactive: \(interactive)")
            }
        }
        return Trash.Config(
            interactiveMode: interactiveMode,
            force: force,
            recursive: recursive,
            rmEmptyDirs: rmEmptyDirs,
            rmRootDir: !preserveRoot,
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
        guard let enumerator = enumerator(at: url,
                                          includingPropertiesForKeys: nil,
                                          options: [.skipsHiddenFiles]) else {
            return true
        }
        return enumerator.allObjects.isEmpty
    }
    
    func isRootDir(_ url: URL) -> Bool {
        return url.standardizedFileURL.path == "/"
    }
    
    func fileCount(_ url: URL) -> Int {
        var count = 0
        if let enumerator = enumerator(at: url,
                                       includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                guard let fileAttributes = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]) else {
                    continue
                }
                if fileAttributes.isRegularFile! {
                    count += 1
                }
            }
        }
        return count
    }
    
    func isGlob(_ path: String) -> Bool {
        let globCharacters = ["*", "?", "[", "]", "{", "}", "**"]
        let characters = Array(path)
        var i = 0
        while i < characters.count {
            if characters[i] == "\\" && i + 1 < characters.count {
                i += 2
                continue
            }
            let currentChar = String(characters[i])
            if globCharacters.contains(currentChar) {
                return true
            }
            i += 1
        }
        return false
    }
    
    
    func normalizePath(_ path: String) -> [URL] {
        if isGlob(path) {
            var urls = [URL]()
            if let enumerator = enumerator(at: URL(fileURLWithPath: "."), includingPropertiesForKeys: nil, options: []) {
                for case let fileURL as URL in enumerator {
                    if fnmatch(path, fileURL.path, 0) == 0 {
                        urls.append(fileURL.standardizedFileURL)
                    }
                }
            }
            return urls
        } else {
            return [URL(fileURLWithPath: path).standardizedFileURL]
        }
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
        var rmEmptyDirs: Bool
        var rmRootDir: Bool
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
        let urls = paths.flatMap(fileManager.normalizePath)
        if urls.isEmpty {
            throw RtError("rmtrash: missing operand")
        }
        if config.interactiveMode == .once &&
            !question("Are you sure you want to move \(urls.count) path\(urls.count > 1 ? "s" : "") to trash?") {
            return
        }
        for url in urls {

            // file exists check
            if !fileManager.fileExists(atPath: url.path) && !config.force {
                throw RtError("rmtrash: \(url.path): No such file or directory")
            }

            // root directory check
            if fileManager.isRootDir(url) && !config.rmRootDir {
                throw RtError("rmtrash: it is dangerous to operate recursively on '/'")
            }

            // directory check
            let isDir = fileManager.isDirectory(url)
            if !config.recursive && isDir { // 1. is a directory and not recursive
                if config.rmEmptyDirs { // 1.1. can remove empty directories
                    if !fileManager.isEmptyDirectory(url) { // 1.1.1. is not empty
                        throw RtError("rmtrash: directory not empty")  //
                    }
                } else { // 1.2. can't remove empty directories
                    throw RtError("rmtrash: \(url.path): is a directory")
                }
            }

            // interactive check
            if config.interactiveMode == .always &&
                !question("Are you sure you want to remove \(url.path)?") {
                continue
            }

            try fileManager.trashItem(at: url)
        }
    }
}
