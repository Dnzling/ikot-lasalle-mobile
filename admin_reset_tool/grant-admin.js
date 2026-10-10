import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const email = process.argv[2]?.trim();
if (!email || !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('Usage: set GOOGLE_APPLICATION_CREDENTIALS, then run: npm run grant-admin -- admin@example.com');
  process.exitCode = 1;
} else {
  initializeApp({ credential: applicationDefault(), projectId: 'ikot-lasalle-ccfab' });
  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  await auth.setCustomUserClaims(user.uid, { ...user.customClaims, admin: true });
  await auth.revokeRefreshTokens(user.uid);
  console.log(`Admin claim granted to ${email} (${user.uid}). Sign out and sign in again in the admin app.`);
}
