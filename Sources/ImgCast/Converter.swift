import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ConvertError: LocalizedError {
    case unreadable
    case renderFailed
    case writeFailed
    case webpEncoderMissing
    case encoderFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "could not read image"
        case .renderFailed: return "could not render image"
        case .writeFailed: return "could not write output"
        case .webpEncoderMissing: return "WebP needs cwebp or ffmpeg (brew install webp)"
        case .encoderFailed(let msg): return msg
        }
    }
}

/// Native ImageIO conversion. WebP output is the only thing ImageIO cannot
/// encode, so it goes through cwebp (or ffmpeg) when available.
enum Converter {
    static let icoMaxSide = 256

    static func convert(_ job: ConversionJob, options: ConvertOptions) throws {
        let image = try loadImage(job.source)
        let target = targetSize(for: image, options: options)
        let rendered = try render(image, to: target, flattenAlpha: !options.format.supportsAlpha)

        try FileManager.default.createDirectory(
            at: job.destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        // encode into a temp file first so a failure never leaves a partial output
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("imgcast-\(UUID().uuidString).\(options.format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        switch options.format {
        case .webp:
            try writeWebP(rendered, to: tmp, quality: options.quality)
        case .ico:
            try writeICO(rendered, to: tmp)
        default:
            try write(rendered, to: tmp, type: options.format.utType,
                      quality: options.format.supportsQuality ? options.quality : nil)
        }

        if FileManager.default.fileExists(atPath: job.destination.path) {
            _ = try FileManager.default.replaceItemAt(job.destination, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: job.destination)
        }
    }

    /// Loads the first frame with EXIF orientation applied.
    static func loadImage(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            throw ConvertError.unreadable
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ConvertError.unreadable
        }
        return img
    }

    /// Exact WxH when a size is set; ICO otherwise caps the longest side at 256.
    static func targetSize(for image: CGImage, options: ConvertOptions) -> PixelSize {
        if let size = options.size { return size }
        let w = image.width, h = image.height
        if options.format == .ico, max(w, h) > icoMaxSide {
            let scale = Double(icoMaxSide) / Double(max(w, h))
            return PixelSize(width: max(1, Int((Double(w) * scale).rounded())),
                             height: max(1, Int((Double(h) * scale).rounded())))
        }
        return PixelSize(width: w, height: h)
    }

    static func render(_ image: CGImage, to size: PixelSize, flattenAlpha: Bool) throws -> CGImage {
        if !flattenAlpha, size.width == image.width, size.height == image.height {
            return image
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let alphaInfo: CGImageAlphaInfo = flattenAlpha ? .noneSkipLast : .premultipliedLast
        guard let ctx = CGContext(data: nil, width: size.width, height: size.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: alphaInfo.rawValue) else {
            throw ConvertError.renderFailed
        }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        if flattenAlpha {
            // JPEG has no alpha: composite onto white instead of black
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(rect)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        guard let out = ctx.makeImage() else { throw ConvertError.renderFailed }
        return out
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Int?) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.writeFailed
        }
        var props: [CFString: Any] = [:]
        if let quality {
            props[kCGImageDestinationLossyCompressionQuality] = Double(min(max(quality, 0), 100)) / 100
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.writeFailed }
    }

    // MARK: - ICO

    /// ImageIO's ICO encoder only accepts a few square sizes, so write a
    /// single-image ICO with an embedded PNG, which allows any size up to 256.
    static func writeICO(_ image: CGImage, to url: URL) throws {
        guard image.width <= icoMaxSide, image.height <= icoMaxSide else {
            throw ConvertError.encoderFailed("ICO size must be at most \(icoMaxSide)x\(icoMaxSide)")
        }
        let pngData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, nil) else {
            throw ConvertError.writeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.writeFailed }

        var data = Data()
        func u16(_ v: Int) { data.append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]) }
        func u32(_ v: Int) { u16(v & 0xffff); u16((v >> 16) & 0xffff) }

        u16(0); u16(1); u16(1)                      // reserved, type = icon, count
        data.append(UInt8(image.width % 256))       // 0 means 256
        data.append(UInt8(image.height % 256))
        data.append(0); data.append(0)              // palette, reserved
        u16(1); u16(32)                             // planes, bits per pixel
        u32(pngData.length)                         // image size
        u32(6 + 16)                                 // offset of image data
        data.append(pngData as Data)
        try data.write(to: url)
    }

    // MARK: - WebP

    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    static func findTool(_ name: String) -> String? {
        searchPaths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var webpEncoderName: String? {
        if findTool("cwebp") != nil { return "cwebp" }
        if findTool("ffmpeg") != nil { return "ffmpeg" }
        return nil
    }

    static func writeWebP(_ image: CGImage, to url: URL, quality: Int) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("imgcast-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(image, to: tmp, type: .png, quality: nil)

        let q = String(min(max(quality, 0), 100))
        if let cwebp = findTool("cwebp") {
            try run(cwebp, ["-quiet", "-q", q, "-alpha_q", "100", tmp.path, "-o", url.path])
        } else if let ffmpeg = findTool("ffmpeg") {
            try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-y", "-i", tmp.path,
                             "-quality", q, url.path])
        } else {
            throw ConvertError.webpEncoderMissing
        }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ConvertError.encoderFailed(msg.isEmpty ? "\(URL(fileURLWithPath: tool).lastPathComponent) failed" : msg)
        }
    }
}
