// Copy vehicle documents with their IDs and all fields between Firebase projects.
// Dry run by default; pass --apply to write to the target project.
import {readFileSync} from 'node:fs';
import admin from 'firebase-admin';

function credential(path, label) {
  if (!path) throw new Error(`Set ${label} to a service-account JSON path.`);
  const data = JSON.parse(readFileSync(path, 'utf8'));
  if (data.type !== 'service_account' || !data.project_id) {
    throw new Error(`${label} is not a Firebase service-account JSON file.`);
  }
  return data;
}

const sourceKey = credential(process.env.SOURCE_FIREBASE_CREDENTIALS, 'SOURCE_FIREBASE_CREDENTIALS');
const targetKey = credential(process.env.TARGET_FIREBASE_CREDENTIALS, 'TARGET_FIREBASE_CREDENTIALS');
if (sourceKey.project_id === targetKey.project_id) {
  throw new Error('Source and target Firebase projects must differ.');
}
const targetProjectId = process.env.TARGET_PROJECT_ID;
if (!targetProjectId || targetKey.project_id !== targetProjectId) {
  throw new Error('TARGET_PROJECT_ID must match the target service-account project ID.');
}
const sourceApp = admin.initializeApp({credential: admin.credential.cert(sourceKey)}, 'vehicle-source');
const targetApp = admin.initializeApp({credential: admin.credential.cert(targetKey)}, 'vehicle-target');
const sourceDb = sourceApp.firestore();
const targetDb = targetApp.firestore();
const vehicleIds = ['CuoxcUom2JLXRq4qu33L', 'fVzHxxqNmYGYKd5gxmqi'];

const source = await Promise.all(vehicleIds.map((id) =>
  sourceDb.collection('vehicles').doc(id).get()));
if (source.some((doc) => !doc.exists)) {
  throw new Error('One of the two hardware vehicle documents is missing from the source.');
}
const target = await targetDb.collection('vehicles').get();
if (!target.empty) {
  throw new Error(`Target vehicles collection already has ${target.size} document(s); copy canceled to avoid overwriting.`);
}
console.log(`Source project: ${sourceKey.project_id}; target project: ${targetProjectId}.`);
console.log(`Vehicle documents to copy: ${source.length}.`);
console.log(`Vehicle document IDs: ${source.map((doc) => doc.id).join(', ')}.`);
if (!process.argv.includes('--apply')) {
  console.log('Dry run only. Pass --apply to copy all vehicle fields and IDs.');
  process.exit(0);
}

let batch = targetDb.batch();
let pending = 0;
let copied = 0;
for (const doc of source) {
  batch.create(targetDb.collection('vehicles').doc(doc.id), doc.data());
  pending++;
  if (pending === 400) {
    await batch.commit();
    copied += pending;
    batch = targetDb.batch();
    pending = 0;
  }
}
if (pending) {
  await batch.commit();
  copied += pending;
}
console.log(`Copied ${copied} vehicle document(s) with original IDs and fields.`);
