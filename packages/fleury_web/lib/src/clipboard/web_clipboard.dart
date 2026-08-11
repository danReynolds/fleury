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
        : !policy.allowPlatformTool
        ? _policyBlockedResolution()
        : _unsupportedResolution();
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

const _clipboardRequirement = fleury.CapabilityRequirement(
  feature: fleury.TerminalFeature.clipboardWrite,
  level: fleury.CapabilityLevel.preferred,
  fallback: fleury.CapabilityFallback(label: _fallbackLabel),
);

fleury.CapabilityResolution _availableResolution() =>
    fleury.resolveCapabilityRequirement(
      _clipboardRequirement,
      const fleury.CapabilityTruth(
        feature: fleury.TerminalFeature.clipboardWrite,
        support: fleury.CapabilitySupport.supported,
        enablement: fleury.CapabilityEnablement.notApplicable,
        delivery: fleury.CapabilityDelivery.delivered,
        evidence: <fleury.CapabilityEvidence>[
          fleury.CapabilityEvidence(
            source: fleury.CapabilityEvidenceSource.operationResult,
            detail: 'navigator.clipboard.writeText completed successfully.',
          ),
        ],
      ),
    );

fleury.CapabilityResolution _degradedResolution(String warning) =>
    fleury.resolveCapabilityRequirement(
      _clipboardRequirement,
      fleury.CapabilityTruth(
        feature: fleury.TerminalFeature.clipboardWrite,
        support: fleury.CapabilitySupport.supported,
        enablement: fleury.CapabilityEnablement.notApplicable,
        delivery: fleury.CapabilityDelivery.failed,
        evidence: <fleury.CapabilityEvidence>[
          fleury.CapabilityEvidence(
            source: fleury.CapabilityEvidenceSource.operationResult,
            detail: warning,
          ),
        ],
      ),
    );

fleury.CapabilityResolution _unsafeResolution(String warning) =>
    fleury.resolveCapabilityRequirement(
      _clipboardRequirement,
      fleury.CapabilityTruth(
        feature: fleury.TerminalFeature.clipboardWrite,
        support: fleury.CapabilitySupport.unknown,
        enablement: fleury.CapabilityEnablement.disabled,
        delivery: fleury.CapabilityDelivery.notApplicable,
        unsafe: true,
        evidence: <fleury.CapabilityEvidence>[
          fleury.CapabilityEvidence(
            source: fleury.CapabilityEvidenceSource.policy,
            detail: warning,
          ),
        ],
      ),
    );

fleury.CapabilityResolution _policyBlockedResolution() =>
    fleury.resolveCapabilityRequirement(
      _clipboardRequirement,
      const fleury.CapabilityTruth(
        feature: fleury.TerminalFeature.clipboardWrite,
        support: fleury.CapabilitySupport.unknown,
        enablement: fleury.CapabilityEnablement.disabled,
        delivery: fleury.CapabilityDelivery.notApplicable,
        policyBlocked: true,
        evidence: <fleury.CapabilityEvidence>[
          fleury.CapabilityEvidence(
            source: fleury.CapabilityEvidenceSource.policy,
            detail: 'Browser clipboard write was disabled by policy.',
          ),
        ],
      ),
    );

fleury.CapabilityResolution _unsupportedResolution() =>
    fleury.resolveCapabilityRequirement(
      _clipboardRequirement,
      const fleury.CapabilityTruth(
        feature: fleury.TerminalFeature.clipboardWrite,
        support: fleury.CapabilitySupport.unsupported,
        enablement: fleury.CapabilityEnablement.notApplicable,
        delivery: fleury.CapabilityDelivery.notApplicable,
        evidence: <fleury.CapabilityEvidence>[
          fleury.CapabilityEvidence(
            source: fleury.CapabilityEvidenceSource.surfaceProfile,
            detail: 'The browser clipboard API is unavailable.',
          ),
        ],
      ),
    );
