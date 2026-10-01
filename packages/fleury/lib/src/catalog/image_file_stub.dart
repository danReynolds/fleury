import 'dart:typed_data';

String canonicalPath(String path) => path;

Uint8List readBytes(String path) => throw UnsupportedError(
  'Image.file is unavailable on browser hosts. Load bytes asynchronously and '
  'use Image.bytes or Image.decoded instead.',
);
