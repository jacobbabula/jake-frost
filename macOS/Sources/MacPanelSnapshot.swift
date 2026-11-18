import AppKit

/// AppKit paints a window's backing separately from its content view.
@MainActor enum MacPanelSnapshot {
    static func png(_ panel: NSWindow) -> Data? {
        guard let content=panel.contentView else {return nil}
        content.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        guard let layer=content.bitmapImageRepForCachingDisplay(in:content.bounds) else {return nil}
        content.cacheDisplay(in:content.bounds,to:layer)
        guard let image=layer.cgImage, let space=CGColorSpace(name:CGColorSpace.sRGB),
              let context=CGContext(data:nil,width:image.width,height:image.height,
                                    bitsPerComponent:8,bytesPerRow:0,space:space,
                                    bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {return nil}
        let rect=CGRect(x:0,y:0,width:image.width,height:image.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect:rect).fill()
            panel.backgroundColor.setFill()
            NSBezierPath(rect:rect).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        context.draw(image,in:rect)
        guard let result=context.makeImage(),
              let png=NSBitmapImageRep(cgImage:result).representation(using:.png,properties:[:]),
              let decoded=NSBitmapImageRep(data:png),
              decoded.colorAt(x:1,y:1)?.alphaComponent == 1 else {return nil}
        return png
    }
}
