// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
  site: 'https://fleury.dev',
  integrations: [
    starlight({
      title: 'Fleury',
      description:
        'A retained-mode UI framework for the terminal — and the browser.',
      // Drop the per-page table-of-contents site-wide; content goes full-width
      // (see the .sl-container override in fleury.css).
      tableOfContents: false,
      // Shared styling for embedded Fleury examples — must be site-wide so the
      // JS-created fullscreen overlay (appended to <body>, outside component
      // scope) and the knob pages get the same host font metrics + chrome.
      customCss: ['./src/styles/fleury.css'],
      sidebar: [
        {
          label: 'Start here',
          items: [
            { label: 'Introduction', slug: 'introduction' },
            { label: 'Getting started', slug: 'getting-started' },
            { label: 'How Fleury compares', slug: 'comparison' },
          ],
        },
        {
          label: 'Guides',
          items: [
            { label: 'Theming', slug: 'guides/theming' },
            { label: 'Animation & tickers', slug: 'guides/animation' },
            { label: 'Focus & keyboard', slug: 'guides/focus-and-keyboard' },
            { label: 'Testing', slug: 'guides/testing' },
          ],
        },
        {
          label: 'Architecture',
          items: [
            { label: 'Core and targets', slug: 'architecture/core-and-targets' },
            {
              label: 'Serving and embedding',
              slug: 'architecture/serving-and-embedding',
            },
            {
              label: 'Built for agents',
              slug: 'architecture/agents-and-semantics',
            },
            { label: 'Performance', slug: 'architecture/performance' },
          ],
        },
        {
          label: 'Widgets',
          items: [{ autogenerate: { directory: 'widgets' } }],
        },
        {
          label: 'Showcases',
          items: [{ autogenerate: { directory: 'showcases' } }],
        },
      ],
    }),
  ],
});
