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

let UseScannerForLineCount = true
let SupportVisibleChildren = false

public protocol LineNumberTextView : class {
    var lineNumberRulerView: LineNumberRulerView? { get set }
}

public extension LineNumberTextView where Self : NSTextView {
    public func setUpLineNumberRulerView() {
        guard let scrollView = enclosingScrollView else {
            return
        }
        lineNumberRulerView = LineNumberRulerView(textView: self)
        scrollView.verticalRulerView = lineNumberRulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }
}

fileprivate extension Int {
    func lnrv_numberOfDigits() -> Int {
        if self == 0 {
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
    private var _accessibilityChildren = [LNRVAccessibilityText]()
#if SupportVisibleChildren
    private var _accessibilityVisibleChildren = [LNRVAccessibilityText]()
#endif
    private var _lineCount: Int = 0 {
        didSet {
            ruleThickness = font.boundingRect(forCGGlyph: 36).width * CGFloat(_lineCount.lnrv_numberOfDigits() + 1)
            needsDisplay = true
        }
    }
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    private let dash = NSLocalizedString("Dash", tableName: "LineNumberRulerView", bundle: Bundle.main, value: "ERROR", comment: "")
    var lineCount: Int {
        get {
            return _lineCount
        }
        set {
            if newValue != _lineCount {
                _lineCount = newValue
            }
        }
    }
    public func common(textView: NSTextView) {
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(lnrv_frameDidChange), name: NSView.frameDidChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(lnrv_textDidChange), name: NSText.didChangeNotification, object: textView)
        ruleThickness = font.boundingRect(forCGGlyph: 36).width * 3.0
    }
    public init(textView: NSTextView) {
        font = textView.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        super.init(scrollView: textView.enclosingScrollView!, orientation: NSRulerView.Orientation.verticalRuler)
        self.clientView = textView
        common(textView: textView)
    }
    public required init(coder: NSCoder) {
        font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        super.init(coder: coder)
        guard let textView = self.clientView as? NSTextView else {
            fatalError()
        }
        font = textView.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        common(textView: textView)
    }
    @objc func lnrv_frameDidChange(notification: NSNotification) {
        needsDisplay = true
    }
    @objc func lnrv_textDidChange(notification: NSNotification) {
        needsDisplay = true
    }
    private enum Error : Swift.Error {
        case unsupportedClientView
        case nilLayoutManager
    }
    private enum LineNumber {
        case line(Int)
        case continuation(Int, Int)
    }
    private enum LineVisibility {
        case visible
        case hidden
    }
    private func countLinesUpTo(string: String, index: Int) -> Int {
#if UseScannerForLineCount
        if index == 0 {
            return 1
        }
        var lineCount = 1
        let scanner = Scanner(string: string)
        scanner.charactersToBeSkipped = CharacterSet()
        let newLines = CharacterSet.newlines
        while !scanner.isAtEnd && scanner.scanLocation <= index {
            // scan til we find a newline
            if scanner.scanUpToCharacters(from: newLines, into: nil) {
                lineCount += 1
                continue
            }
            // Found a run of new lines
            var string: NSString?
            if scanner.scanCharacters(from: newLines, into: &string) {
                let count = string!.length
                // If the run passes the index, only count the new lines between the previous
                // scan location and index
                if scanner.scanLocation > index {
                    lineCount += (index - (scanner.scanLocation - count))
                } else {
                    lineCount += count
                }
                continue
            }
            break
        }
        return lineCount
#else
        let newLineRegex = try! NSRegularExpression(pattern: "\n", options: [])
        return newLineRegex.numberOfMatches(in: string, options: [], range: NSMakeRange(0, index)) + 1
#endif
    }
    private func enumerateLines(visible: Bool = true, work: (LineNumber, LineVisibility, NSRect) -> Void) throws -> Int {
        guard let textView = self.clientView as? NSTextView else {
            throw LineNumberRulerView.Error.unsupportedClientView
        }
        guard let layoutManager = textView.layoutManager else {
            throw LineNumberRulerView.Error.nilLayoutManager
        }
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textView.textContainer!)
        let firstVisibleGlyphCharacterIndex = layoutManager.characterIndexForGlyph(at: visibleGlyphRange.location)
        let firstVisibleLineNumber = countLinesUpTo(string: textView.string, index: firstVisibleGlyphCharacterIndex)
        if visible {
            var lineNumber = firstVisibleLineNumber
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
                        work(.continuation(lineNumber, glyphLineCount), .visible, lineRect)
                    } else {
                        work(.line(lineNumber), .visible, lineRect)
                    }
                    // Move to next glyph line
                    glyphLineCount += 1
                    glyphIndexForGlyphLine = NSMaxRange(effectiveRange)
                }
                glyphIndexForStringLine = NSMaxRange(glyphRangeForStringLine)
                lineNumber += 1
            }
            // Line number for the extra line at the end of the text
            if layoutManager.extraLineFragmentTextContainer != nil {
                work(.line(lineNumber), .visible, layoutManager.extraLineFragmentRect)
            }
            return lineNumber
        } else {
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
                        work(.continuation(lineNumber, glyphLineCount), .visible, lineRect)
                    } else {
                        work(.line(lineNumber), .visible, lineRect)
                    }
                    // Move to next glyph line
                    glyphLineCount += 1
                    glyphIndexForGlyphLine = NSMaxRange(effectiveRange)
                }
                glyphIndexForStringLine = NSMaxRange(glyphRangeForStringLine)
                lineNumber += 1
            }
            // Line number for the extra line at the end of the text
            if layoutManager.extraLineFragmentTextContainer != nil {
                work(.line(lineNumber), .visible, layoutManager.extraLineFragmentRect)
            }
            return lineNumber
        }
    }
    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.clientView as? NSTextView else {
            return
        }
        let relativePoint = self.convert(NSZeroPoint, from: textView)
        let lineNumberAttributes = [NSAttributedStringKey.font: textView.font!, NSAttributedStringKey.foregroundColor: NSColor.gray] as [NSAttributedStringKey : Any]
        let rule = ruleThickness - 5.0
        do {
            _ = try enumerateLines { lineNumber, _, lineRect in
                let lineNumberString: String
                switch lineNumber {
                case .line(let value):
                    if let value = formatter.string(from: value as NSNumber) {
                        lineNumberString = value
                    } else {
                        lineNumberString = "\(value)"
                    }
                case .continuation(_):
                    lineNumberString = dash
                }
                let y = lineRect.minY
                let attString = NSAttributedString(string: lineNumberString, attributes: lineNumberAttributes)
                let x = rule - attString.size().width
                attString.draw(at: NSPoint(x: x, y: relativePoint.y + y))
            }
        } catch {
            
        }
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
    // This has to use the deprecated methods because that's the only way to specify an
    // action name that is different from the action description
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

