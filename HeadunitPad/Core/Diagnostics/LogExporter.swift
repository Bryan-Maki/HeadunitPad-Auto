//
//  LogExporter.swift
//  HeadunitPad
//
//  1:1 port of open-headunit LogExporter.kt
//  Exports diagnostic logs to a file and presents iOS sharing / save sheet.
//

import UIKit

public final class LogExporter {

    public static func exportLogFile() -> URL? {
        let content = AppLog.shared.exportToString()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "headunitpad-log-\(timestamp).txt"

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("LogExporter: Failed to write log file: \(error)")
            return nil
        }
    }

    public static func presentShareSheet(from viewController: UIViewController, sourceView: UIView? = nil) {
        guard let fileURL = exportLogFile() else { return }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            if let view = sourceView {
                popover.sourceView = view
                popover.sourceRect = view.bounds
            } else {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }

        viewController.present(activityVC, animated: true)
    }
}
