import assert from 'node:assert/strict';
import test from 'node:test';

import { exportedClassNames } from './api-reference-exports.mjs';

const api = {
  Alpha: { file: 'packages/widgets/lib/src/alpha.dart' },
  AlphaModel: { file: 'packages/widgets/lib/src/alpha.dart' },
  Beta: { file: 'packages/widgets/lib/src/beta.dart' },
};

test('bare exports include every extracted public class from the target', () => {
  const names = exportedClassNames("export 'src/alpha.dart';", {
    barrelRepoDirectory: 'packages/widgets/lib',
    api,
  });

  assert.deepEqual([...names].sort(), ['Alpha', 'AlphaModel']);
});

test('show and hide clauses remain authoritative', () => {
  const barrel = `
    export 'src/alpha.dart' show Alpha;
    export 'src/beta.dart' hide Beta;
  `;
  const names = exportedClassNames(barrel, {
    barrelRepoDirectory: 'packages/widgets/lib',
    api,
  });

  assert.deepEqual([...names], ['Alpha']);
});
