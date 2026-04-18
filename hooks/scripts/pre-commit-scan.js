const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const cmd = input.tool_input?.command || '';
if (!/git\s+commit/.test(cmd)) { process.exit(0); }

const { execSync } = require('child_process');
try {
  const diff = execSync('git diff --cached --diff-filter=ACM', { encoding: 'utf8' });
  const issues = [];
  const warns = [];

  // \x60 = backtick — avoids shell command substitution when embedded in node -e "..."
  const secretPat = /\b(?:api[_-]?key|secret[_-]?key|password|token|credentials|private[_-]?key|client[_-]?secret)\b\s*[:=]\s*["'\x60][^"'\x60\s]{8,}/i;
  const secretPat2 = /\b(?:sk_live|sk_test|ghp_|gho_|github_pat_|xoxb-|xoxp-|AKIA[0-9A-Z]{16})\w+/;
  if (secretPat.test(diff) || secretPat2.test(diff)) issues.push('Possible hardcoded secret');

  let logs = 0;
  diff.split('\n').forEach(function(line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      if (/console\.log\(/.test(line)) logs++;
      if (/\bdebugger\b/.test(line)) issues.push('debugger statement found');
    }
  });

  if (logs > 0) warns.push(logs + ' console.log(s) \u2014 use structured logger');
  if (issues.length) {
    console.log(JSON.stringify({ decision: 'block', reason: 'Pre-commit scan failed:\n- ' + issues.join('\n- ') }));
  } else if (warns.length) {
    console.log(JSON.stringify({ message: 'Pre-commit warnings:\n- ' + warns.join('\n- ') }));
  }
} catch (e) {}
process.exit(0);
