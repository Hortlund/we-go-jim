import SwiftUI
import UIKit

/// Every training story uses the same 9:16 canvas and 1080 × 1920 export.
@MainActor
enum TrainingShareImageRenderer {
    static let canvasSize = CGSize(width: 360, height: 640)

    static func render<Content: View>(_ content: Content) -> UIImage? {
        let renderer = ImageRenderer(content: content
            .frame(width: canvasSize.width, height: canvasSize.height)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .medium))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
