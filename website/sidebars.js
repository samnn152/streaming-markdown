// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    {
      type: 'category',
      label: 'Getting Started',
      collapsed: false,
      items: [
        'index',
        'installation',
        'quick-start',
        'build-a-demo',
      ],
    },
    {
      type: 'category',
      label: 'Guides',
      collapsed: false,
      items: [
        'api-overview',
        'selection-copy',
        'migration-0-3',
      ],
    },
    {
      type: 'category',
      label: 'Project',
      collapsed: false,
      items: [
        'roadmap',
        'contributing',
      ],
    },
  ],
};

module.exports = sidebars;
