//
//  LineNumberRulerView.swift
//  LineNumber
//
//  Copyright (c) 2015 Yichi Zhang. All rights reserved.
//  Copyright (c) 2018 Doug Russell. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//

import Cocoa

public protocol LineNumberTextView : class {
    var lineNumberView: LineNumberRulerView? { get set }
}

public extension LineNumberTextView {
    public func setUpLineNumberRulerView() {
        guard let textView = self as? NSTextView else {
            return
        }
        guard let scrollView = textView.enclosingScrollView else {
            return
        }
        lineNumberView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }
}

fileprivate extension Int {
    func lnrv_numberOfDigits() -> Int {
        if (self == 0) {
            return 0;
        }
        return 1 + (self / 10).lnrv_numberOfDigits()
    }
}

public class LineNumberRulerView : NSRulerView {
    public var font: NSFont {
        didSet {
            needsDisplay = true
        }
    }
    fileprivate var accessibilityChildrenDirty = true
    private var _actualAccessibilityChildren = [LNRVAccessibilityText]()
    private var _actualLineCount: Int = 0 {
        didSet {
            ruleThickness = font.boundingRect(forCGGlyph: 36).width * CGFloat(_actualLineCount.lnrv_numberOfDigits() + 1)
            needsDisplay = true
        }
    }
    var lineCount: Int {
        get {
            return _actualLineCount
        }
        set {
            if newValue != _actualLineCount {
                _actualLineCount = newValue
            }
        }
    }
    public init(textView: NSTextView) {
        font = textView.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        super.init(scrollView: textView.enclosingScrollView!, orientation: NSRulerView.Orientation.verticalRuler)
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(lnrv_frameDidChange), name: NSView.frameDidChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(lnrv_textDidChange), name: NSText.didChangeNotification, object: textView)
        self.clientView = textView
        if let font = textView.font {
            ruleThickness = font.boundingRect(forCGGlyph: 36).width * 3.0
        } else {
            ruleThickness = 40.0
        }
    }
    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    @objc func lnrv_frameDidChange(notification: NSNotification) {
        needsDisplay = true
    }
    @objc func lnrv_textDidChange(notification: NSNotification) {
        needsDisplay = true
    }
    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.clientView as? NSTextView else {
            return
        }
        guard let layoutManager = textView.layoutManager else {
            return
        }
        let relativePoint = self.convert(NSZeroPoint, from: textView)
        let lineNumberAttributes = [NSAttributedStringKey.font: textView.font!, NSAttributedStringKey.foregroundColor: NSColor.gray] as [NSAttributedStringKey : Any]
        
        let rule = ruleThickness - 5.0
        let drawLineNumber = { (lineNumberString:String, y:CGFloat) -> Void in
            let attString = NSAttributedString(string: lineNumberString, attributes: lineNumberAttributes)
            let x = rule - attString.size().width
            attString.draw(at: NSPoint(x: x, y: relativePoint.y + y))
        }
        
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textView.textContainer!)
        let firstVisibleGlyphCharacterIndex = layoutManager.characterIndexForGlyph(at: visibleGlyphRange.location)
        
        let newLineRegex = try! NSRegularExpression(pattern: "\n", options: [])
        // The line number for the first visible line
        var lineNumber = newLineRegex.numberOfMatches(in: textView.string, options: [], range: NSMakeRange(0, firstVisibleGlyphCharacterIndex)) + 1
        
        var glyphIndexForStringLine = visibleGlyphRange.location
        
        // Go through each line in the string.
        while glyphIndexForStringLine < NSMaxRange(visibleGlyphRange) {
            
            // Range of current line in the string.
            let characterRangeForStringLine = (textView.string as NSString).lineRange(for: NSMakeRange(layoutManager.characterIndexForGlyph(at: glyphIndexForStringLine), 0))
            let glyphRangeForStringLine = layoutManager.glyphRange(forCharacterRange: characterRangeForStringLine, actualCharacterRange: nil)
            
            var glyphIndexForGlyphLine = glyphIndexForStringLine
            var glyphLineCount = 0
            
            while glyphIndexForGlyphLine < NSMaxRange(glyphRangeForStringLine) {
                
                // See if the current line in the string spread across
                // several lines of glyphs
                var effectiveRange = NSMakeRange(0, 0)
                
                // Range of current "line of glyphs". If a line is wrapped,
                // then it will have more than one "line of glyphs"
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndexForGlyphLine, effectiveRange: &effectiveRange, withoutAdditionalLayout: true)
                
                if glyphLineCount > 0 {
                    drawLineNumber("-", lineRect.minY)
                } else {
                    drawLineNumber("\(lineNumber)", lineRect.minY)
                }
                
                // Move to next glyph line
                glyphLineCount += 1
                glyphIndexForGlyphLine = NSMaxRange(effectiveRange)
            }
            
            glyphIndexForStringLine = NSMaxRange(glyphRangeForStringLine)
            lineNumber += 1
        }
        
        // Draw line number for the extra line at the end of the text
        if layoutManager.extraLineFragmentTextContainer != nil {
            drawLineNumber("\(lineNumber)", layoutManager.extraLineFragmentRect.minY)
        }
        
        lineCount = lineNumber
        accessibilityChildrenDirty = true
    }
}

