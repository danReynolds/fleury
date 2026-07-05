/// Showcase sample applications for the Fleury TUI framework.
///
/// Each app is a self-contained root widget (it provides its own theme and
/// [Toaster] host) so it runs identically in a terminal or in the browser over
/// `fleury serve`. They double as the runnable showcases on the docs site.
library;

export 'src/agent_tui.dart' show AgentApp;
export 'src/dashboard.dart' show DashboardApp;
export 'src/file_manager.dart' show FileManagerApp;
export 'src/scaffold.dart' show SampleScaffold, fleurySampleTheme;
