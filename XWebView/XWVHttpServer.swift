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
#if os(iOS)
import UIKit
import MobileCoreServices
#else
import CoreServices
#endif

class XWVHttpServer : NSObject {
    private var socket: CFSocketRef!
    private var connections = Set<XWVHttpConnection>()
    private let overlays: [NSURL]
    private(set) var port: in_port_t = 0

    var rootURL: NSURL {
        return overlays.last!
    }
    var overlayURLs: [NSURL] {
        return overlays.dropLast().reverse()
    }

    init(rootURL: NSURL, overlayURLs: [NSURL]?) {
        precondition(rootURL.fileURL)
        var overlays = [rootURL]
        overlayURLs?.forEach {
            precondition($0.fileURL)
            overlays.append($0)
        }
        self.overlays = overlays.reverse()
        super.init()
    }
    convenience init(rootURL: NSURL) {
        self.init(rootURL: rootURL, overlayURLs: nil)
    }
    deinit {
        stop()
    }

    private func listenOnPort(port: in_port_t) -> Bool {
        guard socket == nil else { return false }

        let info = UnsafeMutablePointer<Void>(unsafeAddressOf(self))
        var context = CFSocketContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
        let callbackType = CFSocketCallBackType.AcceptCallBack.rawValue
        socket = CFSocketCreate(nil, PF_INET, SOCK_STREAM, 0, callbackType, ServerAcceptCallBack, &context)
        guard socket != nil else {
            log("!Failed to create socket")
            return false
        }

        var yes = UInt32(1)
        setsockopt(CFSocketGetNative(socket), SOL_SOCKET, SO_REUSEADDR, &yes, UInt32(sizeof(UInt32)))

        var sockaddr = sockaddr_in(
            sin_len: UInt8(sizeof(sockaddr_in)),
            sin_family: UInt8(AF_INET),
            sin_port: port.bigEndian,
            sin_addr: in_addr(s_addr: UInt32(0x7f000001).bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        let data = NSData(bytes: &sockaddr, length: sizeof(sockaddr_in))
        guard CFSocketSetAddress(socket, data) == CFSocketError.Success else {
            log("!Failed to listen on port \(port) \(String(UTF8String: strerror(errno))!)")
            CFSocketInvalidate(socket)
            return false
        }

        let serverLoop = #selector(XWVHttpServer.serverLoop(_:))
        NSThread.detachNewThreadSelector(serverLoop, toTarget: self, withObject: nil)
        return true
    }

    private func close() {
        // Close all connections.
        connections.forEach { $0.close() }
        connections.removeAll()

        // Close server socket.
        if socket != nil {
            CFSocketInvalidate(socket)
            socket = nil
        }
    }

    func start(port: in_port_t = 0) -> Bool {
        if port == 0 {
            // Try to find a random port in registered ports range
            for _ in 0 ..< 100 {
                let port = in_port_t(arc4random() % (49152 - 1024) + 1024)
                if listenOnPort(port) {
                    self.port = port
                    break
                }
            }
        } else if listenOnPort(port) {
            self.port = port
        }
        guard self.port != 0 else { return false }

        #if os(iOS)
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(XWVHttpServer.suspend(_:)),
                                                         name: UIApplicationDidEnterBackgroundNotification,
                                                         object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(XWVHttpServer.resume(_:)),
                                                         name: UIApplicationWillEnterForegroundNotification,
                                                         object: nil)
        #endif
        return true
    }

    func stop() {
        #if os(iOS)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: nil)
        #endif
        port = 0
        close()
    }

    func suspend(_: NSNotification!) {
        close()
        log("+HTTP server is suspended")
    }
    func resume(_: NSNotification!) {
        if listenOnPort(port) {
            log("+HTTP server is resumed")
        }
    }

    func serverLoop(_: AnyObject) {
        let runLoop = CFRunLoopGetCurrent()
        let source = CFSocketCreateRunLoopSource(nil, socket, 0)
        CFRunLoopAddSource(runLoop, source, kCFRunLoopCommonModes)
        CFRunLoopRun()
    }
}

extension XWVHttpServer : XWVHttpConnectionDelegate {
    func didOpenConnection(connection: XWVHttpConnection) {
        connections.insert(connection)
    }
    func didCloseConnection(connection: XWVHttpConnection) {
        connections.remove(connection)
    }