fileprivate extension Array {
    func lnrv_slice(index: Int, maxCount: Int) -> Array<Element> {
        let count: Int
        if index + maxCount > self.count {
            count = self.count
        } else {
            count = index + maxCount
        }
        return Array(self[index..<count])
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
        return NSLocalizedString("AccessibilityRoleDescription", tableName: "LineNumberRulerView", bundle: Bundle.main, value: "ERROR", comment: "")
    }
    public override func accessibilityLabel() -> String? {
        return NSLocalizedString("AccessibilityLabel", tableName: "LineNumberRulerView", bundle: Bundle.main, value: "ERROR", comment: "")
    }
    // TODO: Build accessibility children incrementally
    private func updateAccessibilityChildren() {
        var reuseQueue = _accessibilityChildren
        _accessibilityChildren.removeAll()
#if SupportVisibleChildren
        _accessibilityVisibleChildren.removeAll()
#endif
        let lineNumberFormat = NSLocalizedString("AccessibilityLineFormatterWithPrefix", tableName: "LineNumberRulerView", bundle: Bundle.main, value: "ERROR", comment: "")
        let lineNumberContinuationFormat = NSLocalizedString("AccessibilityLineContinuationFormatterWithPrefix", tableName: "LineNumberRulerView", bundle: Bundle.main, value: "ERROR", comment: "")
        func dequeue(frame: NSRect, parent: AnyObject) -> LNRVAccessibilityText {
            let text: LNRVAccessibilityText
            if reuseQueue.count > 0 {
                text = reuseQueue.removeLast()
                text.parent = parent
                text.frame = frame
            } else {
                text = LNRVAccessibilityText(frame: frame, parent: parent)
            }
            return text
        }
        func numberString(_ value: Int) -> String {
            guard let numberString = formatter.string(from: value as NSNumber) else {
                return "\(value)"
            }
            return numberString
        }
        do {
            var accessibilityChildren = [LNRVAccessibilityText]()
#if SupportVisibleChildren
            var accessibilityVisibleChildren = [LNRVAccessibilityText]()
#endif
            accessibilityChildren.reserveCapacity(reuseQueue.capacity)
            let rule = ruleThickness
            lineCount = try enumerateLines { lineNumber, visibility, lineRect in
                var elementRect = lineRect
                elementRect.size.width = rule
                let text = dequeue(frame: elementRect, parent: self)
                text.index = accessibilityChildren.count
                let lineNumberString: String
                switch lineNumber {
                case .line(let value):
                    lineNumberString = String(format: lineNumberFormat, numberString(value))
                case .continuation(let lineNumber, let continuations):
                    lineNumberString = String(format: lineNumberContinuationFormat, numberString(lineNumber), numberString(continuations + 1))
                }
                text.text = lineNumberString
                switch visibility {
                case .visible:
#if SupportVisibleChildren
                    accessibilityVisibleChildren.append(text)
#else
                    break
#endif
                case .hidden:
                    break
                }
                accessibilityChildren.append(text)
            }
            _accessibilityChildren.append(contentsOf: accessibilityChildren)
#if SupportVisibleChildren
            _accessibilityVisibleChildren.append(contentsOf: accessibilityVisibleChildren)
#endif
            accessibilityChildrenDirty = false
        } catch {
            
        }
    }
    public override func accessibilityChildren() -> [Any]? {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        return _accessibilityChildren
    }
#if SupportVisibleChildren
    public override func accessibilityVisibleChildren() -> [Any]? {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        return _accessibilityVisibleChildren
    }
#endif
    public override func accessibilityIndex(ofChild child: Any) -> Int {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        guard let element = child as? LNRVAccessibilityText else {
            return NSNotFound
        }
        guard let index =  _accessibilityChildren.index(of: element) else {
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
            return _accessibilityChildren.count
#if SupportVisibleChildren
        case .visibleChildren:
            return _accessibilityVisibleChildren.count
#endif
        default:
            return 0
        }
    }
    public override func accessibilityArrayAttributeValues(_ attribute: NSAccessibilityAttributeName, index: Int, maxCount: Int) -> [Any] {
        if accessibilityChildrenDirty {
            updateAccessibilityChildren()
        }
        switch attribute {
        case .children:
            return _accessibilityChildren.lnrv_slice(index: index, maxCount: maxCount)
#if SupportVisibleChildren
        case .visibleChildren:
            return _accessibilityVisibleChildren.lnrv_slice(index: index, maxCount: maxCount)
#endif
        default:
            return []
        }
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
