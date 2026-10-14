import Foundation
import SwiftUI

@MainActor
final class ConversionModel: ObservableObject {
    @Published var inputs: [URL] = []
    @Published var format: OutputFormat = .webp {
        didSet { if oldValue != format { quality = Double(format.defaultQuality) } }
    }
    @Published var quality: Double = 80
    @Published var resize = false
    @Published var sizeText = ""
    @Published var recursive = false
    @Published var sourceExtensions: Set<String> = Set(defaultSourceExtensions)
    @Published var outputDirectory: URL? = nil
    @Published var overwrite = false
    @Published var dropTargeted = false

    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var log: [LogEntry] = []

    private var task: Task<Void, Never>?

    var hasFolderInput: Bool {
        inputs.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Size used for conversion. ICO always honors the field; other formats
    /// only when "Resize" is on.
    var parsedSize: PixelSize? {
        guard format == .ico || resize else { return nil }
        return PixelSize(parsing: sizeText)
    }

    var sizeIsInvalid: Bool {
        guard format == .ico || resize else { return false }
        let trimmed = sizeText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return format != .ico }
        guard let size = PixelSize(parsing: trimmed) else { return true }
        return format == .ico && max(size.width, size.height) > Converter.icoMaxSide
    }

    var options: ConvertOptions {
        ConvertOptions(format: format,
                       quality: Int(quality.rounded()),
                       size: parsedSize,
                       recursive: recursive,
                       sourceExtensions: sourceExtensions,
                       outputDirectory: outputDirectory,
                       overwrite: overwrite)
    }

    @Published private(set) var plannedCount = 0

    /// Changes whenever anything that affects the plan changes.
    var planKey: String {
        [inputs.map(\.path).joined(separator: "|"), format.rawValue, String(recursive),
         sourceExtensions.sorted().joined(separator: ","), outputDirectory?.path ?? "",
         parsedSize?.suffix ?? ""].joined(separator: "#")
    }

    /// Scans folders off the main thread so big trees don't stall the UI.
    func refreshPlannedCount() async {
        let inputs = inputs, opts = options
        let count = await Task.detached(priority: .utility) {
            Planner.plan(inputs: inputs, options: opts).jobs.count
        }.value
        if !Task.isCancelled { plannedCount = count }
    }

    var summary: (done: Int, skipped: Int, failed: Int) {
        var d = 0, s = 0, f = 0
        for entry in log {
            switch entry.status {
            case .converted: d += 1
            case .skipped: s += 1
            case .failed: f += 1
            }
        }
        return (d, s, f)
    }

    func add(_ urls: [URL]) {
        for url in urls.map(\.standardizedFileURL) where !inputs.contains(url) {
            inputs.append(url)
        }
    }

    func remove(_ url: URL) {
        inputs.removeAll { $0 == url }
    }

    func clearInputs() {
        inputs.removeAll()
        log.removeAll()
        completed = 0
        total = 0
    }

    func start() {
        guard !isRunning, !inputs.isEmpty, !sizeIsInvalid else { return }
        let opts = options
        let plan = Planner.plan(inputs: inputs, options: opts)

        log = plan.skipped
        completed = 0
        total = plan.jobs.count
        isRunning = true

        task = Task {
            await withTaskGroup(of: LogEntry.self) { group in
                let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
                var iterator = plan.jobs.makeIterator()

                func enqueue() -> Bool {
                    guard !Task.isCancelled, let job = iterator.next() else { return false }
                    group.addTask { await Task.detached(priority: .userInitiated) { Self.process(job, opts) }.value }
                    return true
                }

                for _ in 0..<limit where enqueue() {}
                while let entry = await group.next() {
                    log.append(entry)
                    completed += 1
                    _ = enqueue()
                }
            }
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
    }

    nonisolated static func process(_ job: ConversionJob, _ opts: ConvertOptions) -> LogEntry {
        if job.source == job.destination {
            return LogEntry(source: job.source, destination: job.destination, status: .skipped("same file"))
        }
        if !opts.overwrite, FileManager.default.fileExists(atPath: job.destination.path) {
            return LogEntry(source: job.source, destination: job.destination, status: .skipped("exists"))
        }
        do {
            try Converter.convert(job, options: opts)
            return LogEntry(source: job.source, destination: job.destination, status: .converted)
        } catch {
            return LogEntry(source: job.source, destination: job.destination,
                            status: .failed(error.localizedDescription))
        }
    }
}
