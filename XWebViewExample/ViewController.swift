//
//  ViewController.swift
//  XWebViewSample
//
//  Created by Fernando Martinez on 9/28/15.
//  Copyright © 2015 XWebView. All rights reserved.
//

import UIKit
import WebKit
import XWebView

class ViewController: UIViewController {

    @IBOutlet weak var messageTextField: UITextField!
    @IBOutlet weak var contentView: UIView!
    var webView: WKWebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView = WKWebView(frame: contentView.frame)
        setupJsPlugin()
        contentView.addSubview(webView!)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        loadPage()
    }
    
    func setupJsPlugin() {
        let plugin = SamplePlugin()
        webView.loadPlugin(plugin, namespace: "SamplePlugin")
    }
    
    func loadPage() {
        let fileUrl = NSBundle.mainBundle().URLForResource("www/sample_page", withExtension: "html")!
        let baseUrl = NSBundle.mainBundle().resourceURL!
        webView.loadFileURL(fileUrl, allowingReadAccessToURL: baseUrl)
    }
    
    @IBAction func sendMessage(sender: UIButton!) {
        let text = messageTextField.text!
        webView.evaluateJavaScript("printMessage(\"\(text)\")", completionHandler: nil)
    }
}

