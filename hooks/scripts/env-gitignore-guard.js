const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const filePath = input.tool_input?.file_path || '';
if (!/.env/.test(filePath) || /\.env\.example$|\.env\.template$/.test(filePath)) { process.exit(0); }
try {
  const gitignore = require('fs').readFileSync('.gitignore', 'utf8');
  if (!gitignore.includes('.env')) {
    console.log(JSON.stringify({
      message: 'WARNING: .env file modified but .env is not in .gitignore. Add it to prevent committing secrets.',
    }));
  }
} catch (e) {
  console.log(JSON.stringify({
    message: 'WARNING: .env file created but no .gitignore found. Create one with .env entry.',
  }));
}
process.exit(0);