    func handleRequest(request: NSURLRequest) -> NSHTTPURLResponse {
        // Date format, see section 7.1.1.1 of RFC7231
        let dateFormatter = NSDateFormatter()
        dateFormatter.locale = NSLocale(localeIdentifier: "en_US")
        dateFormatter.timeZone = NSTimeZone(name: "GMT")
        dateFormatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"

        var headers: [String: String] = ["Date": dateFormatter.stringFromDate(NSDate())]
        var statusCode = 500
        var fileURL = NSURL()
        if request.URL == nil {
            // Bad request
            statusCode = 400
            log("?Bad request")
        } else if request.HTTPMethod == "GET" || request.HTTPMethod == "HEAD" {
            let fileManager = NSFileManager.defaultManager()
            let relativePath = String(request.URL!.path!.characters.dropFirst())
            for baseURL in overlays {
                var isDirectory: ObjCBool = false
                var url = NSURL(string: relativePath, relativeToURL: baseURL)!
                if fileManager.fileExistsAtPath(url.path!, isDirectory: &isDirectory) {
                    if isDirectory {
                        url = url.URLByAppendingPathComponent("index.html")
                    }
                    if fileManager.isReadableFileAtPath(url.path!) {
                        fileURL = url
                        break
                    }
                }
            }
            if fileURL.path != nil {
                statusCode = 200
                let attrs = try! fileManager.attributesOfItemAtPath(fileURL.path!)
                headers["Content-Type"] = getMIMETypeByExtension(fileURL.pathExtension!)
                headers["Content-Length"] = String(attrs[NSFileSize]!)
                headers["Last-Modified"] = dateFormatter.stringFromDate(attrs[NSFileModificationDate] as! NSDate)
                log("+\(request.HTTPMethod!) \(fileURL.path!)")
            } else {
                // Not found
                statusCode = 404
                fileURL = NSURL()
                log("-File NOT found for URL \(request.URL!)")
            }
        } else {
            // Method not allowed
            statusCode = 405
            headers["Allow"] = "GET HEAD"
        }
        if statusCode != 200 {
            headers["Content-Length"] = "0"
        }
        return NSHTTPURLResponse(URL: fileURL, statusCode: statusCode, HTTPVersion: "HTTP/1.1", headerFields: headers)!
    }
}

private func ServerAcceptCallBack(socket: CFSocket!, type: CFSocketCallBackType, address: CFData!, data:UnsafePointer<Void>, info: UnsafeMutablePointer<Void>) {
    let server = unsafeBitCast(info, XWVHttpServer.self)
    let handle = UnsafePointer<CFSocketNativeHandle>(data).memory
    assert(socket === server.socket && type == CFSocketCallBackType.AcceptCallBack)

    let connection = XWVHttpConnection(handle: handle, delegate: server)
    connection.open()
}

private var mimeTypeCache = [
    // MIME types which are unknown by system.
    "css" : "text/css"
]
private func getMIMETypeByExtension(extensionName: String) -> String {
    var type: String! = mimeTypeCache[extensionName]
    if type == nil {
        // Get MIME type through system-declared uniform type identifier.
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, extensionName, nil),
            let mt = UTTypeCopyPreferredTagWithClass(uti.takeRetainedValue(), kUTTagClassMIMEType) {
                type = mt.takeRetainedValue() as String
        } else {
            // Fall back to binary stream.
            type = "application/octet-stream"
        }
        mimeTypeCache[extensionName] = type
    }
    if type.lowercaseString.hasPrefix("text/") {
        // Assume text resource is UTF-8 encoding
        return type + "; charset=utf-8"
    }
    return type
}
