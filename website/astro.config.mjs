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
        "Flutter's architecture, rebuilt for the terminal — and the browser.",
      sidebar: [
        {
          label: 'Start here',
          items: [
            { label: 'Introduction', slug: 'introduction' },
            { label: 'Getting started', slug: 'getting-started' },
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
