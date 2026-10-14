//
//  QrCodeGenerator.swift
//  HeadunitPad
//
//  1:1 port of open-headunit QrCodeGenerator.kt using iOS CoreImage.
//  Generates crisp, high-resolution QR codes without blur or anti-aliasing artifacts.
//

import UIKit
import CoreImage

public enum QrCodeGenerator {
    private static let context = CIContext()

    /// Generates a sharp UIImage QR code of the given content and pixel dimension.
    public static func generateQrCode(content: String, size: CGFloat = 300) -> UIImage? {
        guard let data = content.data(using: .utf8) else { return nil }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up using nearest-neighbor so pixels stay crisp
        let extent = outputImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scaleX = size / extent.width
        let scaleY = size / extent.height
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
