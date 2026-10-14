import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: ConversionModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                inputPane
                Divider()
                logPane
            }
            .frame(minWidth: 380)

            settingsPane
                .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
        }
        .task(id: model.planKey) {
            try? await Task.sleep(for: .milliseconds(150))
            await model.refreshPlannedCount()
        }
    }

    // MARK: - Inputs

    private var inputPane: some View {
        ZStack {
            if model.inputs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Drop images or folders here")
                        .font(.title3)
                    Button("Choose...") { Self.openPanel(model: model) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.inputs, id: \.self) { url in
                        InputRow(url: url) { model.remove(url) }
                    }
                }
                .listStyle(.inset)
            }

            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 200)
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in model.add([url]) } }
                }
            }
            return true
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { Self.openPanel(model: model) } label: { Label("Add", systemImage: "plus") }
                Button("Clear") { model.clearInputs() }
                    .disabled(model.inputs.isEmpty || model.isRunning)
                Spacer()
                Text(model.inputs.isEmpty ? "" : "\(model.plannedCount) file(s) to convert")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(10)
            .background(.bar)
        }
    }

    // MARK: - Log

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Results").font(.headline)
                Spacer()
                if !model.log.isEmpty {
                    let s = model.summary
                    Text("\(s.done) converted, \(s.skipped) skipped, \(s.failed) failed")
                        .font(.callout)
                        .foregroundStyle(s.failed > 0 ? .red : .secondary)
                }
            }
            .padding(10)

            if model.isRunning {
                ProgressView(value: Double(model.completed), total: Double(max(model.total, 1)))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            List(model.log.reversed()) { entry in
                LogRow(entry: entry)
            }
            .listStyle(.inset)
            .overlay {
                if model.log.isEmpty {
                    Text("Nothing converted yet").foregroundStyle(.tertiary)
                }
            }
        }
        .frame(minHeight: 180)
    }

    // MARK: - Settings

    private var settingsPane: some View {
        VStack(spacing: 0) {
            Form {
                Section("Format") {
                    Picker("Convert to", selection: $model.format) {
                        ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                    }
                    if model.format.supportsQuality {
                        LabeledContent("Quality") {
                            HStack {
                                Slider(value: $model.quality, in: 0...100, step: 1)
                                Text("\(Int(model.quality))")
                                    .monospacedDigit()
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                    if model.format == .webp, Converter.webpEncoderName == nil {
                        Label("WebP needs cwebp or ffmpeg. Run: brew install webp",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                Section("Size") {
                    if model.format == .ico {
                        TextField("ICO size", text: $model.sizeText, prompt: Text("e.g. 32x32, blank = fit 256"))
                    } else {
                        Toggle("Resize", isOn: $model.resize)
                        if model.resize {
                            TextField("Size", text: $model.sizeText, prompt: Text("WxH or N, e.g. 64x64"))
                        }
                    }
                    if model.sizeIsInvalid {
                        Text(model.format == .ico ? "Use WxH up to 256x256, e.g. 32x32" : "Use WxH like 32x32, or N like 32")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Section("Folders") {
                    Toggle("Include sub-folders", isOn: $model.recursive)
                    LabeledContent("Source formats") {
                        SourceFormatPicker(selection: $model.sourceExtensions)
                    }
                }
                .disabled(!model.hasFolderInput)

                Section("Output") {
                    Picker("Save to", selection: Binding(
                        get: { model.outputDirectory == nil ? 0 : 1 },
                        set: { if $0 == 0 { model.outputDirectory = nil } else { chooseOutputDirectory() } }
                    )) {
                        Text("Same folder as source").tag(0)
                        Text("Custom folder...").tag(1)
                    }
                    if let dir = model.outputDirectory {
                        HStack {
                            Text(dir.path(percentEncoded: false))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Change") { chooseOutputDirectory() }
                        }
                    }
                    Toggle("Overwrite existing files", isOn: $model.overwrite)
                }
            }
            .formStyle(.grouped)

            HStack {
                if model.isRunning {
                    Button("Cancel") { model.cancel() }
                } else if let dir = revealTarget {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([dir]) }
                }
                Spacer()
                Button {
                    model.start()
                } label: {
                    Text(model.isRunning ? "Converting \(model.completed)/\(model.total)" : "Convert")
                        .frame(minWidth: 90)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isRunning || model.inputs.isEmpty || model.sizeIsInvalid || model.plannedCount == 0)
            }
            .padding(12)
        }
    }

    private var revealTarget: URL? {
        if let first = model.log.first(where: { if case .converted = $0.status { return true }; return false }) {
            return first.destination
        }
        return nil
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.outputDirectory = url
        }
    }

    @MainActor
    static func openPanel(model: ConversionModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        if panel.runModal() == .OK {
            model.add(panel.urls)
        }
    }
}

// MARK: - Rows

private struct InputRow: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                Text(url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isDir {
                Text("Folder").font(.caption).foregroundStyle(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.source.lastPathComponent)  ->  \(entry.destination.lastPathComponent)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.destination])
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch entry.status {
        case .converted: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped: Image(systemName: "arrow.uturn.right.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var detail: String? {
        switch entry.status {
        case .converted: return nil
        case .skipped(let why): return "skipped: \(why)"
        case .failed(let why): return why
        }
    }
}

private struct SourceFormatPicker: View {
    @Binding var selection: Set<String>
    private let groups: [(label: String, exts: [String])] = [
        ("PNG", ["png"]), ("JPG", ["jpg", "jpeg"]), ("WEBP", ["webp"]), ("GIF", ["gif"]),
        ("BMP", ["bmp"]), ("TIFF", ["tiff", "tif"]), ("HEIC", ["heic"]), ("AVIF", ["avif"]),
    ]

    var body: some View {
        Menu(title) {
            ForEach(groups, id: \.label) { group in
                Toggle(group.label, isOn: Binding(
                    get: { group.exts.allSatisfy(selection.contains) },
                    set: { on in
                        if on { selection.formUnion(group.exts) } else { selection.subtract(group.exts) }
                    }
                ))
            }
            Divider()
            Button("All") { selection = Set(defaultSourceExtensions) }
        }
        .fixedSize()
    }

    private var title: String {
        let picked = groups.filter { $0.exts.allSatisfy(selection.contains) }.map(\.label)
        if picked.count == groups.count { return "All" }
        if picked.isEmpty { return "None" }
        return picked.joined(separator: ", ")
    }
}
