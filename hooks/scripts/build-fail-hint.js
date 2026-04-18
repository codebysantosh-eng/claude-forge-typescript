const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const cmd = input.tool_input?.command || '';
const exitCode = input.tool_output?.exit_code || 0;
if (/npm run build|npx tsc|next build|npm run typecheck/.test(cmd) && exitCode !== 0) {
  console.log(JSON.stringify({ message: 'Build failed. Run /fix to resolve errors incrementally.' }));
}
process.exit(0);
