import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    {
      type: 'category',
      label: 'Getting Started',
      collapsed: false,
      items: [
        'getting-started/installation',
        'getting-started/setup',
        'getting-started/aliases',
      ],
    },
    {
      type: 'category',
      label: 'Commands',
      collapsed: false,
      items: [
        'commands/apps',
        'commands/builds',
        'commands/localizations',
        'commands/media',
        'commands/screenshots',
        'commands/app-info',
        'commands/iap',
        'commands/subscriptions',
        'commands/devices',
        'commands/certificates',
        'commands/bundle-ids',
        'commands/profiles',
      ],
    },
    {
      type: 'category',
      label: 'Guides',
      collapsed: false,
      items: [
        'guides/workflows',
        'guides/automation',
        'guides/ai-skill',
      ],
    },
  ],
};

export default sidebars;
