import Foundation

enum ModelStorageLocator {
    static func candidatePaths(for model: ModelDefinition, storageManager: StorageManager) -> [URL] {
        var paths: [URL] = []
        let roots = [storageManager.modelsDirectory, storageManager.alternativeModelsDirectory].compactMap(\.self)

        for root in roots {
            paths.append(root.appendingPathComponent(model.id))

            let sanitizedHuggingFaceID = model.huggingFaceID
                .replacingOccurrences(of: "/", with: "-")
                .lowercased()
            if sanitizedHuggingFaceID != model.id {
                paths.append(root.appendingPathComponent(sanitizedHuggingFaceID))
            }

            if let hubCachePath = hubCachePath(for: model, under: root) {
                paths.append(hubCachePath)
            }
        }

        return unique(paths)
    }

    static func usableModelPath(for model: ModelDefinition, storageManager: StorageManager) -> URL? {
        candidatePaths(for: model, storageManager: storageManager)
            .first { ModelFileDetector.containsUsableModelArtifact(at: $0) }
    }

    static func storedBytes(for model: ModelDefinition, storageManager: StorageManager) -> Int64 {
        candidatePaths(for: model, storageManager: storageManager)
            .reduce(Int64(0)) { total, path in
                total + directorySize(at: path)
            }
    }

    static func hasStoredFiles(for model: ModelDefinition, storageManager: StorageManager) -> Bool {
        candidatePaths(for: model, storageManager: storageManager)
            .contains { containsStoredFile(at: $0) }
    }

    static func firstStoredPath(for model: ModelDefinition, storageManager: StorageManager) -> URL? {
        candidatePaths(for: model, storageManager: storageManager)
            .first { containsStoredFile(at: $0) }
    }

    private static func hubCachePath(for model: ModelDefinition, under root: URL) -> URL? {
        let components = model.huggingFaceID.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }

        return root
            .appendingPathComponent("models")
            .appendingPathComponent(components[0])
            .appendingPathComponent(components[1])
    }

    private static func containsStoredFile(at path: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            return false
        }

        if !isDirectory.boolValue {
            return true
        }

        guard let enumerator = fileManager.enumerator(
            at: path,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return true
            }
        }

        return false
    }

    private static func directorySize(at path: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return Int64((try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: path,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }

    private static func unique(_ paths: [URL]) -> [URL] {
        var seen = Set<String>()
        return paths.filter { path in
            let key = path.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }
}
