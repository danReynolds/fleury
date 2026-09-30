// A view is either a whole file or an AST-selected region in a backing file.
// All edits are applied to the immutable originals, never by searching for text.
export class SourceProject {
  constructor(project) {
    this.project = project;
    this.views = project.views.map(view => {
      const source = project.files[view.file];
      if (typeof source !== 'string' || !Number.isInteger(view.start) || !Number.isInteger(view.end) || view.start < 0 || view.end < view.start || view.end > source.length) throw new Error('Invalid example source region.');
      const prefix = source.slice(source.lastIndexOf('\n', view.start - 1) + 1, view.start);
      const lines = source.slice(view.start, view.end).split('\n');
      const indents = lines.slice(1).filter(line => line.trim()).map(line => line.length - line.trimStart().length);
      const indent = ' '.repeat(indents.length ? Math.min(...indents) : prefix.length - prefix.trimStart().length);
      const text = lines.map((line, i) => i && line.startsWith(indent) ? line.slice(indent.length) : line).join('\n');
      return { ...view, indent, text };
    });
    if (!project.files['main.dart'] || new Set(this.views.map(v => v.id)).size !== this.views.length) throw new Error('Invalid example project.');
    for (const a of this.views) for (const b of this.views) {
      if (a !== b && a.file === b.file && a.start < b.end && b.start < a.end) throw new Error('Example source regions overlap.');
    }
  }
  snapshot(values) {
    const files = { ...this.project.files }, regions = [];
    for (const file of Object.keys(files)) {
      const source = files[file];
      let cursor = 0, output = '';
      for (const view of this.views.filter(v => v.file === file).sort((a, b) => a.start - b.start)) {
        const value = values[view.id] ?? view.text;
        const text = value.replaceAll('\n', `\n${view.indent}`);
        const before = `/* pad:${view.id}:start */`, after = `/* pad:${view.id}:end */`;
        output += source.slice(cursor, view.start) + before;
        regions.push({ ...view, value, start: output.length, end: output.length + text.length, before, after });
        output += text + after; cursor = view.end;
      }
      files[file] = output + source.slice(cursor);
    }
    function toFile(id, offset) {
      const region = regions.find(v => v.id === id);
      if (!region || offset < 0 || offset > region.value.length) return null;
      return region.start + offset + (region.value.slice(0, offset).match(/\n/g)?.length ?? 0) * region.indent.length;
    }
    function toView(file, offset) {
      const region = regions.find(v => v.file === file && offset >= v.start && offset <= v.end);
      if (!region) return null;
      const newlines = files[file].slice(region.start, offset).match(/\n/g)?.length ?? 0;
      return { id: region.id, offset: Math.max(0, Math.min(region.value.length, offset - region.start - newlines * region.indent.length)) };
    }
    function formatted(id, source) {
      const region = regions.find(v => v.id === id);
      const start = source.indexOf(region.before), end = source.indexOf(region.after);
      if (start < 0 || end < start || source.indexOf(region.before, start + 1) >= 0) throw new Error('Could not format this source region.');
      const lines = source.slice(start + region.before.length, end).trim().split('\n');
      const indents = lines.slice(1).filter(line => line.trim()).map(line => line.length - line.trimStart().length);
      const indent = indents.length ? Math.min(...indents) : 0;
      return lines.map((line, i) => i ? line.slice(Math.min(indent, line.length - line.trimStart().length)) : line).join('\n');
    }
    return { viewText: id => regions.find(v => v.id === id)?.value, files, source: files['main.dart'], fingerprint: JSON.stringify(files), toFile, toView, formatted };
  }
}
