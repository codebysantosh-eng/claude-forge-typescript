const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const cmd = input.tool_input?.command || '';
const stdout = input.tool_output?.stdout || '';

if (!/jest|vitest|coverage/.test(cmd)) { process.exit(0); }

// Match jest/vitest Istanbul summary row: "All files | 75.00 | ..."
const match = stdout.match(/All files\s*\|\s*([\d.]+)/);
if (!match) { process.exit(0); }

const pct = parseFloat(match[1]);
if (pct < 80) {
  console.log(JSON.stringify({
    message: 'Coverage ' + pct + '% is below the 80% general target. See rules/testing.md for per-category targets (auth: 100%, utils: 90%).',
  }));
}
process.exit(0);
