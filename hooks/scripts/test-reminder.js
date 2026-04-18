try {
  const { execSync } = require('child_process');
  const output = execSync('git diff --name-only --diff-filter=ACM HEAD 2>/dev/null', { encoding: 'utf8' });
  const files = output.trim().split('\n').filter(Boolean);
  const src = files.filter(function(f) {
    return /\.[jt]sx?$/.test(f) && !/\.(test|spec|stories)\./.test(f) && !/config/.test(f);
  });
  const tests = files.filter(function(f) { return /\.(test|spec)\.[jt]sx?$/.test(f); });
  if (src.length > 0 && tests.length === 0) {
    console.log(JSON.stringify({
      message: 'Source files changed but no test files modified. Did you add tests? Run /tdd to add coverage.',
    }));
  }
} catch (e) {}
process.exit(0);
