import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'ASCelerate',
  tagline: 'A Swift CLI for App Store Connect',
  favicon: 'img/favicon.svg',

  future: {
    v4: true,
  },

  url: 'https://ascelerate.dev',
  baseUrl: '/',

  organizationName: 'keremerkan',
  projectName: 'ascelerate',

  onBrokenLinks: 'throw',

  headTags: [
    {
      tagName: 'style',
      attributes: {},
      innerHTML: `html{background:#303846}#__docusaurus{background:#fff}[data-theme='dark'] #__docusaurus{background:#1b1b1d}`,
    },
  ],

  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'de', 'fr', 'ja', 'tr'],
    localeConfigs: {
      en: { label: 'English' },
      de: { label: 'Deutsch' },
      fr: { label: 'Français' },
      ja: { label: '日本語' },
      tr: { label: 'Türkçe' },
    },
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: undefined,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/social-card.webp',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      logo: {
        alt: 'ASCelerate',
        src: 'img/favicon.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          type: 'localeDropdown',
          position: 'right',
        },
        {
          href: 'https://github.com/keremerkan/ascelerate',
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
              label: 'Getting Started',
              to: '/docs/getting-started/installation',
            },
            {
              label: 'Commands',
              to: '/docs/commands/apps',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/keremerkan/ascelerate',
            },
            {
              label: 'asc-swift',
              href: 'https://github.com/aaronsky/asc-swift',
            },
          ],
        },
      ],
      copyright: `Maintained by <a href="https://keremerkan.dev" target="_blank" rel="noopener noreferrer">Kerem Erkan</a>.<br/>Not affiliated with Apple Inc. Apple, App Store, App Store Connect, Xcode, and macOS are trademarks of Apple Inc.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'json', 'swift'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
