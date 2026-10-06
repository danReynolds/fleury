/// Fleury's supported host SPI for process hosts (`dart:io`).
///
/// Re-exports `fleury_host.dart` plus the lifecycle contracts a native process
/// host uses to spawn and supervise a Fleury app. Pulls in `dart:io`; browser
/// hosts use `fleury_host.dart`.
///
/// The Unix-socket wire transport is explicitly unstable and lives in
/// `fleury_wire_io.dart`.
library;

export 'fleury_host.dart';
export 'src/remote/spawn.dart'
    show FleurySpawnException, SpawnedFleuryApp, spawnFleuryApp;
