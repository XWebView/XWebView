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

XWVPlugin = function(channel) {
    this.$channel = channel;
}

XWVPlugin.create = function(channel, namespace, base) {
    if (!webkit.messageHandlers[channel])
        return null;  // channel has not established

    // check namespace
    var obj = window;
    var ns = namespace.split('.');
    var last = ns.pop();
    ns.forEach(function(p){
        if (!obj[p]) obj[p] = {};
        obj = obj[p];
    });
    if (obj[last] instanceof this)
        return null;  // channel is occupied

    if (base instanceof Function && base.name != "") {
        obj[last] = base;
        base.$lastInstID = 1;
        base.prototype = new this(channel);
        base.prototype.constructor = base;
        base.destroy = function() {
            for (var i in this) {
                if (!isNaN(Number(i)))
                    this[i].destroy();
            }
            this.prototype.destroy();
        }
        return base.prototype;
    } else {
        if (base instanceof Object)
            this.aggregate(base, this, [channel]);
        else
            base = new this(channel);
        return obj[last] = base;
    }
}

XWVPlugin.defineProperty = function(obj, prop, value, writable) {
    var desc = {
        'configurable': false,
        'enumerable': true,
        'get': function() { return this.$properties[prop]; }
    }
    if (writable) {
        desc.set = function(v) {
            this.$invokeNative(prop, v);
            this.$properties[prop] = v;
        }
    }
    if (!obj.$properties)  obj.$properties = {};
    obj.$properties[prop] = value;
    Object.defineProperty(obj, prop, desc);
}

XWVPlugin.aggregate = function(obj, constructor, args) {
    var ctor = constructor;
    if (typeof(ctor) === 'string' || ctor instanceof String)
        ctor = this[ctor];
    if (!(ctor instanceof Function) || !(ctor.prototype instanceof Object))
        return;
    function clone(obj) {
        var copy = {};
        var keys = Object.getOwnPropertyNames(obj);
        for (var i in keys)
            copy[keys[i]] = obj[keys[i]];
        return copy;
    }
    var p = clone(ctor.prototype);
    p.__proto__ = Object.getPrototypeOf(obj);
    obj.__proto__ = p;
    ctor.apply(obj, args);
}

XWVPlugin.prototype = {
    $retainIfNeeded: function(obj) {
        function isSerializable(obj) {
            if (!(obj instanceof Object))
                return true;
            if (obj instanceof Function)
                return false;
            // TODO: support other types of object (eg. ArrayBuffer)
            // See WebCode::CloneSerializer::dumpIfTerminal() in
            // Source/WebCore/bindings/js/SerializedScriptValue.cpp
            if (obj instanceof Boolean ||
                obj instanceof Date ||
                obj instanceof Number ||
                obj instanceof RegExp ||
                obj instanceof String)
                return true;
            for (var p of Object.getOwnPropertyNames(obj))
                if (!arguments.callee(obj[p]))
                    return false;
            return true;
        }

        // Only serializable objects can be passed by value.
        return isSerializable(obj) ? obj : this.$retainObject(obj);
    },
    $retainObject: function(obj) {
        if (!this.hasOwnProperty('$references')) {
            this.$lastRefID = 1;
            this.$references = [];
        }

        while (this.$references[this.$lastRefID] != undefined)
            ++this.$lastRefID;
        this.$references[this.$lastRefID] = obj;

        return {
            '$sig': 0x5857574F,
            '$ref': this.$lastRefID++
        }
    },
    $releaseObject: function(refid) {
        delete this.$references[refid];
        this.$lastRefID = refid;
    },

    $invokeNative: function(name, args) {
        if (typeof(name) != 'string' && !(name instanceof String)) {
            console.error('Invalid invocation');
            return;
        }

        var channel = this.$channel;
        var target = this.$instanceID;
        var operand = null;

        if (name == '+') {
            // Create instance
            var ctor = this.constructor;
            while (ctor[ctor.$lastInstID] != undefined)
                ++ctor.$lastInstID;
            target = this.$instanceID = ctor.$lastInstID;
            ctor[target] = this;
            // Setup properties
            this.$properties = {};
            for (var i in this.__proto__.$properties)
                this.$properties[i] = this.__proto__.$properties[i];
        } else if (name == '-') {
            // Destroy instance
            this.constructor.$lastInstID = target;
            delete this.constructor[target];
            // Cleanup object
            delete this.$channel;
            delete this.$properties;
            delete this.$references;
            delete this.$instanceID;
            delete this.$lastRefID;
            this.__proto__ = Object.getPrototypeOf(this.__proto__);
        }

        if (this.$properties && this.$properties.hasOwnProperty(name)) {
            // Update property
            operand = this.$retainIfNeeded(args);
        } else if (this[name] instanceof Function || name == '+') {
            // Invoke method
            operand = [];
            args.forEach(function(v, i, a) {
                operand[i] = this.$retainIfNeeded(v);
            }, this);
        }
        webkit.messageHandlers[channel].postMessage({
            '$opcode': name,
            '$operand': operand,
            '$target': target
        });
    },
    destroy: function() {
        this.$invokeNative('-');
    }
}

// A simple implementation of EventTarget interface
XWVPlugin.EventTarget = function() {
    this.$listeners = {}
}

XWVPlugin.EventTarget.prototype = {
    addEventListener: function(type, listener, capture) {
        if (!listener)  return;

        var list = this.$listeners[type];
        if (!list) {
            list = new Array();
            this.$listeners[type] = list;
        } else if (list.indexOf(listener) >= 0) {
            return;
        }
        list.push(listener);
    },
    removeEventListener: function(type, listener, capture) {
        var list = this.$listeners[type];
        if (!list || !listener)
            return;
        var i = list.indexOf(listener);
        if (i >= 0)
            list.splice(i, 1);
    },
    dispatchEvent: function(event) {
        var list = this.$listeners[event.type];
        if (!list)  return;
        for (var i = 0; i < list.length; ++i) {
            var func = list[i];
            if (!(func instanceof Function))
                func = func.handleEvent;
            func(event);
        }
        return true;
    }
}
