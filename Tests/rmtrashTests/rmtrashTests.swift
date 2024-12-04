import XCTest
@testable import rmtrash

enum FileMock: Equatable {
    case file(name: String)
    case directory(name: String, sub: [FileMock])
    
    var name: String {
        switch self {
        case .file(let name): return name
        case .directory(let name, _): return name
        }
    }
    
    var isDirectory: Bool {
        switch self {
        case .file: return false
        case .directory: return true
        }
    }
}

class FileManagerMock: FileManagerType {
    private var root: [FileMock]
    
    init(root: [FileMock]) {
        self.root = root
    }
    
    private func findFile(components: [String], in files: [FileMock]) -> FileMock? {
        // Special case for root directory
        if components.isEmpty || (components.count == 1 && components[0].isEmpty) {
            return .directory(name: "", sub: files)
        }
        
        guard let first = components.first else { return nil }
        for file in files {
            if file.name == first {
                if components.count == 1 {
                    return file
                } else {
                    switch file {
                    case .directory(_, let sub):
                        return findFile(components: Array(components.dropFirst()), in: sub)
                    default:
                        return nil
                    }
                }
            }
        }
        return nil
    }
    
    private func removeFile(components: [String], from files: inout [FileMock]) -> Bool {
        guard let first = components.first else { return false }
        
        if components.count == 1 {
            // Remove the file directly from current directory
            if let index = files.firstIndex(where: { $0.name == first }) {
                files.remove(at: index)
                return true
            }
            return false
        }
        
        // Navigate to subdirectory
        for i in 0..<files.count {
            if files[i].name == first {
                if case .directory(let name, var sub) = files[i] {
                    if removeFile(components: Array(components.dropFirst()), from: &sub) {
                        files[i] = .directory(name: name, sub: sub)
                        return true
                    }
                }
            }
        }
        return false
    }
    
    func trashItem(at url: URL) throws {
        let components = url.pathComponents.filter { $0 != "/" }
        if components.isEmpty {
            root = []
        } else if !removeFile(components: components, from: &root) {
            throw Panic("File not found")
        }
    }
    
    func isDirectory(_ url: URL) throws -> Bool {
        let components = url.pathComponents.filter { $0 != "/" }
        guard let file = findFile(components: components, in: root) else {
            throw Panic("File not found")
        }
        return file.isDirectory
    }
    
    func isEmptyDirectory(_ url: URL) -> Bool {
        let components = url.pathComponents.filter { $0 != "/" }
        guard let file = findFile(components: components, in: root) else {
            return false
        }
        if case .directory(_, let sub) = file {
            return sub.isEmpty
        }
        return false
    }
    
    func isRootDir(_ url: URL) -> Bool {
        // Match real FileManager implementation which uses standardizedFileURL
        return url.standardizedFileURL.path == "/"
    }
    
    func isCrossMountPoint(_ url: URL) throws -> Bool {
        // For mock purposes, we'll always return false
        return false
    }
    
    func fileExists(atPath path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return findFile(components: components, in: root) != nil
    }
    
    func subpaths(atPath path: String, enumerator handler: (String) -> Bool) {
        let components = path.split(separator: "/").map(String.init)
        guard let file = findFile(components: components, in: root) else {
            return
        }
        
        func enumerate(file: FileMock, currentPath: String) {
            switch file {
            case .directory(_, let sub):
                for subFile in sub {
                    let newPath = currentPath.isEmpty ? subFile.name : "\(currentPath)/\(subFile.name)"
                    if handler(newPath) {
                        if case .directory = subFile {
                            enumerate(file: subFile, currentPath: newPath)
                        }
                    }
                }
            default:
                break
            }
        }
        
        if case .directory = file {
            enumerate(file: file, currentPath: "")
        }
    }
    
    func currentFileStructure() -> [FileMock] {
        return root
    }
}

final class rmtrashTests: XCTestCase {

    func testExample() throws {
        // Write your test here and use XCTAssert functions to check expected conditions.
    }

    // MARK: - Config Tests
    
    func testForceConfig() {
        let mockFiles: [FileMock] = [
            .file(name: "test.txt"),
            .directory(name: "dir1", sub: [
                .file(name: "file1.txt")
            ])
        ]
        let fileManager = FileManagerMock(root: mockFiles)
        
        // Test force config - should remove without prompting
        let forceConfig = Trash.Config(
            interactiveMode: .never,
            force: true,
            recursive: false,
            emptyDirs: false,
            preserveRoot: true,
            oneFileSystem: false,
            verbose: false
        )
        let trashWithForce = Trash(config: forceConfig, fileManager: fileManager)
        XCTAssertTrue(trashWithForce.removeMultiple(paths: ["/test.txt"]))
    }
    
