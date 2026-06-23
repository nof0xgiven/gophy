import Foundation

enum ModelFileDetector {
    private static let usableModelFileExtensions: Set<String> = [
        "safetensors",
        "mlmodelc",
    ]

    static func containsUsableModelArtifact(at path: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            return false
        }

        if !isDirectory.boolValue {
            return isUsableModelArtifact(path)
        }

        guard let enumerator = fileManager.enumerator(
            at: path,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            if isUsableModelArtifact(url) {
                return true
            }
        }

        return false
    }

    private static func isUsableModelArtifact(_ url: URL) -> Bool {
        usableModelFileExtensions.contains(url.pathExtension.lowercased())
    }
}
