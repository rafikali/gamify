#!/usr/bin/env node
//
// Bootstrap the first admin user in Firestore.
//
// Usage:
//   node admin/setup_first_admin.js <FIREBASE_UID> <EMAIL> [NAME]
//
// Example:
//   node admin/setup_first_admin.js aBcDeFgH123 ra3210304@gmail.com "Rafik"
//
// After running this, deploy the updated Firestore rules:
//   firebase deploy --only firestore:rules
//
// Then open admin/index.html in a browser and sign in with Google.

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'learnify-rafik-20260421';
const BASE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function getAccessToken() {
  const configDir = path.join(
    process.env.HOME || process.env.USERPROFILE,
    '.config',
    'configstore'
  );
  const tokenFile = path.join(configDir, 'firebase-tools.json');
  if (fs.existsSync(tokenFile)) {
    const config = JSON.parse(fs.readFileSync(tokenFile, 'utf8'));
    const token = config?.tokens?.access_token;
    if (token) return token;
  }
  try {
    return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
  } catch (_) {}
  throw new Error('No access token found. Run "firebase login" first.');
}

async function main() {
  const uid = process.argv[2];
  const email = process.argv[3];
  const name = process.argv[4] || null;

  if (!uid || !email) {
    console.error('Usage: node admin/setup_first_admin.js <UID> <EMAIL> [NAME]');
    console.error('\nTo find your UID:');
    console.error('  1. Open admin/index.html in a browser');
    console.error('  2. Sign in with Google');
    console.error('  3. Your UID will be shown on the "Access Denied" screen');
    process.exit(1);
  }

  const token = getAccessToken();
  const url = `${BASE_URL}/admins/${uid}`;

  const body = JSON.stringify({
    fields: {
      email: { stringValue: email },
      name: name ? { stringValue: name } : { nullValue: null },
      added_by: { stringValue: 'setup_script' },
      added_at: { stringValue: new Date().toISOString() },
    }
  });

  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body,
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Failed: ${res.status} ${err}`);
  }

  console.log(`\n  Admin created!`);
  console.log(`  UID:   ${uid}`);
  console.log(`  Email: ${email}`);
  console.log(`\nNext steps:`);
  console.log(`  1. Deploy rules:  firebase deploy --only firestore:rules`);
  console.log(`  2. Open admin/index.html in a browser`);
  console.log(`  3. Sign in with Google\n`);
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
