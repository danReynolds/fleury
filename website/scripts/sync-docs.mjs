// Syncs canonical architecture docs from the repo's `docs/` folder into the
// Starlight content collection. The docs stay plain Markdown in `docs/` (where
// repo contributors find them); this step derives Starlight frontmatter from
// the H1, strips that H1, and rewrites inter-doc links to site routes.
//
// A doc may embed a LIVE example with an HTML-comment placeholder (invisible on
// GitHub):
//   <!-- fleury-example: linechart.basic | optional caption -->
// When present, the synced page is emitted as `.mdx` with the <FleuryExample>
// component so the doc demonstrates the very feature it documents.
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const DOCS_SRC = join(here, '..', '..', 'docs');
const OUT_DIR = join(here, '..', 'src', 'content', 'docs', 'architecture');
const COMPONENT = '../../../components/FleuryExample.astro';
const GITHUB = 'https://github.com/danReynolds/fleury/blob/main/docs';

const ROUTES = {
  'architecture-overview.md': '/architecture/overview/',
  'core-and-targets.md': '/architecture/core-and-targets/',
  'serving-and-embedding.md': '/architecture/serving-and-embedding/',
  'agents-and-semantics.md': '/architecture/agents-and-semantics/',
  'performance.md': '/architecture/performance/',
};

const DOCS = [
  {
    src: 'architecture-overview.md',
    out: 'overview.md',
    description:
      'How Fleury works under the hood: a retained four-tree pipeline ' +
      '(widget · element · render · semantics) and a platform-neutral core ' +
      'that paints a cell grid to a terminal or a browser.',
  },
  {
    src: 'core-and-targets.md',
    description:
      'How Fleury is layered: a platform-neutral core that produces a cell ' +
      'grid, plus pluggable targets that paint it to a terminal, the DOM, or ' +
      'a remote browser session.',
  },
  {
    src: 'serving-and-embedding.md',
    description:
      'Two ways to run Fleury in a browser — embed it client-side with ' +
      'dart2js, or serve it from a native process — and when to choose each.',
  },
  {
    src: 'agents-and-semantics.md',
    description:
      'Fleury produces a semantic app graph — roles, state, and actions — so ' +
      'tests and AI agents can drive the UI by meaning instead of scraping ANSI.',
  },
  {
    src: 'performance.md',
    description:
      'Why Fleury stays cheap as apps get busy: retained-mode incremental ' +
      'rebuilds, cell-level frame diffing, windowed data widgets, and a ' +
      'patch-stream browser wire.',
  },
];

const rewriteLinks = (md) =>
  md.replace(/\]\(([\w-]+)\.md(#[^)]*)?\)/g, (_m, file, anchor) => {
    const dest = ROUTES[`${file}.md`] ?? `${GITHUB}/${file}.md`;
    return `](${dest}${anchor ?? ''})`;
  });

// <!-- fleury-example: <id> [<cols>x<rows>] [| caption] -->
const EXAMPLE_RE =
  /<!--\s*fleury-example:\s*([\w.]+)(?:\s+(\d+)x(\d+))?\s*(?:\|\s*([^>]*?))?\s*-->/g;
const embedExamples = (md) =>
  md.replace(EXAMPLE_RE, (_m, id, cols, rows, caption) => {
    const size = cols && rows ? ` cols={${cols}} rows={${rows}}` : '';
    const title = caption ? ` title=${JSON.stringify(caption.trim())}` : '';
    return `<FleuryExample id="${id}"${size}${title} />`;
  });

// Start clean so a doc that switches .md <-> .mdx never leaves a stale twin.
rmSync(OUT_DIR, { recursive: true, force: true });
mkdirSync(OUT_DIR, { recursive: true });

for (const doc of DOCS) {
  const raw = readFileSync(join(DOCS_SRC, doc.src), 'utf8');
  const title = (raw.match(/^#\s+(.+)$/m)?.[1] ?? doc.src).trim();
  let body = rewriteLinks(raw.replace(/^#\s+.+\r?\n+/m, ''));

  const hasExample = EXAMPLE_RE.test(body);
  EXAMPLE_RE.lastIndex = 0; // reset after .test()
  const ext = hasExample ? 'mdx' : 'md';
  if (hasExample) body = embedExamples(body);

  const frontmatter =
    `---\n` +
    `title: ${JSON.stringify(title)}\n` +
    `description: ${JSON.stringify(doc.description)}\n` +
    `---\n\n` +
    (hasExample ? `import FleuryExample from '${COMPONENT}';\n\n` : '');

  const base = (doc.out ?? doc.src).replace(/\.md$/, '');
  writeFileSync(join(OUT_DIR, `${base}.${ext}`), frontmatter + body);
  console.log(`synced ${doc.src} -> architecture/${base}.${ext}`);
}
