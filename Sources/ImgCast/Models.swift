import Foundation
import UniformTypeIdentifiers

/// Target formats. Mirrors the bash script (webp, jpg, png, ico) plus a few
/// extras that ImageIO can write natively.
enum OutputFormat: String, CaseIterable, Identifiable {
    case webp, jpg, png, ico, heic, avif, tiff

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    var utType: UTType {
        switch self {
        case .webp: return .webP
        case .jpg:  return .jpeg
        case .png:  return .png
        case .ico:  return .ico
        case .heic: return .heic
        case .avif: return UTType("public.avif") ?? .heic
        case .tiff: return .tiff
        }
    }

    var supportsQuality: Bool {
        switch self {
        case .webp, .jpg, .heic, .avif: return true
        case .png, .ico, .tiff: return false
        }
    }

    var defaultQuality: Int { self == .jpg ? 85 : 80 }

    var supportsAlpha: Bool { self != .jpg }
}

/// Source extensions picked up when scanning folders.
let defaultSourceExtensions = ["png", "jpg", "jpeg", "webp", "bmp", "tiff", "tif", "gif", "heic", "avif"]

/// Normalize a format/extension so jpeg == jpg and tif == tiff.
func normalizedExt(_ ext: String) -> String {
    switch ext.lowercased() {
    case "jpeg": return "jpg"
    case "tif": return "tiff"
    default: return ext.lowercased()
    }
}

struct PixelSize: Equatable {
    var width: Int
    var height: Int

    /// Parses "32x32" or "32" (square). Returns nil for malformed input.
    init?(parsing text: String) {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: "x", omittingEmptySubsequences: false)
        let nums = parts.map { Int($0) }
        if nums.count == 1, let n = nums[0], n > 0 {
            width = n; height = n
        } else if nums.count == 2, let w = nums[0], let h = nums[1], w > 0, h > 0 {
            width = w; height = h
        } else {
            return nil
        }
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var suffix: String { "-\(width)x\(height)" }
}

struct ConvertOptions {
    var format: OutputFormat = .webp
    var quality: Int = 80
    var size: PixelSize? = nil
    var recursive = false
    var sourceExtensions: Set<String> = Set(defaultSourceExtensions)
    var outputDirectory: URL? = nil
    var overwrite = false
}

struct ConversionJob: Identifiable {
    let id = UUID()
    let source: URL
    let destination: URL
}

enum JobStatus {
    case converted, skipped(String), failed(String)
}

struct LogEntry: Identifiable {
    let id = UUID()
    let source: URL
    let destination: URL
    let status: JobStatus
}
