// Shared harness for the browser semantics-mirror suites: mount a tree into a
// detached root and address mirrored elements by semantic id.
import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:web/web.dart' as web;

/// Presents [tree] into a fresh detached root and returns it for inspection.
web.Element present(SemanticTree tree) {
  final root = web.document.createElement('div');
  SemanticDomPresenter(root: root).present(tree);
  return root;
}

/// The mirrored element for the node with semantic id [id].
web.Element byId(web.Element root, String id) =>
    root.querySelector('[data-fleury-semantic-id="$id"]')!;
