const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const content = input.tool_input?.new_string || input.tool_input?.content || '';
const filePath = input.tool_input?.file_path || '';
if (/\.(test|spec|stories)\.[jt]sx?$/.test(filePath)) { process.exit(0); }
if (/console\.log\(/.test(content)) {
  console.log(JSON.stringify({
    message: 'console.log detected in ' + filePath.split('/').pop() + '. Use structured logger instead.',
  }));
}
process.exit(0);
