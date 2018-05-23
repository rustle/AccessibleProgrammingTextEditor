//
//  DocumentController.swift
//  CodeEdit
//
//  Created by Doug Russell on 5/16/18.
//  Copyright © 2018 Doug Russell. All rights reserved.
//

import Cocoa

class DocumentController : NSDocumentController {
    enum Error : Swift.Error {
        case typeMismatch
    }
    override func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        guard let doc = try super.openUntitledDocumentAndDisplay(displayDocument) as? Document else {
            throw DocumentController.Error.typeMismatch
        }
        return doc
    }
}
