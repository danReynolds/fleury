// The guides, grouped by what a reader is trying to do. One list drives both
// the sidebar (astro.config.mjs) and the guides overview page
// (src/components/GuideIndex.astro), so the two can't disagree.
export const GUIDE_GROUPS = [
  {
    label: 'Build the UI',
    items: [
      { label: 'Layout', slug: 'guides/layout' },
      { label: 'Lists & scrolling', slug: 'guides/lists-and-scrolling' },
      { label: 'Forms & validation', slug: 'guides/forms' },
      { label: 'Theming', slug: 'guides/theming' },
      { label: 'Animation', slug: 'guides/animation' },
    ],
  },
  {
    label: 'State, data & navigation',
    items: [
      { label: 'State management', slug: 'guides/state-management' },
      { label: 'Loading data', slug: 'guides/loading-data' },
      { label: 'Navigation & dialogs', slug: 'guides/navigation' },
    ],
  },
  {
    label: 'Input, focus & commands',
    items: [
      { label: 'Input & gestures', slug: 'guides/input-and-gestures' },
      { label: 'Key handling', slug: 'guides/focus-and-keyboard' },
      { label: 'Focus management', slug: 'guides/focus' },
      { label: 'Commands & shortcuts', slug: 'guides/commands' },
    ],
  },
  {
    label: 'Terminal apps',
    items: [
      { label: 'Full-screen & inline', slug: 'guides/terminal-modes' },
      { label: 'Shutdown & signals', slug: 'guides/shutdown-and-signals' },
      { label: 'Terminal capabilities', slug: 'guides/terminal-capabilities' },
      { label: 'Deployment & distribution', slug: 'guides/deployment' },
    ],
  },
  {
    label: 'Develop & debug',
    items: [
      { label: 'Testing', slug: 'guides/testing' },
      { label: 'Hot reload', slug: 'guides/hot-reload' },
      { label: 'Debugging', slug: 'guides/debugging' },
      { label: 'Driving with an agent (MCP)', slug: 'guides/driving-with-agents' },
    ],
  },
];
