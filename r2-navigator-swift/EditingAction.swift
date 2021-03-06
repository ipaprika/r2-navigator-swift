//
//  EditingAction.swift
//  r2-navigator-swift
//
//  Created by Aferdita Muriqi, Mickaël Menu on 03.04.19.
//
//  Copyright 2019 Readium Foundation. All rights reserved.
//  Use of this source code is governed by a BSD-style license which is detailed
//  in the LICENSE file present in the project repository where this source code is maintained.
//

import Foundation
import UIKit
import R2Shared

public enum EditingAction: String {
    case copy = "copy:"
    case share = "_share:"
    case lookup = "_lookup:"
    
    public static var defaultActions: [EditingAction] {
        return [copy, share, lookup]
    }
}


protocol EditingActionsControllerDelegate: AnyObject {
    
    func editingActionsDidPreventCopy(_ editingActions: EditingActionsController)
    
}


/// Handles the authorization and check of editing actions.
final class EditingActionsController {
    
    public weak var delegate: EditingActionsControllerDelegate?
    
    private let actions: [EditingAction]
    private let license: DRMLicense?
    private var needsCopyCheck = false

    init(actions: [EditingAction], license: DRMLicense?) {
        self.actions = actions
        self.license = license
        
        NotificationCenter.default.addObserver(self, selector: #selector(pasteboardDidChange), name: UIPasteboard.changedNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func canPerformAction(_ action: Selector) -> Bool {
        for editingAction in self.actions {
            if action == Selector(editingAction.rawValue) {
                return true
            }
        }
        return false
    }
    
    
    // MARK: - Copy
    
    /// Called when the user attempt to copy the selection. If true is returned, then you may allow the copy.
    func requestCopy() -> Bool {
        guard license?.canCopy ?? true else {
            delegate?.editingActionsDidPreventCopy(self)
            return false
        }
        
        // We rely on UIPasteboardChanged to notify the copy to the delegate because UIKit sets the selection in the UIPasteboard asynchronously
        needsCopyCheck = true
        return true
    }
    
    @objc private func pasteboardDidChange() {
        guard needsCopyCheck else {
            return
        }
        needsCopyCheck = false
        
        let pasteboard = UIPasteboard.general
        
        guard let license = license else {
            return
        }
        guard license.canCopy else {
            pasteboard.items = []
            return
        }
        guard let text = pasteboard.string else {
            return
        }
        
        let authorizedText = license.copy(text)
        if authorizedText != text {
            // We overwrite the pasteboard only if the authorized text is different to avoid erasing formatting
            pasteboard.string = authorizedText
        }
    }
    
}
