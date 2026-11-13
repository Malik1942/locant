// Locant web source lookup. Runs inside the page through the browser's own Apple Event for page
// JavaScript. It finds the DOM node Locant resolved through accessibility, then reads what React's
// development build keeps on it: the component that rendered it, that component's props, and the
// stacks React recorded where the element's JSX and the component's JSX ran. It fetches nothing and
// changes nothing; Locant maps the stack frames to source lines itself (SourceMap.swift).
// The caller replaces the placeholder on the last line with
// {"id","classes","frame":{x,y,w,h},"area":{x,y,w,h}}: the element and the page's viewport, in screen points.
(function (args) {
  'use strict';
  var out = { v: 2 };
  try {
    var node = findNode(args);
    if (!node) { out.error = 'node not found'; return JSON.stringify(out); }
    out.node = describeNode(node);
    var hit = reactFiber(node);
    if (!hit) { out.error = 'no React fiber on the node or its ancestors'; return JSON.stringify(out); }
    out.framework = 'react';
    var fiber = hit.fiber;
    if (hit.depth > 0) out.fiberDepth = hit.depth;
    var source = where(fiber);
    if (source) out.source = source;
    var owner = fiber._debugOwner || null;
    if (!owner) {
      // Production builds keep no owner: name the components above through the return chain.
      out.production = !('_debugStack' in fiber) && !('_debugSource' in fiber);
      var names = [], f = fiber.return, n = 0;
      while (f && n < 40 && names.length < 6) { var nm = componentName(f); if (nm) names.push(nm); f = f.return; n++; }
      if (names.length) out.components = names;
      return JSON.stringify(out);
    }
    var chain = [], o = owner, guard = 0;
    while (o && guard < 12) { var name = ownerName(o); if (name) chain.push(name); o = o._debugOwner || o.owner; guard++; }
    out.components = chain;
    // A server component's record is not a fiber: it has a name and an owner. Its props are what the
    // server sent, promises with React's own fields, so they are left out.
    out.props = isFiber(owner) ? propsPreview(owner.memoizedProps) : [];
    var rendered = where(owner);
    if (rendered) out.renderedAt = rendered;
    // webpack evaluates each module from a string inside a chunk; Locant finds the module's map there.
    if (usesWebpackInternal(source) || usesWebpackInternal(rendered)) out.scripts = scriptURLs();
  } catch (e) {
    out.error = String(e && e.message || e);
  }
  return JSON.stringify(out);

  // MARK: finding the node

  function findNode(a) {
    if (a.id) {
      var byId = document.getElementById(a.id);
      if (byId) return byId;
    }
    var point = clientCenter(a);
    var classes = (a.classes || []).filter(Boolean);
    if (point) {
      var el = document.elementFromPoint(point.x, point.y);
      if (classes.length) {
        // Walk up to the node that carries the class list accessibility named.
        for (var cur = el, i = 0; cur && i < 12; cur = cur.parentElement, i++) {
          if (hasClasses(cur, classes)) return cur;
        }
      } else if (el) {
        // No handles: the point lands on the deepest node, so climb to the one whose size is the frame's.
        return bestBySize(el, a);
      }
    }
    if (classes.length) {
      var sel = classes.map(function (c) { return '.' + CSS.escape(c); }).join('');
      var all = document.querySelectorAll(sel);
      if (all.length === 1) return all[0];
      if (all.length > 1 && a.frame) {
        // Several share the classes: take the one whose size and place match best.
        var best = null, bestScore = Infinity, zoom = pageZoom(a);
        for (var k = 0; k < all.length; k++) {
          var r = all[k].getBoundingClientRect();
          var p = point || { x: 0, y: 0 };
          var score = Math.abs(r.width * zoom - a.frame.w) + Math.abs(r.height * zoom - a.frame.h)
            + (point ? Math.abs(r.left + r.width / 2 - p.x) + Math.abs(r.top + r.height / 2 - p.y) : 0);
          if (score < bestScore) { bestScore = score; best = all[k]; }
        }
        return best;
      }
    }
    return null;
  }

  function bestBySize(el, a) {
    var zoom = pageZoom(a), best = el, bestScore = Infinity;
    for (var cur = el, i = 0; cur && cur !== document.body && i < 8; cur = cur.parentElement, i++) {
      var r = cur.getBoundingClientRect();
      var score = Math.abs(r.width * zoom - a.frame.w) + Math.abs(r.height * zoom - a.frame.h);
      if (score < bestScore) { bestScore = score; best = cur; }
    }
    return best;
  }

  function hasClasses(el, classes) {
    if (!el.classList) return false;
    for (var i = 0; i < classes.length; i++) if (!el.classList.contains(classes[i])) return false;
    return true;
  }

  // Screen points per CSS pixel. The viewport's own width in points over its width in CSS pixels;
  // without the viewport, the window's (wrong beside a sidebar, and Brave randomises the window's numbers).
  function pageZoom(a) {
    var z = a.area && a.area.w && window.innerWidth ? a.area.w / window.innerWidth
      : window.outerWidth && window.innerWidth ? window.outerWidth / window.innerWidth : 1;
    return z > 0.25 && z < 5 ? z : 1;
  }

  // A screen-point frame to the client point at its centre. Accessibility gives the viewport's place
  // on screen; without it, the toolbar is taken to sit above a viewport centred in the window.
  function clientCenter(a) {
    var frame = a.frame;
    if (!frame) return null;
    var zoom = pageZoom(a), left, top;
    if (a.area) {
      left = a.area.x; top = a.area.y;
    } else {
      left = window.screenX + (window.outerWidth - window.innerWidth * zoom) / 2;
      top = window.screenY + window.outerHeight - window.innerHeight * zoom;
    }
    var x = (frame.x + frame.w / 2 - left) / zoom, y = (frame.y + frame.h / 2 - top) / zoom;
    if (x < 0 || y < 0 || x > window.innerWidth || y > window.innerHeight) return null;
    return { x: x, y: y };
  }

  function describeNode(el) {
    var d = { tag: el.tagName.toLowerCase() };
    if (el.id) d.id = el.id;
    if (el.classList && el.classList.length) d.classes = Array.prototype.slice.call(el.classList, 0, 6);
    return d;
  }

  // MARK: React

  function reactFiber(el) {
    for (var cur = el, depth = 0; cur && depth < 8; cur = cur.parentNode, depth++) {
      var keys = Object.keys(cur);
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].indexOf('__reactFiber$') === 0 || keys[i].indexOf('__reactInternalInstance$') === 0) {
          return { fiber: cur[keys[i]], depth: depth };
        }
      }
    }
    return null;
  }

  function isFiber(o) { return !!o && typeof o.tag === 'number'; }

  function componentName(fiber) {
    var t = fiber && fiber.type;
    if (!t || typeof t === 'string') return null;
    if (typeof t === 'function') return t.displayName || t.name || null;
    if (typeof t === 'object') {
      if (t.displayName) return t.displayName;
      var inner = t.render || t.type; // forwardRef, memo
      if (inner) return inner.displayName || inner.name || null;
    }
    return null;
  }

  function ownerName(o) {
    if (isFiber(o)) return componentName(o);
    return typeof o.name === 'string' && o.name ? o.name : null;
  }

  function propsPreview(props) {
    if (!props || typeof props !== 'object') return [];
    return Object.keys(props).filter(function (k) { return k !== 'children' && k !== 'key'; }).slice(0, 12).map(function (k) {
      return { name: k, value: preview(props[k]) };
    });
  }

  function preview(v) {
    if (v === null) return 'null';
    if (v === undefined) return 'undefined';
    if (typeof v === 'function') return '[function]';
    if (typeof v === 'string') return JSON.stringify(v.length > 40 ? v.slice(0, 39) + '…' : v);
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (Array.isArray(v)) return '[array(' + v.length + ')]';
    if (typeof v === 'object') {
      var keys = Object.keys(v);
      return '{' + keys.slice(0, 5).join(', ') + (keys.length > 5 ? ', …' : '') + '}';
    }
    return typeof v;
  }

  // Where a fiber's or a server component's JSX was written. React 18 with the JSX source transform
  // keeps _debugSource, a file and line as written. React 19 keeps a stack made when the JSX ran, in
  // the built code's lines: its first frames go back as they are.
  function where(o) {
    var ds = o._debugSource;
    if (ds && ds.fileName) return { file: ds.fileName, line: ds.lineNumber, column: ds.columnNumber || null };
    var stack = o._debugStack || o.debugStack;
    var text = stack && (stack.stack || String(stack));
    if (!text) return null;
    var frames = parseStack(text);
    return frames.length ? { stack: frames } : null;
  }

  // "    at Row (http://…/Rows.tsx:28:88)" in Chromium, "Row@http://…/Rows.tsx:28:88" in WebKit.
  // A webpack address has brackets of its own, so the place is cut at the first " (" and the last ")".
  function parseStack(text) {
    var lines = text.split('\n'), frames = [];
    for (var i = 0; i < lines.length && frames.length < 8; i++) {
      var line = lines[i].replace(/^\s+/, ''), fn = '', place = line;
      if (line.indexOf('at ') === 0) {
        place = line.slice(3);
        var open = place.indexOf(' (');
        if (open >= 0 && place.charAt(place.length - 1) === ')') { fn = place.slice(0, open); place = place.slice(open + 2, -1); }
      } else if (line.indexOf('@') >= 0) {
        fn = line.slice(0, line.indexOf('@')); place = line.slice(line.indexOf('@') + 1);
      } else continue;
      var m = /^(.+):(\d+):(\d+)$/.exec(place);
      if (!m) continue;
      frames.push({ fn: fn, url: m[1], line: +m[2], column: +m[3] });
    }
    return frames;
  }

  function usesWebpackInternal(w) {
    if (!w || !w.stack) return false;
    for (var i = 0; i < w.stack.length; i++) if (w.stack[i].url.indexOf('webpack-internal:') === 0) return true;
    return false;
  }

  function scriptURLs() {
    var urls = [], scripts = document.scripts;
    for (var i = 0; i < scripts.length && urls.length < 80; i++) {
      var src = scripts[i].src;
      if (src && src.indexOf(location.origin + '/') === 0) urls.push(src);
    }
    return urls;
  }
})(__LOCANT_ARGS__)
