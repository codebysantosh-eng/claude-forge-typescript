const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const cmd = input.tool_input?.command || '';
if (/--no-verify|--no-gpg-sign/.test(cmd) && /git\s+(commit|push|merge|rebase)/.test(cmd)) {
  console.log(JSON.stringify({
    decision: 'block',
    reason: 'Hook bypass flags are not allowed. Fix the underlying issue instead.',
  }));
}
process.exit(0);
