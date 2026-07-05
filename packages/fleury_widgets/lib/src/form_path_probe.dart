// Web-safe stub for the form path-field's `mustExist` filesystem check.
// A conditional import (`if (dart.library.io)`) swaps in form_path_probe_io.dart
// on native platforms; on the web there is no filesystem to probe, so existence
// validation is skipped (the field still enforces format / required / absolute).
// This is what makes the whole FormPanel compile to JavaScript.

/// Returns a validation error string if [path] fails the existence / kind
/// check, or null when it passes (or can't be verified on this platform).
String? probeFormPathExistence({
  required String path,
  required bool requireFile,
  required bool requireDirectory,
  required String label,
}) =>
    null;
