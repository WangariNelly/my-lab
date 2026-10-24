#!/usr/bin/env node
// Fail on broken relative links (files and #anchors) in tracked Markdown.
// External http(s) links are checked separately (lychee, non-blocking) because
// they are flaky; internal links must always resolve.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const root = resolve(dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const files = execFileSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.md"], { cwd: root })
  .toString()
  .split("\n")
  .filter(Boolean);

// GitHub-style heading slugs.
function slugify(text) {
  return text
    .trim()
    .toLowerCase()
    .replace(/<[^>]+>/g, "")
    .replace(/[`*_~[\]()]/g, "")
    .replace(/[^\p{L}\p{N}\s-]/gu, "")
    .replace(/\s/g, "-");
}

const anchorCache = new Map();
function anchorsOf(file) {
  if (anchorCache.has(file)) return anchorCache.get(file);
  const seen = new Map();
  const anchors = new Set();
  let inFence = false;
  for (const line of readFileSync(file, "utf8").split("\n")) {
    if (/^\s*(```|~~~)/.test(line)) inFence = !inFence;
    if (inFence) continue;
    const m = /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
    if (!m) continue;
    const base = slugify(m[1]);
    const n = seen.get(base) ?? 0;
    seen.set(base, n + 1);
    anchors.add(n ? `${base}-${n}` : base);
  }
  anchorCache.set(file, anchors);
  return anchors;
}

const linkRe = /(?<!!)\[(?:[^\]]|\][^(])*?\]\(([^)\s]+)(?:\s+"[^"]*")?\)|^\[[^\]]+\]:\s*(\S+)/gm;
const problems = [];

for (const rel of files) {
  const abs = join(root, rel);
  if (!existsSync(abs)) continue;
  const text = readFileSync(abs, "utf8").replace(/```[\s\S]*?```/g, (m) => m.replace(/[^\n]/g, " "));
  for (const match of text.matchAll(linkRe)) {
    const target = match[1] ?? match[2];
    if (!target || /^(https?:|mailto:|tel:|data:)/i.test(target)) continue;
    const [pathPart, anchor] = target.split("#");
    const decoded = decodeURIComponent(pathPart);
    const dest = decoded ? resolve(dirname(abs), decoded) : abs;
    const line = text.slice(0, match.index).split("\n").length;
    if (!existsSync(dest)) {
      problems.push(`${rel}:${line} → missing ${target}`);
      continue;
    }
    if (anchor && statSync(dest).isFile() && dest.endsWith(".md") && !anchorsOf(dest).has(anchor.toLowerCase())) {
      problems.push(`${rel}:${line} → missing anchor #${anchor} in ${decoded || rel}`);
    }
  }
}

if (problems.length) {
  console.error(`Broken internal links (${problems.length}):\n` + problems.join("\n"));
  process.exit(1);
}
console.log(`Internal links OK across ${files.length} Markdown files.`);
