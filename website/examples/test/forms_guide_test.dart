// Each source/test pair also runs independently.
import 'forms/project_form_test.dart' as project;
import 'forms/save_project_test.dart' as save;
import 'forms/related_fields_test.dart' as related;
import 'forms/custom_field_test.dart' as custom;

void main() {
  project.main();
  save.main();
  related.main();
  custom.main();
}
