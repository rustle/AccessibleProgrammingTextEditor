//
//  DocumentWindowController.swift
//  CodeEdit
//
//  Created by Doug Russell on 5/16/18.
//  Copyright © 2018 Doug Russell. All rights reserved.
//

import Cocoa

class DocumentWindowController : NSWindowController, NSLayoutManagerDelegate {
    @IBOutlet var scrollView: NSScrollView?
    @IBOutlet var textView: TextView?
    override func windowDidLoad() {
        super.windowDidLoad()
        guard let document = document as? Document else {
            return
        }
        guard let textView = textView else {
            return
        }
        guard let layoutManager = textView.layoutManager else {
            return
        }
        document.textStorage.addLayoutManager(layoutManager)
        textView.font = NSFont(name: "Menlo", size: 36.0)
        textView.setUpLineNumberRulerView()
    }
}
