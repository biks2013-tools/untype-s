import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct WindowScreenshotError: Error, Sendable, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

/// Captures the front window of an app (the Screenshot operator) with
/// ScreenCaptureKit. Only that window is captured, never what overlaps it
/// (untype's overlay or pop-up). Needs the Screen Recording permission.
public enum WindowScreenshotCapture {
    /// Longest side of the image sent, in pixels. Claude reads images up to
    /// this size without downscaling them; window text stays legible.
    public static let maxLongEdge = 1568

    public static func capture(pid: pid_t, appName: String) async throws -> WindowScreenshot {
        guard CGPreflightScreenCaptureAccess() else {
            // Shows the system prompt the first time; the grant takes effect
            // after untype is reopened.
            _ = CGRequestScreenCaptureAccess()
            throw WindowScreenshotError(
                "Screen Recording permission is missing: allow untype in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen untype."
            )
        }
        guard let windowID = frontWindowID(pid: pid) else {
            throw WindowScreenshotError("\(appName) has no window on screen to capture.")
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw WindowScreenshotError("Could not list the windows on screen: \(error.localizedDescription)")
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw WindowScreenshotError("The window of \(appName) is not available for capture.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let pixelWidth = filter.contentRect.width * scale
        let pixelHeight = filter.contentRect.height * scale
        let fit = min(1, CGFloat(maxLongEdge) / max(pixelWidth, pixelHeight, 1))
        configuration.width = max(1, Int((pixelWidth * fit).rounded()))
        configuration.height = max(1, Int((pixelHeight * fit).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw WindowScreenshotError("Could not capture the window of \(appName): \(error.localizedDescription)")
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw WindowScreenshotError("Could not encode the screenshot of \(appName) as PNG.")
        }
        return WindowScreenshot(
            image: LLMImageAttachment(
                data: png,
                mediaType: "image/png",
                pixelWidth: image.width,
                pixelHeight: image.height
            ),
            appName: appName
        )
    }

    /// Puts the screenshot on the clipboard (PNG and TIFF), so what was sent
    /// can be pasted and inspected.
    @MainActor
    public static func copyToClipboard(_ screenshot: WindowScreenshot) throws {
        guard let rep = NSBitmapImageRep(data: screenshot.image.data),
              let tiff = rep.tiffRepresentation
        else {
            throw WindowScreenshotError("Could not decode the screenshot for the clipboard.")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(screenshot.image.data, forType: .png),
              pasteboard.setData(tiff, forType: .tiff)
        else {
            throw WindowScreenshotError("Could not write the screenshot to the clipboard.")
        }
    }

    /// The front-most normal window of `pid` (the window list is ordered
    /// front to back).
    private static func frontWindowID(pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID
            else {
                continue
            }
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               (bounds["Width"] ?? 0) < 50 || (bounds["Height"] ?? 0) < 50 {
                continue
            }
            return number
        }
        return nil
    }
}
