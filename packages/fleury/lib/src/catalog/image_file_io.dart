import 'dart:io';
import 'dart:typed_data';

String canonicalPath(String path) => File(path).absolute.path;

Uint8List readBytes(String path) => File(path).readAsBytesSync();
