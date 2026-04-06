#!/usr/bin/env node
// @version: 1.0.0
// PostToolUse code intelligence — analyzes modified files for complexity,
// duplication, naming, and structure issues. Read-only; never modifies files.

'use strict';

const fs     = require('fs');
const path   = require('path');
const crypto = require('crypto');

// ─── Analysis: Method Complexity ────────────────────────────────────────────

function checkComplexity(lines, ext) {
  const issues = [];

  // Patterns that signal the start of a method/function body
  const isCS = ext === '.cs';
  const methodRE = isCS
    ? /^\s*(public|private|protected|internal|static|async|override|virtual|abstract)\b.*\w+\s*\([^)]*\)\s*(\{|$)/
    : /^\s*(export\s+)?(async\s+)?(?:function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[\w]+)\s*=>|(\w+)\s*\([^)]*\)\s*\{)/;

  let methodStart = -1;
  let methodName  = 'anonymous';
  let depth       = 0;
  let hasOpened   = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Try to detect a new method start when not already inside one
    if (methodStart === -1 && methodRE.test(line)) {
      const nm = line.match(
        /function\s+(\w+)|(?:const|let|var)\s+(\w+)|(?:public|private|protected|internal|override|virtual)\s+[\w<>[\]]+\s+(\w+)\s*\(|^\s*(\w+)\s*\([^)]*\)\s*\{/
      );
      methodName  = nm ? (nm[1] || nm[2] || nm[3] || nm[4] || 'anonymous') : 'anonymous';
      methodStart = i;
      depth       = 0;
      hasOpened   = false;
    }

    if (methodStart !== -1) {
      for (const ch of line) {
        if (ch === '{') { depth++; hasOpened = true; }
        if (ch === '}') depth--;
      }

      // Method closed
      if (hasOpened && depth === 0) {
        const len = i - methodStart + 1;
        if (len > 50) {
          issues.push({
            type: 'complexity',
            message: `Method '${methodName}' is ${len} lines — consider splitting into smaller functions`,
            line: methodStart + 1
          });
        }
        methodStart = -1;
      }
    }
  }

  return issues;
}

// ─── Analysis: Nesting Depth ────────────────────────────────────────────────

function checkNesting(lines) {
  const issues  = [];
  const condRE  = /^\s*(if|else\s+if|for|foreach|while|switch|catch)\s*[\({]/;
  const reported = new Set();

  let depth = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Count braces to track real depth
    for (const ch of line) {
      if (ch === '{') depth++;
      if (ch === '}') depth = Math.max(0, depth - 1);
    }

    if (condRE.test(line) && depth > 3) {
      // Deduplicate: one report per 10-line window
      const bucket = Math.floor(i / 10);
      if (!reported.has(bucket)) {
        reported.add(bucket);
        issues.push({
          type: 'complexity',
          message: `Nesting depth ${depth} exceeds 3 — consider early returns or extracting nested logic`,
          line: i + 1
        });
      }
    }
  }

  return issues;
}

// ─── Analysis: Duplication ──────────────────────────────────────────────────

function checkDuplication(lines) {
  const issues = [];
  const WINDOW = 8;

  // Strip blank lines and single-char lines; normalize whitespace
  const meaningful = [];
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (
      t.length > 10 &&
      !/^(\/\/|\/\*|\*|#|<!--)/.test(t) && // skip comment lines
      !/^(import|using|require|package)\b/.test(t)  // skip imports
    ) {
      meaningful.push({ content: t.replace(/\s+/g, ' '), line: i + 1 });
    }
  }

  if (meaningful.length < WINDOW * 2) return issues;

  const seen    = new Map(); // hash → first line number
  const flagged = new Set();

  for (let i = 0; i <= meaningful.length - WINDOW; i++) {
    const block = meaningful.slice(i, i + WINDOW).map(l => l.content).join('\n');
    const hash  = crypto.createHash('md5').update(block).digest('hex');

    if (seen.has(hash)) {
      const firstLine   = seen.get(hash);
      const currentLine = meaningful[i].line;

      // Must be genuinely separate (not sliding over same region)
      if (currentLine - firstLine >= WINDOW && !flagged.has(hash)) {
        flagged.add(hash);
        issues.push({
          type: 'duplication',
          message: `Duplicate block detected — similar to lines ${firstLine}–${firstLine + WINDOW - 1}`,
          line: currentLine
        });
        if (issues.filter(x => x.type === 'duplication').length >= 2) break;
      }
    } else {
      seen.set(hash, meaningful[i].line);
    }
  }

  return issues;
}

// ─── Analysis: Naming ───────────────────────────────────────────────────────

function checkNaming(lines, ext) {
  const issues = [];

  // Variable/field declaration keywords per language
  const declRE = ext === '.cs'
    ? /\b(?:var|int|string|bool|double|float|decimal|object|dynamic|long|byte)\s+([a-z_]\w*)\s*[=;,)]/g
    : /\b(?:const|let|var)\s+([a-z_]\w*)\s*[=;,)]/g;

  // Names considered non-descriptive
  const badNames = new Set([
    'a','b','c','d','e','f','g','h','m','n','o','p','q','r','s','t','u','v','w','x','y','z',
    'tmp','temp','data','obj','foo','bar','baz','val','res','ret','result','info','stuff','thing','item','elem','el'
  ]);

  // Loop lines are exempt (i, j, k as counters are conventional)
  const forRE = /^\s*for\s*\(/;
  let count   = 0;

  for (let i = 0; i < lines.length; i++) {
    if (count >= 3) break; // cap noise at 3 naming issues per file
    if (forRE.test(lines[i])) continue;

    let m;
    declRE.lastIndex = 0;
    while ((m = declRE.exec(lines[i])) !== null) {
      const name = m[1];
      if (badNames.has(name.toLowerCase())) {
        issues.push({
          type: 'naming',
          message: `Variable '${name}' is not descriptive — use a name that reflects its purpose`,
          line: i + 1
        });
        count++;
        if (count >= 3) break;
      }
    }
  }

  return issues;
}

