import test from 'node:test';
import assert from 'node:assert/strict';
import { SourceProject } from '../web/source-project.mjs';
const source = `import 'view.dart';\nWidget buildApp() =>\n  Text('First');\nString label() => 'Last';\n`;
const project = { files: { 'main.dart': source, 'view.dart': 'class View {}\n' }, views: [
  { id: 'widget', file: 'main.dart', label: 'Widget', start: source.indexOf('Text('), end: source.indexOf(';', source.indexOf('Text(')) },
  { id: 'label', file: 'main.dart', label: 'Label', start: source.indexOf("'Last'"), end: source.indexOf("'Last'") + 6 },
  { id: 'file', file: 'view.dart', label: 'View', start: 0, end: 14 },
] };
test('multiple region edits preserve all backing code and other libraries', () => {
 const p = new SourceProject(project), s = p.snapshot({ widget: "Column(\n  children: [Text('Changed')],\n)", label: "'New label'" });
 assert.match(s.source, /Widget buildApp\(\)/); assert.match(s.source, /Text\('Changed'\)/); assert.match(s.source, /'New label'/);
 assert.match(s.files['view.dart'], /class View/); assert.equal(project.files['main.dart'], source);
 for (const id of ['widget', 'label', 'file']) {
   const value = ({ widget: "Column(\n  children: [Text('Changed')],\n)", label: "'New label'" })[id] ?? p.views.find(v=>v.id===id).text;
   for(let offset=0;offset<=value.length;offset++) assert.deepEqual(s.toView(id==='file'?'view.dart':'main.dart', s.toFile(id,offset)),{id,offset});
 }
 assert.equal(s.toView('main.dart', 1), null);
});
test('errors stay mapped after an earlier region changes length', () => {
 const p=new SourceProject(project), s=p.snapshot({widget:"Text('Much longer than before')",label:'unknownName'});
 assert.deepEqual(s.toView('main.dart',s.source.indexOf('unknownName')),{id:'label',offset:0});
 assert.equal(s.toFile('label',4),s.source.indexOf('unknownName')+4);
});
test('format extracts only the selected region, keeping nested indentation', () => {
 const p=new SourceProject(project), s=p.snapshot({widget:'Column(children: [Text("x")])'});
 const formatted=s.files['main.dart'].replace('Column(children: [Text("x")])','Column(\n    children: [Text("x")],\n  )');
 assert.equal(s.formatted('widget',formatted),'Column(\n  children: [Text("x")],\n)');
 assert.throws(()=>s.formatted('widget','not the same file'));
});
test('overlapping or missing backing regions fail at construction', () => {
 assert.throws(()=>new SourceProject({...project,views:[...project.views,project.views[0]]}));
 assert.throws(()=>new SourceProject({...project,views:[{id:'bad',file:'missing.dart',start:0,end:1}]}));
});
