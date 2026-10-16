//
//  NSImageExtensions.swift
//  Doll
//
//  Created by huikai on 2022/6/12.
//

import AppKit
import Foundation

private let badgeTextAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 8),
    .foregroundColor: NSColor.white,
]
private let badgeHorizontalPadding: CGFloat = 3
private let badgeVerticalPadding: CGFloat = 4

private func badgeTextSize(_ text: String) -> CGSize {
    (text as NSString).size(withAttributes: badgeTextAttributes)
}

private func capsuleSize(aroundTextOfSize textSize: CGSize) -> CGSize {
    let height = textSize.height + badgeVerticalPadding
    return CGSize(width: max(textSize.width + badgeHorizontalPadding, height), height: height)
}

extension NSImage {
    var png: Data? { tiffRepresentation?.bitmap?.png }

    static func redBadgeFits(_ text: String) -> Bool {
        capsuleSize(aroundTextOfSize: badgeTextSize(text)).width <= defaultIconSize
    }

    func addBadgeToImage(drawText text: String) -> NSImage {
        let canvasWidth = defaultIconSize
        let canvasHeight = defaultIconSize
        let canvasSize = NSSize(width: canvasWidth, height: canvasHeight)
        let targetImage = NSImage(size: canvasSize, flipped: false) { (dstRect: CGRect) -> Bool in
            let iconSize = text.isEmpty ? defaultIconSize : defaultIconSize - 2
            self.draw(in: CGRect(origin: .zero, size: NSSize(width: iconSize, height: iconSize)))

            guard !text.isEmpty else {
                return true
            }

            let textRenderSize = badgeTextSize(text)
            let badgeBackgroundSize = capsuleSize(aroundTextOfSize: textRenderSize)
            let badgeFillColor = NSColor.systemRed.withAlphaComponent(0.9)
            let badgeBackgroundRect = CGRect(origin: CGPoint(x: canvasWidth - badgeBackgroundSize.width, y: canvasHeight - badgeBackgroundSize.height), size: badgeBackgroundSize)
            let capsuleRadius = badgeBackgroundSize.height / 2
            let badgeBackgroundPath = NSBezierPath(roundedRect: badgeBackgroundRect, xRadius: capsuleRadius, yRadius: capsuleRadius)
            badgeFillColor.setFill()
            badgeBackgroundPath.fill()

            let textOrigin = CGPoint(x: badgeBackgroundRect.minX + (badgeBackgroundSize.width - textRenderSize.width) / 2, y: -((badgeBackgroundSize.height - textRenderSize.height) / 2))
            let textRect = CGRect(origin: textOrigin, size: canvasSize)
            text.draw(in: textRect, withAttributes: badgeTextAttributes)

            return true
        }
        return targetImage
    }

    func grayOut() -> NSImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        guard let grayscale = bitmap.converting(to: .genericGray, renderingIntent: .default) else {
            return nil
        }

        let grayImage = NSImage(size: size)
        grayImage.addRepresentation(grayscale)
        return grayImage
    }

    func invert() -> NSImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIColorInvert") else {
            print("Could not create CIColorInvert filter")
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let outputImage = filter.outputImage else {
            print("Could not obtain output CIImage from filter")
            return nil
        }

        let context = CIContext(options: nil)
        guard let cgOutImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgOutImage, size: size)
    }
}

extension NSBitmapImageRep {
    var png: Data? { representation(using: .png, properties: [:]) }
}
