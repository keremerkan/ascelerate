// The translated homepages' markdown twins (build/<locale>/index.md). static/index.md is the
// English one, hand-written; docusaurus copies it into every locale, so each translated homepage
// advertised an English twin. These are built from the locale's own homepage strings
// (i18n/<locale>/code.json) and docs page titles, with the few lines the homepage doesn't have.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const text = {
  de: {
    openSource: 'Open Source', features: 'Funktionen', docs: 'Dokumentation', commands: 'Befehlsreferenz',
    docsIntro: (url) => `Die Dokumentation finden Sie unter ${url}. Jede Seite gibt es auch als Markdown: Hängen Sie \`.md\` an ihre URL an oder fordern Sie sie mit \`Accept: text/markdown\` an. Hier beginnen:`,
    languages: 'Die Dokumentation gibt es auf Englisch, Deutsch, Spanisch, Französisch, Japanisch und Türkisch.',
    footer: 'Entwickelt von [Kerem Erkan](https://keremerkan.dev). Nicht mit Apple Inc. verbunden. Apple, App Store, App Store Connect, Xcode und macOS sind Marken von Apple Inc.',
  },
  es: {
    openSource: 'Código abierto', features: 'Funciones', docs: 'Documentación', commands: 'Referencia de comandos',
    docsIntro: (url) => `La documentación está en ${url}. Cada página también está disponible en markdown: añada \`.md\` a su URL o pídala con \`Accept: text/markdown\`. Empiece aquí:`,
    languages: 'La documentación está disponible en inglés, alemán, español, francés, japonés y turco.',
    footer: 'Mantenido por [Kerem Erkan](https://keremerkan.dev). Sin relación con Apple Inc. Apple, App Store, App Store Connect, Xcode y macOS son marcas comerciales de Apple Inc.',
  },
  fr: {
    openSource: 'Open source', features: 'Fonctionnalités', docs: 'Documentation', commands: 'Référence des commandes',
    docsIntro: (url) => `La documentation se trouve sur ${url}. Chaque page existe aussi en markdown : ajoutez \`.md\` à son URL ou demandez-la avec \`Accept: text/markdown\`. Pour commencer :`,
    languages: "La documentation est disponible en anglais, allemand, espagnol, français, japonais et turc.",
    footer: "Maintenu par [Kerem Erkan](https://keremerkan.dev). Sans lien avec Apple Inc. Apple, App Store, App Store Connect, Xcode et macOS sont des marques d'Apple Inc.",
  },
  ja: {
    openSource: 'オープンソース', features: '機能', docs: 'ドキュメント', commands: 'コマンドリファレンス',
    docsIntro: (url) => `ドキュメントは ${url} にあります。各ページは、URL の末尾に \`.md\` を付けるか、\`Accept: text/markdown\` でリクエストすると Markdown でも取得できます。まずはこちら：`,
    languages: 'ドキュメントは英語、ドイツ語、スペイン語、フランス語、日本語、トルコ語で利用できます。',
    footer: '[Kerem Erkan](https://keremerkan.dev) が開発・管理しています。Apple Inc. とは関係ありません。Apple、App Store、App Store Connect、Xcode、macOS は Apple Inc. の商標です。',
  },
  tr: {
    openSource: 'Açık kaynak', features: 'Özellikler', docs: 'Dokümantasyon', commands: 'Komut başvurusu',
    docsIntro: (url) => `Dokümantasyon ${url} adresindedir. Her sayfa Markdown olarak da alınabilir: URL'sinin sonuna \`.md\` ekleyin veya \`Accept: text/markdown\` ile isteyin. Buradan başlayın:`,
    languages: 'Dokümantasyon İngilizce, Almanca, İspanyolca, Fransızca, Japonca ve Türkçe olarak sunulur.',
    footer: "[Kerem Erkan](https://keremerkan.dev) tarafından geliştirilmektedir. Apple Inc. ile bağlantılı değildir. Apple, App Store, App Store Connect, Xcode ve macOS, Apple Inc.'in ticari markalarıdır.",
  },
};

const features = ['pipeline', 'provisioning', 'media', 'iap', 'presence', 'reports', 'ads', 'workflows', 'ai'];
const pages = [
  ['getting-started/installation'], ['getting-started/setup'], ['commands/apps', 'commands'], ['guides/workflows'], ['guides/ai-skill'],
];

function title(root, locale, page) {
  const source = readFileSync(join(root, 'i18n', locale, 'docusaurus-plugin-content-docs', 'current', `${page}.md`), 'utf8');
  return source.match(/^title:\s*["']?(.+?)["']?\s*$/m)?.[1] ?? page;
}

export function writeHomepageTwins(root, build) {
  let written = 0;
  for (const [locale, t] of Object.entries(text)) {
    const codeFile = join(root, 'i18n', locale, 'code.json');
    if (!existsSync(join(build, locale))) continue;
    const code = JSON.parse(readFileSync(codeFile, 'utf8'));
    const m = (key) => code[key]?.message ?? '';
    const base = `https://ascelerate.dev/${locale}`;
    const lines = [
      '---',
      `title: ${JSON.stringify(`ascelerate: ${m('homepage.tagline')}`)}`,
      `description: ${JSON.stringify(m('homepage.meta.description'))}`,
      `canonical: ${base}/`,
      '---',
      '',
      '# ascelerate',
      '',
      `${m('homepage.tagline')}. ${m('homepage.hero.description')}`,
      '',
      `${t.openSource}: https://github.com/keremerkan/ascelerate`,
      '',
      `## ${m('homepage.install.title')}`,
      '',
      '```bash',
      '# Homebrew',
      'brew install ascelerate',
      '',
      '# curl',
      'curl -sSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash',
      '```',
      '',
      `## ${t.features}`,
      '',
      ...features.map((f) => `- **${m(`homepage.features.${f}.title`)}**: ${m(`homepage.features.${f}.description`)}`),
      '',
      `## ${t.docs}`,
      '',
      t.docsIntro(`${base}/docs/getting-started/installation`),
      '',
      ...pages.map(([page, label]) => `- [${label ? t[label] : title(root, locale, page)}](${base}/docs/${page}.md)`),
      '',
      t.languages,
      '',
      '---',
      '',
      t.footer,
      '',
    ];
    writeFileSync(join(build, locale, 'index.md'), lines.join('\n'));
    written += 1;
  }
  return written;
}