public class LineNumberAccessibilityElement : NSObject, NSAccessibilityElementProtocol {
    public var frame: NSRect
    public weak var parent: AnyObject?
    public init(frame: NSRect = .zero, parent: AnyObject? = nil) {
        self.frame = frame
        self.parent = parent
    }
    public func isAccessibilityElement() -> Bool {
        return true
    }
    public func accessibilityFrame() -> NSRect {
        guard let parent = parent else {
            return .zero
        }
        if let parent = parent as? NSView {
            let value = NSAccessibilityFrameInView(parent, frame)
            return value
        } else if let parent = parent as? LineNumberAccessibilityElement {
            let base = parent.accessibilityFrame()
            let frame = self.frame
            var final = base
            final.origin.x += frame.origin.x
            final.origin.y += frame.origin.y
            final.size.width += frame.size.width
            final.size.height += frame.size.height
            return final
        }
        return .zero
    }
    public func accessibilityParent() -> Any? {
        return parent
    }
    public func prepareForReuse() {
        self.parent = nil
        self.frame = .zero
    }
}

public extension NSAccessibilityActionName {
    static let scrollToVisible = NSAccessibilityActionName(rawValue: "AXScrollToVisible")
}

public class LNRVAccessibilityText : LineNumberAccessibilityElement, NSAccessibilityStaticText {
    public var index: Int?
    public var text: String?
    public func accessibilityIndex() -> Int {
        guard let index = index else {
            return NSNotFound
        }
        return index
    }
    public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        return self
    }
    public func accessibilityValue() -> String? {
        return text
    }
    public override func accessibilityActionNames() -> [NSAccessibilityActionName] {
        return [NSAccessibilityActionName.scrollToVisible]
    }
    public override func accessibilityActionDescription(_ action: NSAccessibilityActionName) -> String? {
        if action == NSAccessibilityActionName.scrollToVisible {
            return "Scroll To Visible"
        }
        return nil
    }
    public override func accessibilityPerformAction(_ action: NSAccessibilityActionName) {
        if action == NSAccessibilityActionName.scrollToVisible {
            guard let ruler = parent as? LineNumberRulerView else {
                return
            }
            guard let textView = ruler.clientView as? NSTextView else {
                return
            }
            textView.scrollToVisible(frame)
            ruler.accessibilityChildrenDirty = true
        }
    }
    public override func prepareForReuse() {
        index = nil
        text = nil
    }
}

