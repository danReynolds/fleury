// One entry point for the guide checks; each demo also runs independently.
import 'input/contact_fields_test.dart' as contact_fields;
import 'input/file_actions_test.dart' as file_actions;
import 'input/split_pane_test.dart' as split_pane;
import 'input/nested_row_test.dart' as nested_row;
import 'input/press_tile_test.dart' as press_tile;
import 'input/selectable_note_test.dart' as selectable_note;

void main() {
  contact_fields.main();
  file_actions.main();
  split_pane.main();
  nested_row.main();
  press_tile.main();
  selectable_note.main();
}
