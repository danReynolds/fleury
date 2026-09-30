// Links the first inline-code mention of a widget on each page to its
// reference page, so a reader who meets `ListView` or `Scope.create` in a guide,
// a concepts page, or another widget's docs is one click from its API.
//
// The widget list comes from src/widget-sidebar.json, which
// scripts/gen-widget-pages.mjs writes alongside the reference pages. Mentions
// inside headings and existing links are left alone, and a page never links
// to itself.
import { existsSync, readFileSync } from 'node:fs';

const sidebarFile = new URL('../widget-sidebar.json', import.meta.url);

// `ListView`, `ListView.builder`, `ListView(…)`, `Scope<Cart>`, `Scope.create(…)`.
const MENTION = /^([A-Z][A-Za-z0-9]*)(?:<[^`]*>)?(?:\.[a-z][A-Za-z0-9]*)?(?:\(.*\))?$/s;

const widgetPages = () => {
  if (!existsSync(sidebarFile)) return new Map();
  const groups = JSON.parse(readFileSync(sidebarFile, 'utf8'));
  return new Map(groups.flatMap((group) => group.items.map((item) => [item.label, item.slug])));
};

export default function remarkWidgetLinks({ base = '' } = {}) {
  const pages = widgetPages();
  return (tree, file) => {
    if (pages.size === 0) return;
    const path = String(file.path ?? file.history?.[0] ?? '');
    const ownSlug = path.match(/content\/docs\/(.+?)(?:\/index)?\.mdx?$/)?.[1];
    const linked = new Set();
    const walk = (node) => {
      if (!node.children) return;
      node.children.forEach((child, index) => {
        if (child.type === 'link' || child.type === 'linkReference' || child.type === 'heading') return;
        if (child.type === 'inlineCode') {
          const name = child.value.match(MENTION)?.[1];
          const slug = name && pages.get(name);
          if (!slug || slug === ownSlug || linked.has(name)) return;
          linked.add(name);
          node.children[index] = { type: 'link', url: `${base}/${slug}/`, children: [child] };
          return;
        }
        walk(child);
      });
    };
    walk(tree);
  };
}
