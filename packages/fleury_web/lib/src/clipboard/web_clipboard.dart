import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury/fleury_host.dart' as fleury;
import 'package:web/web.dart' as web;

const _browserClipboardTransport = 'navigator.clipboard.writeText';
const _fallbackLabel = 'in-process register';

/// Browser clipboard backend for Fleury web hosts.
///
/// The browser system clipboard is best-effort: secure-context restrictions,
/// user activation requirements, and permission prompts can all reject writes.
/// Fleury still updates the in-process register first so app-local copy
/// behavior succeeds even when the browser denies system clipboard access.
final class WebClipboard extends fleury.Clipboard {
  WebClipboard({
    web.Window? window,
    Future<void> Function(String text)? writeText,
    bool? secureContext,
    bool? clipboardAvailable,
  }) : _window = window ?? web.window,
       _writeText = writeText,
       _secureContext = secureContext,
       _clipboardAvailableOverride = clipboardAvailable;

  final web.Window _window;
  final Future<void> Function(String text)? _writeText;
  final bool? _secureContext;
  final bool? _clipboardAvailableOverride;
  String? _register;

  @override
  String? readInProcess() => _register;

  @override
  Future<fleury.ClipboardWriteReport> writeWithReport(
    String text, {
    fleury.ClipboardWritePolicy policy = fleury.ClipboardWritePolicy.standard,
  }) async {
    _register = text;
    final payloadBytes = utf8.encode(text).length;
    final encodedLength = base64Encode(utf8.encode(text)).length;

    if (policy.allowPlatformTool && _isSecureContext && _clipboardAvailable) {
      try {
        await _writeBrowserText(text);
        return _report(
          result: fleury.ClipboardWriteResult.platformTool,
          resolution: _availableResolution(),
          policy: policy,
          payloadBytes: payloadBytes,
          encodedLength: encodedLength,
          browserAttempted: true,
          browserSucceeded: true,
        );
      } catch (error) {
        return _report(
          result: fleury.ClipboardWriteResult.inProcessOnly,
          resolution: _degradedResolution(
            'Browser clipboard write failed; using $_fallbackLabel. $error',
          ),
          policy: policy,
          payloadBytes: payloadBytes,
          encodedLength: encodedLength,
          browserAttempted: true,
          browserSucceeded: false,
        );
      }
    }

    final resolution = !_isSecureContext
        ? _unsafeResolution('Browser clipboard requires a secure context.')
        : _degradedResolution(
            _clipboardAvailable
                ? 'Browser clipboard write disabled by policy.'
                : 'Browser clipboard API is unavailable.',
          );
    return _report(
      result: fleury.ClipboardWriteResult.inProcessOnly,
      resolution: resolution,
      policy: policy,
      payloadBytes: payloadBytes,
      encodedLength: encodedLength,
      browserAttempted: false,
      browserSucceeded: false,
    );
  }

  bool get _isSecureContext => _secureContext ?? _window.isSecureContext;

  bool get _clipboardAvailable =>
      _clipboardAvailableOverride ?? _writeText != null || _hasClipboardApi;

  bool get _hasClipboardApi {
    try {
      final clipboard = _window.navigator.getProperty<JSObject?>(
        'clipboard'.toJS,
      );
      final writeText = clipboard?.getProperty<JSAny?>('writeText'.toJS);
      return writeText != null && writeText.typeofEquals('function');
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeBrowserText(String text) {
    final writeText = _writeText;
    if (writeText != null) return writeText(text);
    return _window.navigator.clipboard.writeText(text).toDart;
  }

  fleury.ClipboardWriteReport _report({
    required fleury.ClipboardWriteResult result,
    required fleury.CapabilityResolution resolution,
    required fleury.ClipboardWritePolicy policy,
    required int payloadBytes,
    required int encodedLength,
    required bool browserAttempted,
    required bool browserSucceeded,
  }) {
    return fleury.ClipboardWriteReport(
      result: result,
      resolution: resolution,
      policy: policy,
      payloadBytes: payloadBytes,
      osc52EncodedLength: encodedLength,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: browserAttempted,
      osc52Attempted: false,
      osc52Emitted: false,
      platformTool: browserAttempted || browserSucceeded
          ? _browserClipboardTransport
          : null,
    );
  }
}

fleury.CapabilityResolution _availableResolution() =>
    const fleury.CapabilityResolution(
      feature: fleury.TerminalFeature.clipboardWrite,
      level: fleury.CapabilityLevel.preferred,
      state: fleury.CapabilityResolutionState.available,
    );

fleury.CapabilityResolution _degradedResolution(String warning) =>
    fleury.CapabilityResolution(
      feature: fleury.TerminalFeature.clipboardWrite,
      level: fleury.CapabilityLevel.preferred,
      state: fleury.CapabilityResolutionState.degraded,
      fallbackLabel: _fallbackLabel,
      warning: warning,
    );

fleury.CapabilityResolution _unsafeResolution(String warning) =>
    fleury.CapabilityResolution(
      feature: fleury.TerminalFeature.clipboardWrite,
      level: fleury.CapabilityLevel.preferred,
      state: fleury.CapabilityResolutionState.unsafe,
      fallbackLabel: _fallbackLabel,
      warning: warning,
    );
