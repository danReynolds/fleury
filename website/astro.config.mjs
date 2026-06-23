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
      // The product mark: leaf-F shown next to the wordmark in the header.
      logo: {
        src: './src/assets/fleury-icon.png',
        alt: 'Fleury',
      },
      // Primary favicon is the scalable SVG; the rest (ICO fallback, PNG sizes,
      // apple-touch, PWA manifest, social card) are added via head below.
      favicon: '/favicon.svg',
      head: [
        { tag: 'link', attrs: { rel: 'icon', href: '/favicon.ico', sizes: '32x32' } },
        { tag: 'link', attrs: { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32.png' } },
        { tag: 'link', attrs: { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16.png' } },
        { tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' } },
        { tag: 'link', attrs: { rel: 'manifest', href: '/site.webmanifest' } },
        { tag: 'meta', attrs: { name: 'theme-color', content: '#070d0b' } },
        { tag: 'meta', attrs: { property: 'og:image', content: 'https://fleury.dev/og.png' } },
        { tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
        { tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
        { tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' } },
        { tag: 'meta', attrs: { name: 'twitter:image', content: 'https://fleury.dev/og.png' } },
      ],
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
            { label: 'Tutorial: a filterable list', slug: 'tutorial' },
            { label: 'Why Fleury', slug: 'comparison' },
          ],
        },
        {
          label: 'Core concepts',
          items: [
            { label: 'Widgets & state', slug: 'concepts/widgets-and-state' },
            { label: 'App entry points', slug: 'concepts/app-entry' },
          ],
        },
        {
          label: 'Guides',
          items: [
            { label: 'Layout', slug: 'guides/layout' },
            { label: 'Theming', slug: 'guides/theming' },
            { label: 'Animation', slug: 'guides/animation' },
            { label: 'Focus & keyboard', slug: 'guides/focus-and-keyboard' },
            { label: 'Testing', slug: 'guides/testing' },
            { label: 'Deployment & distribution', slug: 'guides/deployment' },
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
