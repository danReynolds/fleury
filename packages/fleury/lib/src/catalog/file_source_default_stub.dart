import 'file_source.dart';

FileSource defaultFileSource() => throw UnsupportedError(
  'There is no local disk to list in the browser. Pass a FileSource to '
  'FileBrowser or FilePicker, such as a MemoryFileSource.',
);
