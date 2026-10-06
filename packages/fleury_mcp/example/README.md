# Drive a Fleury app with fleury_mcp

`fleury_mcp` starts your Fleury app and serves its semantic tree to an MCP
host, which can then read the UI and operate it. The app needs no MCP code.
The server runs on macOS and Linux.

## 1. Add the server to the app

Add it as a development dependency of the app it will drive:

```yaml
dev_dependencies:
  fleury_mcp: ^0.1.0
```

Then run `dart pub get`. `dart pub add --dev fleury_mcp` does both steps.

## 2. Start it from the app's directory

Pass the command that runs your app after `--`:

```sh
dart run fleury_mcp -- dart run bin/run_app.dart
```

The server speaks JSON-RPC on stdin and stdout, so an MCP host normally starts
it. With Claude Code:

```sh
claude mcp add my-app -- dart run fleury_mcp -- dart run bin/run_app.dart
```

Configure the host to start the server in the application directory, so Dart
finds the development dependency and the app's entrypoint.

## 3. Check it by hand

Without a host, pipe in the legacy initialization request and a `get_ui` call:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_ui","arguments":{}}}' \
  | dart run fleury_mcp -- dart run bin/run_app.dart
```

The second response lists the app's controls with their roles, labels, values,
and supported actions. A cold `dart run` compiles the app first. If `get_ui`
reports that the app has not rendered a UI yet, retry, or compile the app once
(`dart compile exe bin/run_app.dart -o my_app`) and pass `./my_app` as its
command instead.

The [package README](https://pub.dev/packages/fleury_mcp) covers the tools, the
options, and attaching to a development session you started with
`fleury run --agent`.
