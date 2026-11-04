// Locant web source lookup (prototype). Runs inside the page through the browser's own
// "execute javascript" Apple Event. It finds the DOM node Locant resolved through accessibility,
// then reads what React's development build keeps on it: the component that rendered it, that
// component's props, where the element's JSX is, and where the component is used. Source lines
// come from the dev server's source maps. It returns one JSON string and never changes the page.
// The caller replaces the placeholder on the last line with {"id","classes","frame":{x,y,w,h}} in screen points.
(function (args) {
  'use strict';
  // Assigned before any return: the helpers below are hoisted, their data is not.
  var mapCache = {};
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var out = { v: 1 };
  try {
    var node = findNode(args);
    if (!node) { out.error = 'node not found'; return JSON.stringify(out); }
    out.node = describeNode(node);
    var hit = reactFiber(node);
    if (!hit) { out.error = 'no React fiber on the node or its ancestors'; return JSON.stringify(out); }
    out.framework = 'react';
    var fiber = hit.fiber;
    if (hit.depth > 0) out.fiberDepth = hit.depth;
    var source = fiberSource(fiber);
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
    while (o && guard < 12) { var name = componentName(o); if (name) chain.push(name); o = o._debugOwner; guard++; }
    out.components = chain;
    out.props = propsPreview(owner.memoizedProps);
    var rendered = fiberSource(owner);
    if (rendered) out.renderedAt = rendered;
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
    var point = clientCenter(a.frame);
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
        return bestBySize(el, a.frame);
      }
    }
    if (classes.length) {
      var sel = classes.map(function (c) { return '.' + CSS.escape(c); }).join('');
      var all = document.querySelectorAll(sel);
      if (all.length === 1) return all[0];
      if (all.length > 1 && a.frame) {
        // Several share the classes: take the one whose size and place match best.
        var best = null, bestScore = Infinity, zoom = pageZoom();
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

  function bestBySize(el, frame) {
    var zoom = pageZoom(), best = el, bestScore = Infinity;
    for (var cur = el, i = 0; cur && cur !== document.body && i < 8; cur = cur.parentElement, i++) {
      var r = cur.getBoundingClientRect();
      var score = Math.abs(r.width * zoom - frame.w) + Math.abs(r.height * zoom - frame.h);
      if (score < bestScore) { bestScore = score; best = cur; }
    }
    return best;
  }

  function hasClasses(el, classes) {
    if (!el.classList) return false;
    for (var i = 0; i < classes.length; i++) if (!el.classList.contains(classes[i])) return false;
    return true;
  }

  // outerWidth is in screen points, innerWidth in CSS pixels: their ratio is the page zoom.
  function pageZoom() {
    var z = window.outerWidth && window.innerWidth ? window.outerWidth / window.innerWidth : 1;
    return z > 0.25 && z < 5 ? z : 1;
  }

  // A screen-point frame to the client point at its centre. The toolbar sits above the viewport,
  // so the viewport's top is the window's bottom minus the viewport's height in points.
  function clientCenter(frame) {
    if (!frame) return null;
    var zoom = pageZoom();
    var left = window.screenX + (window.outerWidth - window.innerWidth * zoom) / 2;
    var top = window.screenY + window.outerHeight - window.innerHeight * zoom;
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

  // Where a fiber's JSX was written. React 18 with the JSX source transform keeps _debugSource;
  // React 19 keeps _debugStack, an Error made when the JSX ran, whose frames the source map maps.
  function fiberSource(fiber) {
    var ds = fiber._debugSource;
    if (ds && ds.fileName) return { file: ds.fileName, line: ds.lineNumber, column: ds.columnNumber || null, via: 'debugSource' };
    var stack = fiber._debugStack;
    var text = stack && (stack.stack || String(stack));
    if (!text) return null;
    var frame = userFrame(text);
    if (!frame) return null;
    var mapped = mapFrame(frame);
    if (mapped) { mapped.via = 'sourcemap'; return mapped; }
    return { file: stripQuery(frame.url), line: frame.line, column: frame.column, via: 'generated' };
  }

  // The first frame outside React and node_modules: the JSX call in the user's own module.
  function userFrame(text) {
    var lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var m = /(https?:\/\/[^\s()]+):(\d+):(\d+)/.exec(lines[i]);
      if (!m) continue;
      if (/\/node_modules\/|react-dom|react_jsx|jsx-dev-runtime|jsx-runtime|\/@react-refresh/.test(m[1])) continue;
      return { url: m[1], line: +m[2], column: +m[3] };
    }
    return null;
  }

  function stripQuery(url) { return url.replace(/[?#].*$/, ''); }

  // MARK: source maps

  function fetchText(url) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, false); // synchronous: the Apple Event waits for a plain return value
    xhr.send(null);
    return xhr.status >= 200 && xhr.status < 300 ? xhr.responseText : null;
  }

  function loadMap(url) {
    if (url in mapCache) return mapCache[url];
    var map = null;
    try {
      var code = fetchText(url);
      var m = code && /\/\/[#@] sourceMappingURL=(\S+)\s*$/.exec(code);
      if (m) {
        var ref = m[1];
        var inline = /^data:application\/json;(?:charset=[^;,]+;)?base64,(.*)$/.exec(ref);
        var json = inline ? decodeBase64(inline[1]) : fetchText(new URL(ref, url).href);
        if (json) { map = JSON.parse(json); map.__url = inline ? url : new URL(ref, url).href; }
      }
    } catch (e) { map = null; }
    mapCache[url] = map;
    return map;
  }

  function decodeBase64(b64) {
    var bin = atob(b64), bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder().decode(bytes);
  }

  function vlq(seg) {
    var out = [], shift = 0, value = 0;
    for (var i = 0; i < seg.length; i++) {
      var d = B64.indexOf(seg[i]), more = d & 32;
      value += (d & 31) << shift;
      if (more) { shift += 5; continue; }
      out.push(value & 1 ? -(value >> 1) : value >> 1);
      shift = 0; value = 0;
    }
    return out;
  }

  // One-based generated line and column to one-based original file, line and column.
  function mapFrame(frame) {
    var map = loadMap(frame.url);
    if (!map || !map.mappings) return null;
    var lines = map.mappings.split(';');
    var src = 0, oLine = 0, oCol = 0, best = null;
    for (var li = 0; li < lines.length && li < frame.line; li++) {
      var gCol = 0;
      if (!lines[li]) continue;
      var segs = lines[li].split(',');
      for (var s = 0; s < segs.length; s++) {
        if (!segs[s]) continue;
        var f = vlq(segs[s]);
        gCol += f[0];
        if (f.length > 3) { src += f[1]; oLine += f[2]; oCol += f[3]; }
        if (li === frame.line - 1 && f.length > 3 && gCol <= frame.column - 1) {
          best = { source: src, line: oLine + 1, column: oCol + 1 };
        }
      }
    }
    if (!best) return null;
    var name = (map.sources || [])[best.source];
    if (name == null) return null;
    return { file: sourcePath(name, map), line: best.line, column: best.column };
  }

  // A source map's source as the dev server serves it: "/src/Library.tsx" for Vite's "Library.tsx"
  // next to "/src/Library.tsx?t=…". Absolute file paths and webpack:// names pass through.
  function sourcePath(name, map) {
    if (/^\//.test(name)) return name;
    if (/^[a-z]+:\/\//i.test(name) && !/^https?:/i.test(name)) return name;
    try {
      var base = map.__url;
      var root = map.sourceRoot ? new URL(map.sourceRoot.replace(/\/?$/, '/'), base).href : base;
      var u = new URL(name, root);
      return u.origin === location.origin ? u.pathname : u.href;
    } catch (e) { return name; }
  }
})(__LOCANT_ARGS__)
