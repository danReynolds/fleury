// Runs every benchmark in the suite and prints a single consolidated
// report. Useful for capturing a full baseline in one go.

import 'animation_benchmarks.dart' as animation;
import 'build_benchmarks.dart' as build;
import 'debug_shell_benchmarks.dart' as debug;
import 'focus_traversal_benchmarks.dart' as focus_traversal;
import 'paint_benchmarks.dart' as paint;
import 'parser_benchmarks.dart' as parser;
import 'render_benchmarks.dart' as render;
import 'widgets_benchmarks.dart' as widgets;

void main() {
  print('=== render ===');
  render.main();
  print('');
  print('=== paint ===');
  paint.main();
  print('');
  print('=== build ===');
  build.main();
  print('');
  print('=== parser ===');
  parser.main();
  print('');
  print('=== widgets ===');
  widgets.main();
  print('');
  print('=== focus traversal ===');
  focus_traversal.main();
  print('');
  print('=== animation ===');
  animation.main();
  print('');
  print('=== debug shell ===');
  debug.main();
}
