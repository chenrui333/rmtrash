import Foundation
import ArgumentParser

// Custom TextOutputStream for stderr
struct StandardError: TextOutputStream {
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

struct Rmtrash: ParsableCommand {
    @Flag(name: .shortAndLong, help: "Recursively remove directories and their contents.")
    var recursive: Bool = false

    @Flag(name: .shortAndLong, help: "Ignore nonexistent files and arguments, never prompt.")
    var force: Bool = false

    @Flag(name: .shortAndLong, help: "Print debugging information.")
    var verbose: Bool = false

    @Argument(help: "The files or directories to move to trash.")
    var paths: [String]

    func run() throws {
        var standardError = StandardError()
        let fileManager = FileManager.default

        for path in paths {
            let fileURL = URL(fileURLWithPath: path)

            // Check if the file or directory exists
            guard fileManager.fileExists(atPath: path) else {
                if !force {
                    print("File does not exist: \(path)", to: &standardError)
                }
                continue
            }

            // Check if it's a directory and if recursive flag is set
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            if isDirectory.boolValue && !recursive {
                print("Skipping directory (no -r flag): \(path)", to: &standardError)
                continue
            }

            // Move to trash
            do {
                var resultingItemURL: NSURL?
                try fileManager.trashItem(at: fileURL, resultingItemURL: &resultingItemURL)
                if let trashedURL = resultingItemURL {
                    if verbose {
                        print("Moved to trash: \(trashedURL.path ?? "")")
                    }
                }
            } catch {
                print("Failed to move file to trash: \(error.localizedDescription)", to: &standardError)
            }
        }
    }
}

Rmtrash.main()