public extension LineNumberRulerView {
    public override func isAccessibilityElement() -> Bool {
        return true
    }
    public override func accessibilityRole() -> NSAccessibilityRole? {
        return .list
    }
    public override func accessibilityRoleDescription() -> String? {
        return "ruler"
    }
    public override func accessibilityLabel() -> String? {
        return "Line Number"
    }
    // TODO: Build accessibility children incrementally
    private func updateAccessibilityChildren() {
        _actualAccessibilityChildren = []
        guard let textView = self.clientView as? NSTextView else {
            return
        }
        guard let layoutManager = textView.layoutManager else {
            return
        }
        var reuseQueue = _actualAccessibilityChildren
        var accessibilityChildren = [LNRVAccessibilityText]()
        accessibilityChildren.reserveCapacity(reuseQueue.capacity)
        let rule = ruleThickness
        let addLineNumberElement = { (lineNumberString: String, lineRect: CGRect) -> Void in
            var elementRect = lineRect
            elementRect.size.width = rule
            let text: LNRVAccessibilityText
            if reuseQueue.count > 0 {
                text = reuseQueue.removeLast()
                text.parent = self
                text.frame = elementRect
            } else {
                text = LNRVAccessibilityText(frame: elementRect, parent: self)
            }
            text.index = accessibilityChildren.count
            text.text = lineNumberString
            accessibilityChildren.append(text)
        }
        // The line number for the first visible line
        var lineNumber = 1
        var glyphIndexForStringLine = 0
        let characters = textView.textStorage!.length
        // Go through each line in the string.
        while glyphIndexForStringLine < characters {
            // Range of current line in the string.
            let characterRangeForStringLine = (textView.string as NSString).lineRange(for: NSMakeRange(layoutManager.characterIndexForGlyph(at: glyphIndexForStringLine), 0))
            let glyphRangeForStringLine = layoutManager.glyphRange(forCharacterRange: characterRangeForStringLine, actualCharacterRange: nil)
            var glyphIndexForGlyphLine = glyphIndexForStringLine
            var glyphLineCount = 0
            while glyphIndexForGlyphLine < NSMaxRange(glyphRangeForStringLine) {
                // See if the current line in the string spread across
                // several lines of glyphs
                var effectiveRange = NSMakeRange(0, 0)
                
                // Range of current "line of glyphs". If a line is wrapped,
                // then it will have more than one "line of glyphs"
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndexForGlyphLine, effectiveRange: &effectiveRange, withoutAdditionalLayout: true)
                
                if glyphLineCount > 0 {
                    addLineNumberElement("Line \(lineNumber) continued", lineRect)
                } else {
                    addLineNumberElement("Line \(lineNumber)", lineRect)
                }
                
                // Move to next glyph line
                glyphLineCount += 1
                glyphIndexForGlyphLine = NSMaxRange(effectiveRange)
            }
            glyphIndexForStringLine = NSMaxRange(glyphRangeForStringLine)
            lineNumber += 1
        }
        addLineNumberElement("Line \(lineNumber)", layoutManager.extraLineFragmentRect)
        _actualAccessibilityChildren = accessibilityChildren
        accessibilityChildrenDirty = false
    }
    public override func accessibilityChildren() -> [Any]? {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        return _actualAccessibilityChildren
    }
    public override func accessibilityIndex(ofChild child: Any) -> Int {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        guard let element = child as? LNRVAccessibilityText else {
            return NSNotFound
        }
        guard let index =  _actualAccessibilityChildren.index(of: element) else {
            return NSNotFound
        }
        return index
    }
    public override func accessibilityArrayAttributeCount(_ attribute: NSAccessibilityAttributeName) -> Int {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        switch attribute {
        case .children:
            break
        default:
            return 0
        }
        return _actualAccessibilityChildren.count
    }
    public override func accessibilityArrayAttributeValues(_ attribute: NSAccessibilityAttributeName, index: Int, maxCount: Int) -> [Any] {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        switch attribute {
        case .children:
            break
        default:
            return []
        }
        let count: Int
        if index + maxCount > _actualAccessibilityChildren.count {
            count = _actualAccessibilityChildren.count
        } else {
            count = index + maxCount
        }
        return Array(_actualAccessibilityChildren[index..<count])
    }
    public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let children = accessibilityChildren() as? [NSAccessibilityElementProtocol] else {
            return self
        }
        for child in children {
            if child.accessibilityFrame().contains(point) {
                return child
            }
        }
        return self
    }
}
