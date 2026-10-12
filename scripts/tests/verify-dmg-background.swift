import AppKit
import Vision

guard CommandLine.arguments.count == 2 else {
    fputs("Expected a background image path.\n", stderr)
    exit(2)
}

let backgroundURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: backgroundURL),
      let representation = image.representations.first else {
    fputs("Could not read the generated DMG background.\n", stderr)
    exit(1)
}

guard representation.pixelsWide == 1080, representation.pixelsHigh == 720 else {
    fputs(
        "Expected a 1080x720 Retina background, got \(representation.pixelsWide)x\(representation.pixelsHigh).\n",
        stderr
    )
    exit(1)
}

guard abs(image.size.width - 540) < 0.5, abs(image.size.height - 360) < 0.5 else {
    fputs("Expected the Retina background to retain a 540x360 logical size.\n", stderr)
    exit(1)
}

guard let backgroundData = try? Data(contentsOf: backgroundURL),
      let bitmap = NSBitmapImageRep(data: backgroundData) else {
    fputs("Could not inspect the generated DMG background pixels.\n", stderr)
    exit(1)
}

func relativeLuminance(at point: NSPoint) -> CGFloat? {
    let pixelX = Int(point.x * CGFloat(bitmap.pixelsWide) / image.size.width)
    let pixelY = Int(
        (image.size.height - point.y) * CGFloat(bitmap.pixelsHigh) / image.size.height
    )
    guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(NSColorSpace.sRGB) else {
        return nil
    }

    func linearized(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linearized(color.redComponent)
        + 0.7152 * linearized(color.greenComponent)
        + 0.0722 * linearized(color.blueComponent)
}

let lightBackgroundPoints = [
    NSPoint(x: 140, y: 105),
    NSPoint(x: 400, y: 105),
    NSPoint(x: 140, y: 180),
    NSPoint(x: 400, y: 180)
]

for backgroundPoint in lightBackgroundPoints {
    guard let luminance = relativeLuminance(at: backgroundPoint),
          (luminance + 0.05) / 0.05 >= 4.5 else {
        fputs("Expected the light background to provide at least 4.5:1 contrast for black Finder content.\n", stderr)
        exit(1)
    }
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(url: backgroundURL)
try handler.perform([request])

let recognizedText = (request.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: " ")

guard recognizedText.localizedCaseInsensitiveContains("Drag to install") else {
    fputs("Expected the background to visibly contain 'Drag to install'.\n", stderr)
    exit(1)
}
