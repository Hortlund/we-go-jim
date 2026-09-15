import ImageIO
import UIKit
import XCTest
@testable import WGJ

@MainActor
final class AvatarImageCodecTests: XCTestCase {
    func testCompressionDownsamplesLargePhoto() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
        let source = renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let result = await AvatarImageCodec.compressedAvatarData(from: source, maxPixelSize: 320)
        let data = try XCTUnwrap(result)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 320)
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int), 320)
        XCTAssertLessThan(data.count, source.count)
    }

    func testInvalidImageAndDimensionsDoNotCrash() async {
        for size: CGFloat in [.nan, .infinity, 0, -1] {
            let result = await AvatarImageCodec.thumbnail(from: Data(), maxPixelSize: size)
            XCTAssertNil(result)
        }
        let result = await AvatarImageCodec.compressedAvatarData(from: Data("not an image".utf8), maxPixelSize: 640)
        XCTAssertNil(result)
    }

    func testCancelledCompressionDoesNotReturnImageData() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await AvatarImageCodec.compressedAvatarData(from: Data(), maxPixelSize: 640)
        }
        let result = await task.value
        XCTAssertNil(result)
    }
}
