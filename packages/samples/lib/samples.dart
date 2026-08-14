/// Showcase sample applications for the Fleury TUI framework.
///
/// Each app is a self-contained root widget (it provides its own theme and
/// [Toaster] host) so it runs identically in a terminal or in the browser over
/// `fleury serve`. They double as the runnable showcases on the docs site.
library;

export 'src/agent_tui.dart' show AgentApp;
export 'src/ansi_sprite_studio.dart' show AnsiSpriteStudioApp;
export 'src/dashboard.dart' show DashboardApp;
export 'src/debug_playground.dart' show DebugPlaygroundApp;
export 'src/editor.dart'
    show EditorApp, EditorModel, EditorPersonality, VimMode;
export 'src/finance.dart' show FinanceApp;
export 'src/file_manager.dart' show FileManagerApp;
export 'src/forms_showcase.dart' show FormsShowcaseApp;
export 'src/neon_asteroids.dart' show NeonAsteroidsApp;
export 'src/scaffold.dart' show SampleScaffold, fleurySampleTheme;
