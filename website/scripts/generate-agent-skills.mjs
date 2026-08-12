#!/usr/bin/env node
// Publish the repo's AI skills at /.well-known/agent-skills/ (Agent Skills
// discovery convention, https://schemas.agentskills.io): copies each
// skills/<name>/SKILL.md into the build output and writes the index.json
// manifest with content digests. Runs after `docusaurus build`, so the
// published skills always match the repo's — no duplicated sources.
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const skillsSrc = join(root, '..', 'skills');
const outDir = join(root, 'build', '.well-known', 'agent-skills');

const SKILLS = ['ascelerate', 'app-store-screenshots'];

const entries = SKILLS.map((name) => {
  const body = readFileSync(join(skillsSrc, name, 'SKILL.md'));
  const description = /^description:\s*(.+)$/m.exec(body.toString())?.[1].trim() ?? '';
  mkdirSync(join(outDir, name), { recursive: true });
  writeFileSync(join(outDir, name, 'SKILL.md'), body);
  return {
    name,
    type: 'skill-md',
    description,
    url: `/.well-known/agent-skills/${name}/SKILL.md`,
    digest: `sha256:${createHash('sha256').update(body).digest('hex')}`,
  };
});

const index = { $schema: 'https://schemas.agentskills.io/discovery/0.2.0/schema.json', skills: entries };
writeFileSync(join(outDir, 'index.json'), JSON.stringify(index, null, 2) + '\n');
console.log(`[agent-skills] published ${entries.length} skills to /.well-known/agent-skills/`);
