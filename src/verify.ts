import * as fs from 'fs';
import * as path from 'path';

const ROOT_DIR = path.join(__dirname, '..');
const GROUND_TRUTH_DIR = path.join(ROOT_DIR, 'generated');
const OUTPUT_DIR = path.join(ROOT_DIR, 'generated-output');

function getAllFiles(dirPath: string, arrayOfFiles: string[] = []): string[] {
  if (!fs.existsSync(dirPath)) return arrayOfFiles;
  
  const files = fs.readdirSync(dirPath);

  files.forEach((file) => {
    const fullPath = path.join(dirPath, file);
    if (fs.statSync(fullPath).isDirectory()) {
      arrayOfFiles = getAllFiles(fullPath, arrayOfFiles);
    } else {
      arrayOfFiles.push(fullPath);
    }
  });

  return arrayOfFiles;
}

function verify() {
  console.log('Verifying generated outputs against ground truth...');

  if (!fs.existsSync(OUTPUT_DIR)) {
    console.error(`Error: Output directory ${OUTPUT_DIR} does not exist. Run generation first.`);
    process.exit(1);
  }

  const truthFiles = getAllFiles(GROUND_TRUTH_DIR);
  let hasDiff = false;

  for (const truthFile of truthFiles) {
    const relativePath = path.relative(GROUND_TRUTH_DIR, truthFile);
    // Exclude static scripts that are just provided as-is
    if (relativePath.includes('fabricx-up.sh')) {
      continue;
    }
    
    const outputFile = path.join(OUTPUT_DIR, relativePath);

    if (!fs.existsSync(outputFile)) {
      console.error(`\n❌ Missing file in output: ${relativePath}`);
      hasDiff = true;
      continue;
    }

    const truthContent = fs.readFileSync(truthFile, 'utf8').trim();
    const outputContent = fs.readFileSync(outputFile, 'utf8').trim();

    if (truthContent !== outputContent) {
      console.error(`\n❌ Mismatch found in: ${relativePath}`);
      
      const truthLines = truthContent.split('\n');
      const outputLines = outputContent.split('\n');
      
      const maxLines = Math.max(truthLines.length, outputLines.length);
      for (let i = 0; i < maxLines; i++) {
        if (truthLines[i] !== outputLines[i]) {
           console.log(`  Line ${i+1}:`);
           console.log(`  - Expected: ${truthLines[i] === undefined ? '<eof>' : truthLines[i]}`);
           console.log(`  + Actual  : ${outputLines[i] === undefined ? '<eof>' : outputLines[i]}`);
           // Just show the first differing line per file, to avoid overwhelming logs
           break;
        }
      }
      
      hasDiff = true;
    } else {
      console.log(` ✓ MATCH: ${relativePath}`);
    }
  }

  if (hasDiff) {
    console.error('\nVerification failed! Differences found.');
    process.exit(1);
  } else {
    console.log('\n✅ Verification passed! All generated files perfectly match the ground truth.');
    process.exit(0);
  }
}

try {
  verify();
} catch (error) {
  console.error('Unexpected error during verification:', error);
  process.exit(1);
}
