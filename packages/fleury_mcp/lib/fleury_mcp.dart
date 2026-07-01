/// A Model Context Protocol (MCP) server for Fleury.
///
/// It drives a running Fleury terminal-UI app through its semantic tree, so an
/// MCP host (Claude, Claude Code, …) can read the UI as roles/labels/values and
/// operate it through the actions each node advertises — no screen-scraping.
///
/// - [FleuryAppBridge] spawns the app and bridges to it over Fleury's remote
///   wire (it is a peer, like the browser serve client), tracking the live
///   semantic snapshot and carrying actions/input back.
/// - [McpServer] / [runMcpServer] expose that bridge as JSON-RPC 2.0 over stdio:
///   a `fleury://ui/tree` resource plus get_ui / find_nodes / invoke_action /
///   type_text / press_key tools.
library;

export 'src/app_bridge.dart' show BridgeLog, FleuryAppBridge, FleuryAppBridgeException;
export 'src/mcp_server.dart'
    show McpServer, mcpProtocolVersion, mcpServerName, mcpServerVersion, runMcpServer;
