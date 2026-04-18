const input = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
const filePath = input.tool_input?.file_path || '';
const patterns = [
  '.eslintrc', 'eslint.config', '.prettierrc', 'tsconfig.json', 'biome.json',
  '.github/workflows', 'jest.config', 'vitest.config', 'next.config',
  'tailwind.config', 'prisma/schema.prisma',
];
const hit = patterns.find(function(p) { return filePath.includes(p); });
if (hit) {
  console.log(JSON.stringify({ message: 'Modifying config: ' + hit + '. Ensure this is intentional.' }));
}
process.exit(0);
