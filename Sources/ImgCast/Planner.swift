import Foundation

/// Turns the user's inputs + options into a list of source -> destination jobs,
/// following the same rules as the imgcast bash script.
enum Planner {
    static func plan(inputs: [URL], options: ConvertOptions) -> (jobs: [ConversionJob], skipped: [LogEntry]) {
        var jobs: [ConversionJob] = []
        var skipped: [LogEntry] = []
        var seen = Set<URL>()
        let fm = FileManager.default

        for input in inputs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: input.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let base = input.standardizedFileURL
                for file in collectFiles(in: base, options: options) where seen.insert(file).inserted {
                    let dst = destination(for: file, base: base, options: options)
                    // folder mode skips files already in the target format
                    if normalizedExt(file.pathExtension) == options.format.fileExtension, options.size == nil {
                        skipped.append(LogEntry(source: file, destination: dst, status: .skipped("already \(options.format.label)")))
                        continue
                    }
                    jobs.append(ConversionJob(source: file, destination: dst))
                }
            } else {
                let file = input.standardizedFileURL
                guard seen.insert(file).inserted else { continue }
                let dst = destination(for: file, base: nil, options: options)
                jobs.append(ConversionJob(source: file, destination: dst))
            }
        }
        return (jobs, skipped)
    }

    static func collectFiles(in dir: URL, options: ConvertOptions) -> [URL] {
        let exts = Set(options.sourceExtensions.map { $0.lowercased() })
        let fm = FileManager.default
        var result: [URL] = []

        if options.recursive {
            let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let url = en?.nextObject() as? URL {
                if exts.contains(url.pathExtension.lowercased()), isRegularFile(url) {
                    result.append(url.standardizedFileURL)
                }
            }
        } else {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            result = items.filter { exts.contains($0.pathExtension.lowercased()) && isRegularFile($0) }
                .map { $0.standardizedFileURL }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// <stem>[-WxH].<ext>, beside the source or mirrored under the output dir.
    static func destination(for src: URL, base: URL?, options: ConvertOptions) -> URL {
        let stem = src.deletingPathExtension().lastPathComponent + (options.size?.suffix ?? "")
        let name = "\(stem).\(options.format.fileExtension)"

        guard let outDir = options.outputDirectory else {
            return src.deletingLastPathComponent().appendingPathComponent(name)
        }
        if let base {
            let srcDir = src.deletingLastPathComponent().path
            let basePath = base.path
            if srcDir.hasPrefix(basePath) {
                let rel = String(srcDir.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let dir = rel.isEmpty ? outDir : outDir.appendingPathComponent(rel, isDirectory: true)
                return dir.appendingPathComponent(name)
            }
        }
        return outDir.appendingPathComponent(name)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
