import { randomBytes } from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const requestId = process.argv[2];
if (!requestId || requestId.includes('/') || !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('Usage: set GOOGLE_APPLICATION_CREDENTIALS to the private service-account JSON path, then run: npm run reset -- <request-id>');
  process.exitCode = 1;
} else {
  await run(requestId);
}

function same(a, b) {
  return String(a ?? '').trim().toLocaleLowerCase() ===
    String(b ?? '').trim().toLocaleLowerCase();
}

async function run(id) {
  initializeApp({ credential: applicationDefault(), projectId: 'ikot-lasalle-ccfab' });
  const db = getFirestore();
  const auth = getAuth();
  const requestRef = db.collection('passwordResetRequests').doc(id);
  const request = await requestRef.get();
  if (!request.exists || request.data().status !== 'pending') {
    throw new Error('Request does not exist or is no longer pending.');
  }
  const submitted = request.data();
  const matches = await db.collection('users')
    .where('idNumber', '==', submitted.idNumber).limit(2).get();
  if (matches.size !== 1) throw new Error('No unique user matches the ID number. Do not reset.');
  const userDoc = matches.docs[0];
  const user = userDoc.data();
  if (!['Student', 'Teacher', 'Visitor', 'Staff'].includes(user.userType)) {
    throw new Error('Only passenger accounts can be reset with this tool.');
  }
  if (!same(submitted.firstName, user.firstName) ||
      !same(submitted.lastName, user.lastName) ||
      !same(submitted.contactNumber, user.contactNumber ?? user.phone)) {
    throw new Error('Submitted details do not match the user profile. Do not reset.');
  }
  console.log(`Request: ${id}`);
  console.log(`Passenger: ${user.firstName} ${user.lastName} | ID: ${user.idNumber} | Contact: ${user.contactNumber ?? user.phone}`);
  console.log('Verify the passenger in person and check their physical ID before continuing.');
  const prompt = createInterface({ input: stdin, output: stdout });
  let answer;
  try {
    answer = await prompt.question(`Type RESET ${user.idNumber} to confirm: `);
  } finally {
    prompt.close();
  }
  if (answer !== `RESET ${user.idNumber}`) {
    console.log('Canceled; no password was changed.');
    return;
  }
  await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(requestRef);
    if (latest.data()?.status !== 'pending') throw new Error('Request is no longer pending.');
    transaction.update(requestRef, {
      status: 'processing',
      processingAt: FieldValue.serverTimestamp(),
    });
  });
  const temporaryPassword = `T!${randomBytes(12).toString('base64url')}`;
  let passwordChanged = false;
  try {
    await auth.updateUser(userDoc.id, { password: temporaryPassword });
    passwordChanged = true;
    await auth.revokeRefreshTokens(userDoc.id);
    const batch = db.batch();
    batch.update(userDoc.ref, {
      mustChangePassword: true,
      passwordChangedAt: FieldValue.serverTimestamp(),
      'session.active': false,
      'session.endReason': 'passwordReset',
      'session.endedAt': FieldValue.serverTimestamp(),
    });
    const activeSessionId = user.session?.id;
    if (activeSessionId) {
      batch.set(userDoc.ref.collection('sessions').doc(activeSessionId), {
        active: false,
        endReason: 'passwordReset',
        endedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    batch.update(requestRef, {
      status: 'completed',
      completedAt: FieldValue.serverTimestamp(),
      passengerUid: userDoc.id,
    });
    await batch.commit();
    console.log(`Reset complete. Give this one-time temporary password to the passenger in person: ${temporaryPassword}`);
    console.log('The passenger must change it at next login. Do not save or send it over chat.');
  } catch (error) {
    if (passwordChanged) {
      console.error('Auth password changed, but finalization failed. Keep this temporary password securely for recovery:', temporaryPassword);
      console.error('Request is in processing state. Resolve manually before another reset.');
    } else {
      await requestRef.update({ status: 'pending', processingAt: FieldValue.delete() });
    }
    throw error;
  }
}
