// One entry point for the guide checks; each demo also runs independently.
import 'input/contact_fields_test.dart' as contact_fields;
import 'input/split_pane_test.dart' as split_pane;
import 'input/hover_notes_test.dart' as hover_notes;
import 'input/press_tile_test.dart' as press_tile;
import 'input/selectable_note_test.dart' as selectable_note;

void main() {
  contact_fields.main();
  split_pane.main();
  hover_notes.main();
  press_tile.main();
  selectable_note.main();
}
