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
        guard let webView = webView else { return }

        // add to userContentController
        webView.configuration.userContentController.addUserScript(script)

        // inject into current context
        if webView.url != nil {
            webView.evaluateJavaScript(script.source) {
                if let error = $1 {
                    log("!Failed to inject script. \(error)")
                }
            }
        }
    }
    private func eject() {
        guard let webView = webView else { return }

        // remove from userContentController
        let controller = webView.configuration.userContentController
        let userScripts = controller.userScripts
        controller.removeAllUserScripts()
        userScripts.forEach {
            if $0 != self.script { controller.addUserScript($0) }
        }

        if webView.url != nil, let cleanup = cleanup {
            // clean up in current context
            DispatchQueue.main.async {
                webView.evaluateJavaScript(cleanup, completionHandler: nil)
            }
        }
    }
}
