import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

// OSC 8 hyperlinks demo. Over `fleury serve` the links render as clickable
// browser anchors; in a supporting terminal (iTerm2/kitty/WezTerm/Ghostty, or
// FLEURY_HYPERLINKS=1) the same MarkdownText emits clickable OSC 8 links.
void main() {
  runApp(
    MarkdownText('''
# Fleury 0.1 — clickable links, one widget, every surface

Docs: [Fleury docs](https://danreynolds.github.io/fleury/)

Source: [danReynolds/fleury](https://github.com/danReynolds/fleury)

Found a bug? [Open an issue](https://github.com/danReynolds/fleury/issues)

Email example: [hello@example.com](mailto:hello@example.com)

Unsafe scheme is refused (renders as plain text, not a link):
[do not click](javascript:alert(1))

Press Ctrl+C to exit.
'''),
  );
}
