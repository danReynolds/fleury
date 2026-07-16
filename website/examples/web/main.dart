// Entry point for the docs example bundle. Compiled to JS with:
//   dart compile js web/main.dart -o <site>/public/fleury-examples.js
//
// It scans the page for `<div data-fleury-example="<id>">` hosts and mounts the
// matching example into each, fully client-side. It also exposes
// `window.fleuryMountExamples()` so the docs site can re-scan after Astro
// client-side navigations (the dart2js `main` only runs on the first load).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury_doc_examples/frame_flush_scheduler.dart';
import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

// `window.fleuryMountExamples()` — re-scan the page after client-side
// navigations (the dart2js `main` only runs once).
@JS('fleuryMountExamples')
external set _fleuryMountExamples(JSFunction value);

// `window.fleuryMountInto(hostElement, id)` — mount one example into a given
// element (used by the fullscreen overlay) and return a `{ dispose }` handle so
// the caller can tear it down (and stop any ticker) on close.
@JS('fleuryMountInto')
external set _fleuryMountInto(JSFunction value);

// `window.fleuryMountKnobs(hostElement, id, paramsJson)` — mount a knob-enabled
// widget built from a JSON params string, and return a
// `{ update(paramsJson), dispose }` handle so the docs UI can push new prop
// values (re-rendering in place) and tear it down.
@JS('fleuryMountKnobs')
external set _fleuryMountKnobs(JSFunction value);

void main() {
  _fleuryMountExamples = (() => _mountAll()).toJS;
  _fleuryMountInto = ((web.Element host, String id) => _mountInto(
    host,
    id,
  )).toJS;
  _fleuryMountKnobs =
      ((web.Element host, String id, String paramsJson) => _mountKnobs(
        host,
        id,
        paramsJson,
      )).toJS;
  _mountAll();
}

JSObject _mountKnobs(web.Element host, String id, String paramsJson) {
  final params = KnobParams(_decodeParams(paramsJson));
  MountedApp? surface;
  var disposed = false;
  unawaited(
    mountApp(
      () => knobRoot(id, params),
      into: host,
      flushScheduler: _docsFlush,
    ).then((h) {
      if (disposed) {
        h.dispose();
      } else {
        surface = h;
      }
    }),
  );
  final handle = JSObject();
  handle['update'] = ((String json) {
    params.value = _decodeParams(json);
  }).toJS;
  handle['dispose'] = (() {
    disposed = true;
    surface?.dispose();
    surface = null;
  }).toJS;
  return handle;
}

Map<String, Object?> _decodeParams(String json) {
  try {
    final decoded = jsonDecode(json);
    return decoded is Map
        ? decoded.cast<String, Object?>()
        : <String, Object?>{};
  } catch (_) {
    return <String, Object?>{};
  }
}

JSObject _mountInto(web.Element host, String id) {
  final builder = examples[id];
  MountedApp? surface;
  DocsExampleThemeController? followed;
  var disposed = false;
  if (builder != null) {
    final themeController = DocsExampleThemeController(
      _docsExampleStyleForHost(host),
    );
    followed = _followSiteTheme(host, themeController);
    unawaited(
      mountApp(
        () => themedExampleRoot(builder, themeController),
        into: host,
        flushScheduler: _docsFlush,
      ).then((h) {
        if (disposed) {
          h.dispose();
        } else {
          surface = h;
        }
      }),
    );
  }
  final handle = JSObject();
  handle['dispose'] = (() {
    disposed = true;
    _unfollowSiteTheme(followed);
    surface?.dispose();
    surface = null;
  }).toJS;
  return handle;
}

void _mountAll() {
  final hosts = web.document.querySelectorAll('[data-fleury-example]');
  for (var i = 0; i < hosts.length; i++) {
    final node = hosts.item(i);
    if (node is! web.Element) continue;
    if (node.getAttribute('data-fleury-state') != null) continue; // mounted
    mountExample(node);
  }
}

