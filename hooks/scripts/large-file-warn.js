const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const filePath = input.tool_input?.file_path;
if (!filePath) { process.exit(0); }
try {
  const lines = require('fs').readFileSync(filePath, 'utf8').split('\n').length;
  if (lines > 800) {
    console.log(JSON.stringify({
      message: filePath.split('/').pop() + ' is ' + lines + ' lines (limit: 800). Consider splitting by responsibility.',
    }));
  }
} catch (e) {}
process.exit(0);
