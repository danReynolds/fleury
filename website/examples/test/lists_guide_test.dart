import 'lists/horizontal_list_test.dart' as horizontal_list;
import 'lists/horizontal_content_test.dart' as horizontal_content;
// One entry point for the guide checks; each example also runs independently.
import 'lists/file_list_test.dart' as file_list;
import 'lists/task_browser_test.dart' as task_browser;
import 'lists/reorder_tasks_test.dart' as reorder_tasks;
import 'lists/scroll_edges_test.dart' as scroll_edges;
import 'lists/build_log_test.dart' as build_log;

void main() {
  file_list.main();
  horizontal_list.main();
  horizontal_content.main();
  task_browser.main();
  reorder_tasks.main();
  scroll_edges.main();
  build_log.main();
}
