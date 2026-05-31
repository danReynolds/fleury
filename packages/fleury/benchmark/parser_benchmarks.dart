// Input parser throughput. Measures bytes/sec the state machine
// can chew through. Mixed sequence types (plain text, CSI cursor
// chords, modifier chords, multi-byte UTF-8) so the result reflects
// realistic load, not just the printable-ASCII fast path.

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';

class _CountingSink implements TuiEventSink {
  int count = 0;
  @override
  void add(TuiEvent event) => count += 1;
}

/// 1KB of printable ASCII. The hot path.
class ParserAsciiBenchmark extends BenchmarkBase {
  ParserAsciiBenchmark() : super('parser_ascii_1KB');
  late final List<int> bytes;
  late final InputParser parser;
  late final TuiEventSink sink;

  @override
  void setup() {
    bytes = List<int>.filled(1024, 0x61); // all 'a'
    parser = InputParser();
    sink = _CountingSink();
  }

  @override
  void run() {
    parser.feed(bytes, sink);
  }
}

/// 1KB of CSI cursor-key sequences (ESC[A repeated). Stresses the
/// CSI state machine.
class ParserCsiBenchmark extends BenchmarkBase {
  ParserCsiBenchmark() : super('parser_csi_1KB');
  late final List<int> bytes;
  late final InputParser parser;
  late final TuiEventSink sink;

  @override
  void setup() {
    final source = <int>[];
    while (source.length < 1024) {
      source.addAll([0x1B, 0x5B, 0x41]); // ESC [ A
    }
    bytes = source.sublist(0, 1024);
    parser = InputParser();
    sink = _CountingSink();
  }

  @override
  void run() {
    parser.feed(bytes, sink);
  }
}

/// 1KB of multi-byte UTF-8 (Chinese character 中, 3 bytes).
class ParserUtf8Benchmark extends BenchmarkBase {
  ParserUtf8Benchmark() : super('parser_utf8_1KB');
  late final List<int> bytes;
  late final InputParser parser;
  late final TuiEventSink sink;

  @override
  void setup() {
    final source = <int>[];
    while (source.length < 1024) {
      source.addAll([0xE4, 0xB8, 0xAD]); // 中
    }
    bytes = source.sublist(0, 1023);
    parser = InputParser();
    sink = _CountingSink();
  }

  @override
  void run() {
    parser.feed(bytes, sink);
  }
}

/// Mixed realistic input: typed text, occasional arrow chords, modifier
/// chords, paste-sized bursts.
class ParserMixedBenchmark extends BenchmarkBase {
  ParserMixedBenchmark() : super('parser_mixed_1KB');
  late final List<int> bytes;
  late final InputParser parser;
  late final TuiEventSink sink;

  @override
  void setup() {
    final source = <int>[];
    while (source.length < 1024) {
      // word + space + arrow up + word + ctrl-c
      source.addAll([0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x20]); // "hello "
      source.addAll([0x1B, 0x5B, 0x41]); // ESC [ A (arrow up)
      source.addAll([0x77, 0x6F, 0x72, 0x6C, 0x64, 0x20]); // "world "
      source.add(0x03); // Ctrl+C
    }
    bytes = source.sublist(0, 1024);
    parser = InputParser();
    sink = _CountingSink();
  }

  @override
  void run() {
    parser.feed(bytes, sink);
  }
}

void main() {
  ParserAsciiBenchmark().report();
  ParserCsiBenchmark().report();
  ParserUtf8Benchmark().report();
  ParserMixedBenchmark().report();
}
