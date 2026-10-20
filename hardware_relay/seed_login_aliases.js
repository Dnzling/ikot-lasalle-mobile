// Run once with GOOGLE_APPLICATION_CREDENTIALS before publishing the new rules.
// Aliases contain only an ID-to-auth-email mapping and are readable by ID,
// never as a collection query.
import admin from 'firebase-admin';

admin.initializeApp({credential: admin.credential.applicationDefault()});
const db = admin.firestore();
const users = await db.collection('users').get();
const aliases = new Map();
const duplicateIds = new Set();
const inactiveUids = new Set();
for (const user of users.docs) {
  if (user.data().active === false || user.data().archived === true) {
    inactiveUids.add(user.id);
    continue;
  }
  const id = String(user.data().idNumber || '').trim();
  const email = String(user.data().email || '').trim().toLowerCase();
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(id) || !email.includes('@')) continue;
  if (aliases.has(id) && aliases.get(id).uid !== user.id) duplicateIds.add(id);
  aliases.set(id, {email, uid: user.id});
}
let batch = db.batch();
let pending = 0;
let total = 0;
for (const [id, alias] of aliases) {
  if (duplicateIds.has(id)) continue;
  batch.set(db.collection('loginAliases').doc(id), alias);
  pending++;
  total++;
  if (pending === 400) {
    await batch.commit();
    batch = db.batch();
    pending = 0;
  }
}
if (pending) await batch.commit();
const existingAliases = await db.collection('loginAliases').get();
let removed = 0;
for (const existing of existingAliases.docs) {
  if (!inactiveUids.has(existing.data().uid) || aliases.has(existing.id)) continue;
  await existing.ref.delete();
  removed++;
}
console.log(`Created ${total} login aliases.`);
console.log(`Removed ${removed} aliases for inactive accounts.`);
if (duplicateIds.size) {
  console.error(`Skipped duplicate ID numbers: ${[...duplicateIds].join(', ')}. Resolve these before publishing restrictive rules.`);
  process.exitCode = 1;
}
