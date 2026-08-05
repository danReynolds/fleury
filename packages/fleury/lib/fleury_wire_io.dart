/// Fleury's explicitly unstable remote wire for `dart:io` peers.
///
/// Exposes the Unix-socket transport used by first-party peers. Import
/// `fleury_wire.dart` alongside this library for the platform-neutral frames
/// and codecs. Keeping the two imports explicit also keeps their generated API
/// documentation unambiguous.
///
/// This is a lockstep protocol surface, not a semver-stable third-party host
/// API. Use a matching Fleury build.
library;

export 'src/remote/unix_socket_transport.dart' show UnixSocketFrameTransport;
