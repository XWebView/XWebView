/*
 Copyright 2015 XWebView

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

import Foundation
import WebKit

class XWVUserScript {
    weak var webView: WKWebView?
    let script: WKUserScript
    let cleanup: String?

    init(webView: WKWebView, script: WKUserScript, cleanup: String? = nil) {
        self.webView = webView
        self.script = script
        self.cleanup = cleanup
        inject()
    }
    convenience init(webView: WKWebView, script: WKUserScript, namespace: String) {
        self.init(webView: webView, script: script, cleanup: "delete \(namespace)")
    }
    deinit {
        eject()
    }

    private func inject() {
        // add to userContentController
        webView!.configuration.userContentController.addUserScript(script)

        // inject into current context
        if webView!.URL != nil {
            webView!.evaluateJavaScript(script.source) {
                (_, error)->Void in
                if let err = error {
                    println("ERROR: Inject user script in context.\n\(err)")
                }
            }
        }
    }
    private func eject() {
        if let controller = webView?.configuration.userContentController {
            // remove from userContentController
            let userScripts = filter(controller.userScripts) { $0 !== self.script }
            controller.removeAllUserScripts()
            for script in userScripts {
                controller.addUserScript(script as! WKUserScript)
            }
        }
        if let webView = webView where webView.URL != nil && cleanup != nil {
            // clean up in current context
            webView.evaluateJavaScript(cleanup!, completionHandler: nil)
        }
    }
}
