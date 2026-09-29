# Inline setup recording

`inline-setup.cast` is native Fleury output captured on a macOS POSIX PTY, not
browser-rendered frames. A small fixture supplies the shell context; the app
handles editing, template selection, review, Back, completion, and cleanup.
The recorder's terminal emulator answers cursor queries from its actual state.
It also asserts that terminal modes and earlier output survive the session.

Regenerate from the repository root (Python dependencies can go in a venv):

```sh
python3 -m pip install -r tool/inline-pty-requirements.txt
dart compile exe packages/samples/bin/inline.dart -o /tmp/fleury-inline-setup
python3 tool/record_inline_showcase.py /tmp/fleury-inline-setup
```

The self-hosted asciinema player loads only when the visitor requests playback.
This automated recording complements hands-on dogfooding in a real terminal.