/// Mounts the example named by `data-fleury-example` into [host].
void mountExample(web.Element host) {
  final id = host.getAttribute('data-fleury-example');
  final builder = id == null ? null : examples[id];
  if (builder == null) {
    host.textContent = 'Unknown Fleury example: $id';
    return;
  }
  final themeController = DocsExampleThemeController(
    _docsExampleStyleForHost(host),
  );
  _followSiteTheme(host, themeController);
  host.setAttribute('data-fleury-state', 'mounting');
  unawaited(
    mountApp(
      () => themedExampleRoot(builder, themeController),
      into: host,
      flushScheduler: _docsFlush,
    ).then((_) => host.setAttribute('data-fleury-state', 'ready')),
  );
}

DocsExampleStyle _docsExampleStyleForHost(web.Element host) {
  switch (host.getAttribute('data-fleury-theme')) {
    case 'light':
      return DocsExampleStyle.light;
    case 'site':
      return _siteDocsExampleStyle();
    case 'dark':
    default:
      return DocsExampleStyle.dark;
  }
}

DocsExampleStyle _siteDocsExampleStyle() =>
    web.document.documentElement?.getAttribute('data-theme') == 'light'
    ? DocsExampleStyle.light
    : DocsExampleStyle.dark;

// Embeds that follow the site (Starlight) light/dark theme. A single shared
// MutationObserver fans `data-theme` changes out to all of them, rather than
// spinning up one observer per embed. Each entry carries its host so we can drop
// embeds whose host has detached (e.g. an Astro client-side navigation replaced
// the page) — the `mountExample` path has no dispose hook to unregister itself.
final List<(web.Element, DocsExampleThemeController)> _siteThemeEmbeds =
    <(web.Element, DocsExampleThemeController)>[];
web.MutationObserver? _siteThemeObserver;

/// Registers [controller] to follow the site theme when [host] opted in with
/// `data-fleury-theme="site"`. Returns the controller when registered, so a
/// caller with a dispose path can later [_unfollowSiteTheme] it.
DocsExampleThemeController? _followSiteTheme(
  web.Element host,
  DocsExampleThemeController controller,
) {
  if (host.getAttribute('data-fleury-theme') != 'site') return null;
  final root = web.document.documentElement;
  if (root == null) return null;
  _siteThemeEmbeds.add((host, controller));
  _siteThemeObserver ??=
      web.MutationObserver(
        ((JSArray<web.MutationRecord> _, web.MutationObserver __) {
          _siteThemeEmbeds.removeWhere((e) => !e.$1.isConnected);
          final style = _siteDocsExampleStyle();
          for (final (_, c) in _siteThemeEmbeds) {
            c.style = style;
          }
        }).toJS,
      )..observe(
        root,
        web.MutationObserverInit(
          attributes: true,
          attributeFilter: <JSString>['data-theme'.toJS].toJS,
        ),
      );
  return controller;
}

void _unfollowSiteTheme(DocsExampleThemeController? controller) {
  if (controller == null) return;
  _siteThemeEmbeds.removeWhere((e) => identical(e.$2, controller));
  if (_siteThemeEmbeds.isEmpty) {
    _siteThemeObserver?.disconnect();
    _siteThemeObserver = null;
  }
}

/// Flush scheduler for the docs examples: prefer `requestAnimationFrame`
/// (smooth, vsync-aligned) but guarantee a flush via a short Timer fallback even
/// when rAF is paused (a backgrounded or headless tab). Without this, a
/// late-mounted or animating example would never paint there. First to fire wins.
void Function() _docsFlush(Duration delay, void Function() flush) {
  return scheduleDocsFrameFlush(
    delay,
    flush,
    requestAnimationFrame: (callback) =>
        web.window.requestAnimationFrame(((JSNumber _) => callback()).toJS),
    // dart2js disallows tearing off external extension-type interop members.
    cancelAnimationFrame: (frameId) => web.window.cancelAnimationFrame(frameId),
  );
}
