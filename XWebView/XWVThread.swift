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

class XWVThread : NSThread {
    var timer: NSTimer!

    deinit {
        cancel()
    }

    override func main() {
        do {
            switch  Int(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 60, Boolean(1))) {
                case kCFRunLoopRunFinished:
                    // No input source, add a timer (which will never fire) to avoid spinning.
                    let interval = NSDate.distantFuture().timeIntervalSinceNow
                    timer = NSTimer(timeInterval: interval, target: self, selector: Selector(), userInfo: nil, repeats: false)
                    NSRunLoop.currentRunLoop().addTimer(timer, forMode: NSDefaultRunLoopMode)
                case kCFRunLoopRunHandledSource:
                    // Remove the timer because run loop has had input source
                    if timer != nil {
                        timer.invalidate()
                        timer = nil
                    }
                case kCFRunLoopRunStopped:
                    cancel()
                default:
                    break
            }
        } while !cancelled
    }
}
