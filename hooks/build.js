#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const HOOKS_FILE = path.join(__dirname, 'hooks.json');
const SCRIPTS_DIR = path.join(__dirname, 'scripts');

function toInlineCommand(scriptId) {
  const scriptPath = path.join(SCRIPTS_DIR, scriptId + '.js');
  const source = fs.readFileSync(scriptPath, 'utf8');

  const oneLiner = source
    .replace(/^\s*\/\/[^\n]*/gm, '')  // strip whole-line comments
    .replace(/\n+/g, ' ')             // collapse newlines
    .replace(/\s{2,}/g, ' ')          // collapse extra whitespace
    .trim();

  // Shell-escape for embedding in: node -e "..."
  // \  →  \\  (must be first to avoid double-escaping)
  // "  →  \"  (would end the shell double-quoted string)
  const shellEscaped = oneLiner
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"');

  return 'node -e "' + shellEscaped + '"';
}

function rebuildHooks(hookList) {
  return hookList.map(function(hook) {
    const scriptPath = path.join(SCRIPTS_DIR, hook.id + '.js');
    if (!fs.existsSync(scriptPath)) {
      console.error('ERROR: No script found for hook id "' + hook.id + '" at ' + scriptPath);
      process.exit(1);
    }
    return Object.assign({}, hook, {
      hooks: hook.hooks.map(function(h) {
        return Object.assign({}, h, { command: toInlineCommand(hook.id) });
      }),
    });
  });
}

const config = JSON.parse(fs.readFileSync(HOOKS_FILE, 'utf8'));

const updated = Object.assign({}, config, {
  hooks: Object.fromEntries(
    Object.entries(config.hooks).map(function(entry) {
      return [entry[0], rebuildHooks(entry[1])];
    })
  ),
});

fs.writeFileSync(HOOKS_FILE, JSON.stringify(updated, null, 2) + '\n');
console.log('hooks.json rebuilt from hooks/scripts/ (' +
  Object.values(updated.hooks).flat().length + ' hooks)');
