// @ts-check

const lightCodeTheme = require('prism-react-renderer').themes.github;
const darkCodeTheme = require('prism-react-renderer').themes.dracula;

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'animated_streaming_markdown',
  tagline: 'Streaming Markdown parser and animated Flutter renderer.',
  favicon: 'img/logo.svg',

  url: 'https://samnn.dev',
  baseUrl: '/',
  organizationName: 'samnn152',
  projectName: 'streaming-markdown',
  trailingSlash: false,

  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          path: '../docs',
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl:
            'https://github.com/samnn152/streaming-markdown/edit/dev/docs/',
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/logo.svg',
      navbar: {
        title: 'animated_streaming_markdown',
        logo: {
          alt: 'animated_streaming_markdown logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'docs',
            position: 'left',
            label: 'Docs',
          },
          {
            href: 'https://pub.dev/packages/animated_streaming_markdown',
            label: 'pub.dev',
            position: 'right',
          },
          {
            href: 'https://github.com/samnn152/streaming-markdown',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              {
                label: 'Installation',
                to: '/installation',
              },
              {
                label: 'Build a Demo',
                to: '/build-a-demo',
              },
              {
                label: 'Migration 0.3',
                to: '/migration-0-3',
              },
            ],
          },
          {
            title: 'Project',
            items: [
              {
                label: 'GitHub',
                href: 'https://github.com/samnn152/streaming-markdown',
              },
              {
                label: 'Issues',
                href: 'https://github.com/samnn152/streaming-markdown/issues',
              },
              {
                label: 'API Reference',
                href: 'https://pub.dev/documentation/animated_streaming_markdown/latest/',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} animated_streaming_markdown.`,
      },
      prism: {
        theme: lightCodeTheme,
        darkTheme: darkCodeTheme,
        additionalLanguages: ['dart', 'yaml'],
      },
      colorMode: {
        defaultMode: 'light',
        respectPrefersColorScheme: true,
      },
    }),
};

module.exports = config;
