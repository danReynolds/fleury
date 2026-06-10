typedef TraceMap = Map<String, Object?>;

/// Browser input traces captured as importable data.
///
/// Each trace has the browser events to replay against [DomInputSource] and the
/// normalized Fleury events expected from that replay. Keep this file free of
/// `dart:io` so the same catalog can be imported by browser tests.
const browserInputTraceFixtures = <TraceMap>[
  {
    'name': 'navigation key with shift',
    'browserEvents': <TraceMap>[
      {
        'target': 'textArea',
        'event': 'keydown',
        'key': 'ArrowLeft',
        'shiftKey': true,
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {
        'type': 'key',
        'keyCode': 'arrowLeft',
        'keyEventType': 'down',
        'modifiers': <String>['shift'],
      },
    ],
  },
  {
    'name': 'shortcut repeat with ctrl and shift',
    'browserEvents': <TraceMap>[
      {
        'target': 'textArea',
        'event': 'keydown',
        'key': 'S',
        'ctrlKey': true,
        'shiftKey': true,
        'repeat': true,
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {
        'type': 'key',
        'char': 's',
        'keyEventType': 'repeat',
        'modifiers': <String>['ctrl', 'shift'],
      },
    ],
  },
  {
    'name': 'meta printable shortcut normalizes to ctrl shortcut',
    'browserEvents': <TraceMap>[
      {
        'target': 'textArea',
        'event': 'keydown',
        'key': 'Z',
        'metaKey': true,
        'shiftKey': true,
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {
        'type': 'key',
        'char': 'z',
        'keyEventType': 'down',
        'modifiers': <String>['ctrl', 'shift'],
      },
    ],
  },
  {
    'name': 'AltGraph printable text stays on input channel',
    'browserEvents': <TraceMap>[
      {
        'target': 'textArea',
        'event': 'keydown',
        'key': '@',
        'ctrlKey': true,
        'altKey': true,
        'modifierAltGraph': true,
      },
      {
        'target': 'textArea',
        'event': 'input',
        'inputType': 'insertText',
        'data': '@',
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {'type': 'text', 'text': '@'},
    ],
  },
  {
    'name': 'Alt-only printable text stays on input channel',
    'browserEvents': <TraceMap>[
      {'target': 'textArea', 'event': 'keydown', 'key': 'å', 'altKey': true},
      {
        'target': 'textArea',
        'event': 'input',
        'inputType': 'insertText',
        'data': 'å',
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {'type': 'text', 'text': 'å'},
    ],
  },
  {
    'name': 'printable text input',
    'browserEvents': <TraceMap>[
      {
        'target': 'textArea',
        'event': 'input',
        'inputType': 'insertText',
        'data': 'x',
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {'type': 'text', 'text': 'x'},
    ],
  },
  {
    'name': 'multi-line paste',
    'browserEvents': <TraceMap>[
      {'target': 'textArea', 'event': 'paste', 'text': 'a\nb'},
    ],
    'expectedFleuryEvents': <TraceMap>[
      {'type': 'paste', 'text': 'a\nb'},
    ],
  },
  {
    'name': 'paste accelerator waits for paste event',
    'browserEvents': <TraceMap>[
      {'target': 'textArea', 'event': 'keydown', 'key': 'v', 'ctrlKey': true},
      {'target': 'textArea', 'event': 'paste', 'text': 'pasted'},
    ],
    'expectedFleuryEvents': <TraceMap>[
      {'type': 'paste', 'text': 'pasted'},
    ],
  },
  {
    'name': 'composition commit suppresses duplicate input',
    'browserEvents': <TraceMap>[
      {'target': 'textArea', 'event': 'compositionstart'},
      {'target': 'textArea', 'event': 'compositionupdate', 'data': 'é'},
      {'target': 'textArea', 'event': 'compositionend', 'data': 'é'},
      {
        'target': 'textArea',
        'event': 'input',
        'inputType': 'insertText',
        'data': 'é',
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {'type': 'composition', 'kind': 'update', 'text': 'é'},
      {'type': 'composition', 'kind': 'commit', 'text': 'é'},
    ],
  },
  {
    'name': 'composition cancel without commit text',
    'browserEvents': <TraceMap>[
      {'target': 'textArea', 'event': 'compositionstart'},
      {'target': 'textArea', 'event': 'compositionupdate', 'data': 'あ'},
      {'target': 'textArea', 'event': 'compositionend'},
    ],
    'expectedFleuryEvents': <TraceMap>[
      {'type': 'composition', 'kind': 'update', 'text': 'あ'},
      {'type': 'composition', 'kind': 'cancel'},
    ],
  },
  {
    'name': 'pointer down drag and up',
    'browserEvents': <TraceMap>[
      {
        'target': 'host',
        'event': 'pointerdown',
        'pointerId': 1,
        'clientX': 25,
        'clientY': 65,
        'button': 0,
        'buttons': 1,
      },
      {
        'target': 'host',
        'event': 'pointermove',
        'pointerId': 1,
        'clientX': 35,
        'clientY': 45,
        'button': 0,
        'buttons': 1,
      },
      {
        'target': 'host',
        'event': 'pointerup',
        'pointerId': 1,
        'clientX': 45,
        'clientY': 25,
        'button': 0,
        'buttons': 0,
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {
        'type': 'mouse',
        'kind': 'down',
        'button': 'left',
        'col': 1,
        'row': 2,
        'modifiers': <String>[],
      },
      {
        'type': 'mouse',
        'kind': 'drag',
        'button': 'left',
        'col': 2,
        'row': 1,
        'modifiers': <String>[],
      },
      {
        'type': 'mouse',
        'kind': 'up',
        'button': 'left',
        'col': 3,
        'row': 0,
        'modifiers': <String>[],
      },
    ],
  },
  {
    'name': 'pointer cancellation clears stale drag state',
    'browserEvents': <TraceMap>[
      {
        'target': 'host',
        'event': 'pointerdown',
        'pointerId': 1,
        'clientX': 25,
        'clientY': 65,
        'button': 0,
        'buttons': 1,
      },
      {'target': 'host', 'event': 'lostpointercapture', 'pointerId': 1},
      {
        'target': 'host',
        'event': 'pointermove',
        'pointerId': 1,
        'clientX': 35,
        'clientY': 45,
        'button': 0,
        'buttons': 1,
      },
      {
        'target': 'host',
        'event': 'pointerdown',
        'pointerId': 2,
        'clientX': 25,
        'clientY': 65,
        'button': 0,
        'buttons': 1,
      },
      {'target': 'host', 'event': 'pointercancel', 'pointerId': 2},
      {
        'target': 'host',
        'event': 'pointermove',
        'pointerId': 2,
        'clientX': 45,
        'clientY': 45,
        'button': 0,
        'buttons': 1,
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {
        'type': 'mouse',
        'kind': 'down',
        'button': 'left',
        'col': 1,
        'row': 2,
        'modifiers': <String>[],
      },
      {
        'type': 'mouse',
        'kind': 'moved',
        'button': 'none',
        'col': 2,
        'row': 1,
        'modifiers': <String>[],
      },
      {
        'type': 'mouse',
        'kind': 'down',
        'button': 'left',
        'col': 1,
        'row': 2,
        'modifiers': <String>[],
      },
      {
        'type': 'mouse',
        'kind': 'moved',
        'button': 'none',
        'col': 3,
        'row': 1,
        'modifiers': <String>[],
      },
    ],
  },
  {
    'name': 'wheel up and down',
    'browserEvents': <TraceMap>[
      {
        'target': 'host',
        'event': 'wheel',
        'clientX': 15,
        'clientY': 25,
        'deltaY': -1,
      },
      {
        'target': 'host',
        'event': 'wheel',
        'clientX': 15,
        'clientY': 25,
        'deltaY': 1,
      },
    ],
    'expectedFleuryEvents': <TraceMap>[
      {
        'type': 'mouse',
        'kind': 'scrollUp',
        'button': 'none',
        'col': 0,
        'row': 0,
        'modifiers': <String>[],
      },
      {
        'type': 'mouse',
        'kind': 'scrollDown',
        'button': 'none',
        'col': 0,
        'row': 0,
        'modifiers': <String>[],
      },
    ],
  },
];