// ─── Analysis: Structure ────────────────────────────────────────────────────

function checkStructure(lines, source) {
  const issues = [];

  // Large file
  if (lines.length > 500) {
    issues.push({
      type: 'structure',
      message: `File is ${lines.length} lines — consider splitting into focused modules`,
      line: 1
    });
  }

  // Mixed responsibilities heuristic — UI + data-access in same file
  const hasUI = /\b(render|component|jsx|innerHTML|querySelector|getElementById|template|v-if|ng-if)\b/i.test(source);
  const hasDB = /\b(query|execute|sql|dbContext|repository|connection|transaction|INSERT|SELECT|UPDATE|DELETE)\b/i.test(source);
  if (hasUI && hasDB) {
    issues.push({
      type: 'structure',
      message: 'File mixes UI rendering and data-access concerns — consider separating into distinct layers',
      line: 1
    });
  }

  // Large class (C#): class body > 500 lines
  const classMatch = source.match(/\bclass\s+\w+/g);
  if (classMatch && classMatch.length === 1 && lines.length > 500) {
    // Already reported above; skip duplicate
  } else if (classMatch && classMatch.length > 3) {
    issues.push({
      type: 'structure',
      message: `File defines ${classMatch.length} classes — consider one class per file`,
      line: 1
    });
  }

  return issues;
}

// ─── Main ────────────────────────────────────────────────────────────────────

const TOOL_INPUT = process.env.TOOL_INPUT || '';
if (!TOOL_INPUT) process.exit(0);

let payload;
try   { payload = JSON.parse(TOOL_INPUT); }
catch { process.exit(0); }

const filePath = payload.file_path || '';
if (!filePath) process.exit(0);

const SUPPORTED = new Set(['.cs', '.js', '.ts', '.jsx', '.tsx']);
const ext       = path.extname(filePath).toLowerCase();
if (!SUPPORTED.has(ext)) process.exit(0);

let stat, source;
try {
  stat = fs.statSync(filePath);
  if (stat.size > 1024 * 1024) process.exit(0);
  source = fs.readFileSync(filePath, 'utf8');
} catch { process.exit(0); }

const lines  = source.split('\n');
const issues = [
  ...checkComplexity(lines, ext),
  ...checkNesting(lines),
  ...checkDuplication(lines),
  ...checkNaming(lines, ext),
  ...checkStructure(lines, source)
];

if (issues.length > 0) {
  process.stdout.write(
    JSON.stringify({ files: [{ path: filePath, issues }] }, null, 2) + '\n'
  );
}

process.exit(0);