    func testRecursiveConfig() {
        let mockFiles: [FileMock] = [
            .directory(name: "dir1", sub: [
                .file(name: "file1.txt"),
                .directory(name: "subdir", sub: [
                    .file(name: "file2.txt")
                ])
            ])
        ]
        let fileManager = FileManagerMock(root: mockFiles)
        
        // Test non-recursive config - should fail
        let nonRecursiveConfig = Trash.Config(
            interactiveMode: .never,
            force: true,
            recursive: false,
            emptyDirs: false,
            preserveRoot: true,
            oneFileSystem: false,
            verbose: false
        )
        let trashNonRecursive = Trash(config: nonRecursiveConfig, fileManager: fileManager)
        XCTAssertFalse(trashNonRecursive.removeMultiple(paths: ["/dir1"]))
        
        // Test recursive config - should succeed
        let recursiveConfig = Trash.Config(
            interactiveMode: .never,
            force: true,
            recursive: true,
            emptyDirs: false,
            preserveRoot: true,
            oneFileSystem: false,
            verbose: false
        )
        let trashRecursive = Trash(config: recursiveConfig, fileManager: fileManager)
        XCTAssertTrue(trashRecursive.removeMultiple(paths: ["/dir1"]))
    }
    
    func testEmptyDirsConfig() {
        let mockFiles: [FileMock] = [
            .directory(name: "emptyDir", sub: []),
            .directory(name: "nonEmptyDir", sub: [
                .file(name: "file.txt")
            ])
        ]
        let fileManager = FileManagerMock(root: mockFiles)
        
        // Test emptyDirs config
        let emptyDirsConfig = Trash.Config(
            interactiveMode: .never,
            force: true,
            recursive: false,
            emptyDirs: true,
            preserveRoot: true,
            oneFileSystem: false,
            verbose: false
        )
        let trashEmptyDirs = Trash(config: emptyDirsConfig, fileManager: fileManager)
        XCTAssertTrue(trashEmptyDirs.removeMultiple(paths: ["/emptyDir"]))
        XCTAssertFalse(trashEmptyDirs.removeMultiple(paths: ["/nonEmptyDir"]))
    }
    
    func testPreserveRootConfig() {
        let mockFiles: [FileMock] = [
            .directory(name: "testdir", sub: [])
        ]
        let fileManager = FileManagerMock(root: mockFiles)
        
        // Test preserveRoot config
        let preserveRootConfig = Trash.Config(
            interactiveMode: .never,
            force: true,
            recursive: true,
            emptyDirs: true,
            preserveRoot: true,
            oneFileSystem: false,
            verbose: false
        )
        let trashPreserveRoot = Trash(config: preserveRootConfig, fileManager: fileManager)
        
        // Root directory should not be removable when preserveRoot is true
        XCTAssertFalse(trashPreserveRoot.removeMultiple(paths: ["/"]))
        
        // Test non-root paths should still work
        XCTAssertTrue(trashPreserveRoot.removeMultiple(paths: ["/testdir"]))
        
        // Test with preserveRoot disabled
        let nonPreserveRootConfig = Trash.Config(
            interactiveMode: .never,
            force: true,
            recursive: true,
            emptyDirs: true,
            preserveRoot: false,
            oneFileSystem: false,
            verbose: false
        )
        let trashNonPreserveRoot = Trash(config: nonPreserveRootConfig, fileManager: fileManager)
        XCTAssertTrue(trashNonPreserveRoot.removeMultiple(paths: ["/"]))
    }
    
    func testFileListStateAfterDeletion() {
        // Initial file structure
        let initialFiles: [FileMock] = [
            .file(name: "test1.txt"),
            .file(name: "test2.txt"),
            .directory(name: "dir1", sub: [
                .file(name: "file1.txt"),
                .file(name: "file2.txt"),
                .directory(name: "subdir", sub: [
                    .file(name: "deep.txt")
                ])
            ])
        ]
        let fileManager = FileManagerMock(root: initialFiles)
        
        let config = Trash.Config(
            interactiveMode: .never,
            force: true,
            recursive: true,
            emptyDirs: true,
            preserveRoot: true,
            oneFileSystem: false,
            verbose: false
        )
        let trash = Trash(config: config, fileManager: fileManager)
        
        // Test single file deletion
        XCTAssertTrue(trash.removeMultiple(paths: ["/test1.txt"]))
        let expectedAfterSingleDelete: [FileMock] = [
            .file(name: "test2.txt"),
            .directory(name: "dir1", sub: [
                .file(name: "file1.txt"),
                .file(name: "file2.txt"),
                .directory(name: "subdir", sub: [
                    .file(name: "deep.txt")
                ])
            ])
        ]
        XCTAssertEqual(fileManager.currentFileStructure(), expectedAfterSingleDelete)
        
        // Test directory deletion
        XCTAssertTrue(trash.removeMultiple(paths: ["/dir1"]))
        let expectedAfterDirDelete: [FileMock] = [
            .file(name: "test2.txt")
        ]
        XCTAssertEqual(fileManager.currentFileStructure(), expectedAfterDirDelete)
        
        // Test remaining file deletion
        XCTAssertTrue(trash.removeMultiple(paths: ["/test2.txt"]))
        XCTAssertEqual(fileManager.currentFileStructure(), [])
    }
}
