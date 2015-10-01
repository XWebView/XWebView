//
//  SamplePlugin.swift
//  XWebView
//
//  Created by Fernando Martinez on 9/28/15.
//  Copyright © 2015 XWebView. All rights reserved.
//

import UIKit
import WebKit

class SamplePlugin: NSObject {
    func receiveMessage(message: String) {
        dispatch_async(dispatch_get_main_queue(), {
            UIAlertView(
                title: "New Message",
                message: message,
                delegate: nil,
                cancelButtonTitle: "OK"
            ).show()
        })
    }
}
