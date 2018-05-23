//
//  TextView.swift
//  CodeEdit
//
//  Created by Doug Russell on 5/22/18.
//  Copyright © 2018 Doug Russell. All rights reserved.
//

import Cocoa

class TextView : NSTextView, LineNumberTextView {
    var lineNumberRulerView: LineNumberRulerView?
}
