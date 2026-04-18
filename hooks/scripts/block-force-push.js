const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const cmd = input.tool_input?.command || '';
if (/git\s+push.*--force(?!-)/.test(cmd)) {
  console.log(JSON.stringify({
    decision: 'block',
    reason: 'Force push blocked. Use --force-with-lease for safety.',
  }));
}
process.exit(0);
