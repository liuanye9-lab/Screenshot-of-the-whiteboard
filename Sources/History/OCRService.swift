// OCRService.swift — 基于 Vision 的文字识别
import AppKit
import Vision

enum OCRService {
    static func recognizeText(in image: NSImage, region: CGRect? = nil) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }

        let targetImage: CGImage
        if let rect = region {
            let scale = CGFloat(cgImage.width) / image.size.width
            let cropRect = CGRect(
                x: rect.origin.x * scale,
                y: (image.size.height - rect.origin.y - rect.height) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            targetImage = cgImage.cropping(to: cropRect) ?? cgImage
        } else {
            targetImage = cgImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: targetImage, options: [:])
        try handler.perform([request])

        guard let results = request.results else { return "" }

        let text = results.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.joined(separator: "\n")

        return text
    }

    static func recognizeAndCopy(in image: NSImage, region: CGRect? = nil) async throws -> String {
        let text = try await recognizeText(in: image, region: region)
        if !text.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        return text
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取图片"
        case .noTextFound: return "未识别到文字内容"
        }
    }
}
