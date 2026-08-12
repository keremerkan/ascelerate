#!/usr/bin/env node
// Copy every docs source .md into the build output as a "markdown twin"
// (build/docs/<path>.md and build/<locale>/docs/<path>.md). Agents get them
// via Accept: text/markdown content negotiation (functions/_middleware.js)
// or by fetching the .md URL directly. Runs after `docusaurus build`.
import { cpSync, statSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const build = join(root, 'build');

const targets = [
  { src: join(root, 'docs'), out: join(build, 'docs') },
  ...['de', 'fr', 'ja', 'tr'].map((l) => ({
    src: join(root, 'i18n', l, 'docusaurus-plugin-content-docs', 'current'),
    out: join(build, l, 'docs'),
  })),
];

const onlyMarkdown = (src) => statSync(src).isDirectory() || src.endsWith('.md');

function countMd(dir) {
  return readdirSync(dir, { recursive: true }).filter((f) => f.toString().endsWith('.md')).length;
}

let total = 0;
for (const { src, out } of targets) {
  if (!existsSync(src)) continue;
  cpSync(src, out, { recursive: true, filter: onlyMarkdown });
  total += countMd(src);
}
console.log(`[md-twins] ${total} markdown twins copied into build/`);
