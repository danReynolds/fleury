/// Fleury host SPI for process hosts (`dart:io`).
///
/// Re-exports [fleury_host.dart](fleury_host.dart) plus the socket transports a
/// native process host — `fleury serve`, an MCP/agent bridge — uses to drive a
/// spawned Fleury app over a connection. Pulls in `dart:io`; browser hosts use
/// `fleury_host.dart` with their own (e.g. WebSocket) transport instead.
library;

export 'fleury_host.dart';
export 'src/remote/spawn.dart';
export 'src/remote/unix_socket_transport.dart';
