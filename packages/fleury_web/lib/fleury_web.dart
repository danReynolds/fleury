/// Run fleury in the browser.
///
/// Pairs the framework's platform-agnostic core (`fleury_core.dart`) with
/// a [WebTerminalDriver] over xterm.js. The host page creates the terminal
/// and exposes it as `globalThis.fleuryTerminal`; [runTuiWeb] does the rest.
library;

export 'src/run_tui_web.dart' show runTuiWeb;
export 'src/web_terminal_driver.dart' show WebTerminalDriver;
