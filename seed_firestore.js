#!/usr/bin/env node
//
// Seeds Firestore with categories and words from firestore.seed.json
// using the Firestore REST API + Firebase CLI auth token.
//
// Run: node seed_firestore.js
//

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'learnify-rafik-20260421';
const BASE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function getAccessToken() {
  // Use the Firebase CLI's cached token
  const configDir = path.join(
    process.env.HOME || process.env.USERPROFILE,
    '.config',
    'configstore'
  );
  const tokenFile = path.join(configDir, 'firebase-tools.json');
  if (fs.existsSync(tokenFile)) {
    const config = JSON.parse(fs.readFileSync(tokenFile, 'utf8'));
    const token = config?.tokens?.access_token;
    const refreshToken = config?.tokens?.refresh_token;
    if (token) return token;
  }
  // Fallback: use gcloud
  try {
    return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
  } catch (_) {}
  throw new Error('No access token found. Run "firebase login" or "gcloud auth login" first.');
}

function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'string') return { stringValue: val };
  if (typeof val === 'number') {
    return Number.isInteger(val) ? { integerValue: String(val) } : { doubleValue: val };
  }
  if (typeof val === 'boolean') return { booleanValue: val };
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map(toFirestoreValue) } };
  }
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function buildDocument(data) {
  const fields = {};
  for (const [key, value] of Object.entries(data)) {
    fields[key] = toFirestoreValue(value);
  }
  return { fields };
}

async function writeDocument(collection, docId, data, token) {
  const url = `${BASE_URL}/${collection}/${docId}`;
  const body = JSON.stringify(buildDocument(data));

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
    throw new Error(`Failed to write ${collection}/${docId}: ${res.status} ${err}`);
  }
}

async function main() {
  const token = getAccessToken();
  const seedPath = path.join(__dirname, 'firestore.seed.json');
  const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

  console.log(`Seeding ${seed.categories.length} categories...`);
  for (const cat of seed.categories) {
    const { id, ...data } = cat;
    await writeDocument('categories', id, data, token);
    console.log(`  ✓ categories/${id}`);
  }

  console.log(`Seeding ${seed.words.length} words...`);
  for (const word of seed.words) {
    const { id, ...data } = word;
    await writeDocument('words', id, data, token);
    console.log(`  ✓ words/${id}`);
  }

  console.log('\nDone! All seed data written to Firestore.');
}

main().catch((err) => {
  console.error('Seed failed:', err.message);
  process.exit(1);
});
