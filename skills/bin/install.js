#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");
const https = require("https");
const readline = require("readline");

const home = os.homedir();
const skillURL =
  "https://raw.githubusercontent.com/keremerkan/ascelerate/main/skills/ascelerate/SKILL.md";

const agents = [
  {
    name: "Claude Code",
    dir: path.join(home, ".claude", "skills", "ascelerate"),
    file: "SKILL.md",
    detect: path.join(home, ".claude"),
  },
  {
    name: "Cursor",
    dir: path.join(home, ".cursor", "rules"),
    file: "ascelerate.md",
    detect: path.join(home, ".cursor"),
  },
  {
    name: "Windsurf",
    dir: path.join(home, ".windsurf", "rules"),
    file: "ascelerate.md",
    detect: path.join(home, ".windsurf"),
  },
  {
    name: "GitHub Copilot",
    dir: path.join(home, ".github", "instructions"),
    file: "ascelerate.md",
    detect: null,
  },
];

function prompt(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function fetch(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          return fetch(res.headers.location).then(resolve, reject);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode} fetching skill file.`));
        }
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
        res.on("error", reject);
      })
      .on("error", reject);
  });
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes("--help") || args.includes("-h")) {
    console.log("Usage: npx ascelerate-skill [--uninstall]");
    console.log("");
    console.log("Install the ascelerate skill for AI coding agents.");
    console.log("Fetches the latest skill file from GitHub.");
    console.log("");
    console.log("Options:");
    console.log("  --uninstall  Remove the installed skill");
    console.log("  --help       Show this help message");
    return;
  }

  const uninstall = args.includes("--uninstall");

  // Detect installed agents
  const available = agents.filter(
    (a) => a.detect === null || fs.existsSync(a.detect)
  );

  if (available.length === 0) {
    console.log("No supported AI coding agents found.");
    console.log("Supported: Claude Code, Cursor, Windsurf, GitHub Copilot");
    process.exit(1);
  }

  // Show selection menu
  console.log(uninstall ? "Remove skill from:" : "Install skill for:");
  available.forEach((a, i) => {
    console.log(`  [${i + 1}] ${a.name}`);
  });
  console.log("");

  const answer = await prompt("Select agent: ");
  const index = parseInt(answer, 10) - 1;

  if (isNaN(index) || index < 0 || index >= available.length) {
    console.log("Canceled.");
    process.exit(0);
  }

  const agent = available[index];
  const target = path.join(agent.dir, agent.file);

  if (uninstall) {
    if (!fs.existsSync(target)) {
      console.log(`No skill installed at ${target}`);
      return;
    }
    fs.unlinkSync(target);
    console.log(`Removed ascelerate skill from ${target}`);
    return;
  }

  // Fetch latest skill from GitHub
  console.log("Fetching latest skill from GitHub...");
  const content = await fetch(skillURL);

  fs.mkdirSync(agent.dir, { recursive: true });
  fs.writeFileSync(target, content, "utf8");
  console.log(`Installed ascelerate skill for ${agent.name}.`);
  console.log(`  ${target}`);
}

main().catch((err) => {
  console.error(`Error: ${err.message}`);
  process.exit(1);
});
