const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const content = input.tool_input?.new_string || input.tool_input?.content || '';
const pat = /NEXT_PUBLIC_[A-Z_]*(SECRET|PASSWORD|PRIVATE|KEY|TOKEN|CREDENTIAL|API_KEY|CLIENT_SECRET)[A-Z_]*/gi;
const matches = Array.from(content.matchAll(pat));
if (matches.length) {
  const names = matches.map(function(m) { return m[0]; }).join(', ');
  console.log(JSON.stringify({
    decision: 'block',
    reason: 'NEXT_PUBLIC_ prefix exposes secrets to the browser: ' + names + '. Remove the NEXT_PUBLIC_ prefix \u2014 these must be server-only env vars.',
  }));
}
process.exit(0);
