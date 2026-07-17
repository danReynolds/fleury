import { posix } from 'node:path';

const directivePattern = /export\s+(['"])([^'"]+)\1([\s\S]*?);/g;

/// Returns the public class names exported by a Dart barrel.
///
/// `show` clauses are authoritative. Bare exports (and exports with only a
/// `hide` clause) are resolved through the API extractor's source-file
/// metadata, which keeps the coverage gate honest when a barrel stops spelling
/// out every class name.
export function exportedClassNames(
  barrel,
  { barrelRepoDirectory, api }
) {
  const exported = new Set();
  for (const match of barrel.matchAll(directivePattern)) {
    const source = posix.normalize(posix.join(barrelRepoDirectory, match[2]));
    const clause = match[3];
    const shown = clause.match(/\bshow\s+([\s\S]*?)(?=\bhide\b|$)/);
    if (shown) {
      for (const name of _names(shown[1])) exported.add(name);
      continue;
    }

    const hidden = new Set(
      _names(clause.match(/\bhide\s+([\s\S]*?)$/)?.[1] ?? '')
    );
    for (const [name, entry] of Object.entries(api)) {
      if (entry.file === source && !hidden.has(name)) exported.add(name);
    }
  }
  return exported;
}

function _names(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/.*$/gm, '')
    .split(',')
    .map((name) => name.trim())
    .filter(Boolean);
}
