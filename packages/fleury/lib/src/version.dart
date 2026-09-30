/// The Fleury package version embedded in its CLI and diagnostics.
///
/// Keep this synchronized with pubspec.yaml when preparing a release. A
/// standalone compiled CLI cannot look up the pubspec that produced it; the
/// version contract test checks these declarations agree.
const fleuryVersion = '0.1.0';
