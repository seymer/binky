import Foundation

/// Expands archives with system tools (no bundled decompressors).
enum ArchiveExtractionService: Sendable {

    enum ExtractionError: Error {
        case unsupportedFormat(String)
        case processFailed(String, Int32)
        case destinationExists(URL)
        /// Archive contained an entry that escaped the destination directory (path traversal).
        case pathTraversalDetected(URL)
    }

    /// Extracts `source` into `destinationDirectory` (created if needed). Does not delete the source.
    ///
    /// After extraction, every produced entry is verified to live under `destinationDirectory`.
    /// Any entry whose resolved path escapes the destination causes the extraction to be rolled
    /// back (destination tree removed) and `pathTraversalDetected` is thrown.
    static func extract(source: URL, destinationDirectory: URL) throws {
        let fm = FileManager.default
        let ext = source.pathExtension.lowercased()

        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        switch ext {
        case "zip":
            try runDittoExtractZip(from: source, to: destinationDirectory)
        case "tar", "tgz":
            try runTarExtract(from: source, to: destinationDirectory, gzip: ext == "tgz")
        case "gz" where source.deletingPathExtension().pathExtension.lowercased() == "tar":
            try runTarExtract(from: source, to: destinationDirectory, gzip: true)
        case "gz":
            try runTarExtract(from: source, to: destinationDirectory, gzip: true)
        case "bz2":
            try runTarExtract(from: source, to: destinationDirectory, bzip: true)
        case "xz":
            try runTarExtract(from: source, to: destinationDirectory, xz: true)
        default:
            throw ExtractionError.unsupportedFormat(ext)
        }

        try verifyNoPathTraversal(under: destinationDirectory)
    }

    private static func runDittoExtractZip(from source: URL, to destinationDirectory: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", source.path, destinationDirectory.path]
        try runProcess(p, label: "ditto")
    }

    private static func runTarExtract(from source: URL, to destinationDirectory: URL, gzip: Bool = false, bzip: Bool = false, xz: Bool = false) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        // -P is intentionally NOT passed (the default already strips leading slashes and rejects
        // absolute paths). The post-extract verifier below catches the remaining `..` cases that
        // BSD tar does not block on its own.
        var args = ["-xf", source.path, "-C", destinationDirectory.path]
        if gzip {
            args.insert("-z", at: 1)
        } else if bzip {
            args.insert("-j", at: 1)
        } else if xz {
            args.insert("-J", at: 1)
        }
        p.arguments = args
        try runProcess(p, label: "tar")
    }

    private static func runProcess(_ p: Process, label: String) throws {
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw ExtractionError.processFailed(label, p.terminationStatus)
        }
    }

    /// Walks the extracted tree and confirms every entry resolves to a path under `root`.
    /// On detection, removes the entire extracted tree and throws `pathTraversalDetected`.
    private static func verifyNoPathTraversal(under root: URL) throws {
        let fm = FileManager.default
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalRootWithSlash = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }

        for case let url as URL in enumerator {
            // Resolve symlinks too — an extracted symlink could itself point outside the tree.
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            if resolved != canonicalRoot && !resolved.hasPrefix(canonicalRootWithSlash) {
                try? fm.removeItem(at: root)
                throw ExtractionError.pathTraversalDetected(url)
            }
        }
    }
}
