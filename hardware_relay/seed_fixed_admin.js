import admin from 'firebase-admin';

const adminId = 'admin20260001';
const adminPassword = process.env.ADMIN_PASSWORD || '';

if (adminPassword.length < 6) {
  throw new Error('Set ADMIN_PASSWORD to the fixed admin password (at least 6 characters).');
}

const projectId = 'ikot-lasalle-2bed1';
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId,
});
const auth = admin.auth();
const db = admin.firestore();

const email = `admin_${Buffer.from(adminId.toUpperCase()).toString('base64url')}@${projectId}.firebaseapp.com`;
const aliasRef = db.collection('loginAliases').doc(adminId);
const aliasSnapshot = await aliasRef.get();
if (aliasSnapshot.exists && aliasSnapshot.data()?.email !== email) {
  throw new Error(`Admin ID ${adminId} is already assigned to a different login.`);
}

const profileSnapshot = await db.collection('users')
    .where('idNumber', '==', adminId).limit(1).get();
if (!aliasSnapshot.exists && !profileSnapshot.empty) {
  throw new Error(`Admin ID ${adminId} is already assigned to a different profile.`);
}

let user;
try {
  user = await auth.getUserByEmail(email);
} catch (error) {
  if (error.code !== 'auth/user-not-found') throw error;
}

if (!user) {
  if (aliasSnapshot.exists) {
    throw new Error('The admin login alias exists, but its Firebase Auth account is missing.');
  }
  user = await auth.createUser({
    email,
    password: adminPassword,
    displayName: 'Ikot La Salle Admin',
    emailVerified: true,
    disabled: false,
  });
} else if (!aliasSnapshot.exists || aliasSnapshot.data()?.uid !== user.uid) {
  throw new Error('A Firebase Auth account already uses the admin email without its matching login alias.');
} else {
  if (profileSnapshot.docs.some((doc) => doc.id !== user.uid)) {
    throw new Error(`Admin ID ${adminId} is already assigned to a different profile.`);
  }
  user = await auth.updateUser(user.uid, {password: adminPassword, disabled: false});
}

const now = admin.firestore.FieldValue.serverTimestamp();
const batch = db.batch();
batch.set(db.collection('users').doc(user.uid), {
  idNumber: adminId,
  userType: 'Admin',
  active: true,
  email,
  updatedAt: now,
  ...(!profileSnapshot.empty ? {} : {createdAt: now}),
}, {merge: true});
batch.set(aliasRef, {
  uid: user.uid,
  email,
  idNumber: adminId,
  userType: 'Admin',
  updatedAt: now,
  ...(!aliasSnapshot.exists ? {createdAt: now} : {}),
}, {merge: true});
await batch.commit();

console.log(`Fixed admin account is ready in ${projectId} (ID: ${adminId}).`);
