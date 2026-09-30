import { build } from 'esbuild';
const options = { bundle: true, format: 'esm', minify: true, loader: { '.ttf': 'file', '.dart': 'text' }, outdir: '../.build/editor', logLevel: 'info' };
await build({ ...options, entryPoints: { main: 'web/main.js', 'editor.worker': 'monaco-editor/editor/editor.worker.js' } });
