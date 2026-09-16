/// Versioned workload contracts. Changing a fixture or timing boundary requires
/// a new harness hash; results from different hashes cannot be compared.
const labSchema = 2;
const scenarios = <String, String>{
  'panes-16': '16 fixed panes; mutate one visible wrapping label each frame',
  'panes-40': '40 fixed panes; mutate one visible wrapping label each frame',
  'panes-96': '96 fixed panes; mutate one visible wrapping label each frame',
  'dashboard-leaf': 'Real dashboard; mutate one visible text leaf',
  'editor-leaf': 'Real editor; mutate one visible text leaf',
  'resize': 'Dashboard; alternate 120x40 and 100x32 viewports',
  'typing': 'Real TextInput; alternate insertion and deletion, closed loop',
  'list': '100,000 rows; move focus down through a lazy list, closed loop',
  'keyed-list-1k': '1,000 integer keys; parent updates visible row labels',
  'keyed-list': '100,000 integer keys; parent updates visible row labels',
  'keyed-list-strings':
      '100,000 string keys; parent updates visible row labels',
  'keyed-list-reorder': '100,000 keys; swap the first two items on each update',
  'keyed-list-replace': '100,000 keys; replace the final key on each update',
  'unkeyed-list-rebuild': '100,000 unkeyed rows; parent updates visible labels',
  'paste': 'Real TextInput; paste 4 KiB then clear, closed loop',
  'burst':
      'TextInput plus log; 16 input events injected without awaiting replies',
  'slow-output':
      'Same burst with a 10 ms blocked output sink; verify final wire state',
};

bool isPipeline(String name) =>
    scenarios.containsKey(name) &&
    !isListRebuild(name) &&
    !const {'typing', 'list', 'paste', 'burst', 'slow-output'}.contains(name);

bool isListRebuild(String name) =>
    name.startsWith('keyed-list') || name == 'unkeyed-list-rebuild';

int listRebuildCount(String name) => name == 'keyed-list-1k' ? 1000 : 100000;

Map<String, Object> contract(String scenario) => {
      'scenario': scenario,
      'fixture': scenarios[scenario]!,
      'viewport': isListRebuild(scenario) ? [80, 20] : [120, 40],
      'boundary': isListRebuild(scenario)
          ? 'parent setState through tester pump; excludes encoding, transport and display'
          : isPipeline(scenario)
              ? 'mutation through build/layout/paint/diff/commit; excludes output encoding'
              : 'enqueue to next event-loop checkpoint after dispatch; not display latency',
      'load': switch (scenario) {
        'burst' ||
        'slow-output' =>
          '16-event batch; no per-event response pacing',
        _ => 'closed loop',
      },
      'sink': isPipeline(scenario) || isListRebuild(scenario)
          ? 'cell buffer'
          : 'structured in-memory peer',
      'debugCounters': false,
    };

class LabOptions {
  LabOptions({required this.scenario, this.samples = 300, this.warmup = 30}) {
    if (!scenarios.containsKey(scenario)) {
      throw ArgumentError('Unknown scenario: $scenario');
    }
    if (samples < 2 || warmup < 0) {
      throw ArgumentError('samples must be >= 2; warmup must be >= 0');
    }
  }
  final String scenario;
  final int samples, warmup;
  Map<String, Object> toJson() => {
        ...contract(scenario),
        'samples': samples,
        'warmup': warmup,
      };
}
