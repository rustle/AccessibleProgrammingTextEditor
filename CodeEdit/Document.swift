//
//  Document.swift
//  CodeEdit
//
//  Created by Doug Russell on 5/16/18.
//  Copyright © 2018 Doug Russell. All rights reserved.
//

import Cocoa

class Document : NSDocument {
    var textStorage = NSTextStorage()
    override func makeWindowControllers() {
        guard windowControllers.count == 0 else {
            return
        }
        addWindowController(DocumentWindowController(windowNibName: NSNib.Name("DocumentWindow")))
    }
    override func read(from url: URL, ofType typeName: String) throws {
        textStorage.mutableString.setString("")
        repeat {
            do {
                textStorage.beginEditing()
                try textStorage.read(from: url, options: [:], documentAttributes: nil, error: ())
                textStorage.endEditing()
                break
            } catch {
                continue
            }
        } while true
    }
}

