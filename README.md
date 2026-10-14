# ImgCast

Native macOS (Apple Silicon) app version of the `imgcast` bash script:
convert images between formats, one file or whole folder trees.

## Features

- Drag and drop files or folders (or drop onto the Dock icon / "Open With")
- Targets: WebP, JPG, PNG, ICO, HEIC, AVIF, TIFF
- Quality slider for lossy formats (JPG default 85, others 80)
- Resize to `WxH` or `N` (square); output name gets a `-WxH` suffix, like the script
- ICO: any size up to 256x256, blank = fit longest side to 256
- Folders: include sub-folders, filter by source format, skip files already in the target format
- Output beside the source, or into a custom folder that mirrors the source tree
- Skip or overwrite existing outputs
- Parallel conversion across all cores, per-file results log

## Engine

Conversion uses Apple's ImageIO directly, so ffmpeg is not needed. EXIF
orientation is applied, and transparency is flattened onto white for JPG.
ImageIO cannot encode WebP, so WebP output uses `cwebp` (or `ffmpeg` as a
fallback) from Homebrew:

```bash
brew install webp
```

## Build

Requires only the Xcode Command Line Tools (macOS 14+).

```bash
scripts/build-app.sh            # -> build/ImgCast.app
scripts/build-app.sh --install  # also copies to /Applications
```

For development: `swift run`.

The app is ad-hoc signed, which is fine for running on your own Mac.
