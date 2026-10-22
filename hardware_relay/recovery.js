import crypto from 'node:crypto';

const ipWindows = new Map();

function cleanEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function validEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function requireBrevo() {
  const apiKey = process.env.BREVO_API_KEY;
  const senderEmail = cleanEmail(process.env.BREVO_SENDER_EMAIL);
  if (!apiKey || !validEmail(senderEmail)) {
    throw new Error('Recovery email is not configured. Set BREVO_API_KEY and BREVO_SENDER_EMAIL.');
  }
  return {apiKey, senderEmail,
    senderName: process.env.BREVO_SENDER_NAME || 'Ikot La Salle'};
}

function appUrl() {
  const value = process.env.APP_PUBLIC_URL || 'https://ikot-lasalle-mobile.onrender.com';
  const url = new URL(value);
  if (url.protocol !== 'https:') throw new Error('APP_PUBLIC_URL must use HTTPS.');
  return url.origin;
}

function limit(key, max, windowMs) {
  const now = Date.now();
  // Keep this best-effort in-memory limiter bounded on a public endpoint.
  if (ipWindows.size > 10000) {
    for (const [entry, value] of ipWindows) {
      if (now - value.start >= windowMs) ipWindows.delete(entry);
    }
    while (ipWindows.size > 10000) ipWindows.delete(ipWindows.keys().next().value);
  }
  const current = ipWindows.get(key);
  if (!current || now - current.start >= windowMs) {
    ipWindows.set(key, {start: now, count: 1});
    return;
  }
  current.count++;
  if (current.count > max) throw new Error('Too many attempts. Please try again later.');
}

function ipKey(req) {
  return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '')
    .split(',')[0].trim();
}

async function sendBrevo({to, subject, html, text}) {
  const {apiKey, senderEmail, senderName} = requireBrevo();
  const response = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {'api-key': apiKey, 'content-type': 'application/json'},
    signal: AbortSignal.timeout(15000),
    body: JSON.stringify({
      sender: {name: senderName, email: senderEmail},
      to: [{email: to}], subject, htmlContent: html, textContent: text,
    }),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    throw new Error(`Brevo email delivery failed (${response.status}): ${detail}`);
  }
}

export async function startRecoveryEmailVerification({admin, db, uid, email, req}) {
  const target = cleanEmail(email);
  if (!validEmail(target)) throw new Error('Enter a valid recovery email address.');
  requireBrevo();
  const verificationUrl = appUrl();
  limit(`verify:${uid}`, 3, 60 * 60 * 1000);
  const userRef = db.collection('users').doc(uid);
  const snapshot = await userRef.get();
  const user = snapshot.data();
  if (!user || user.active === false || !['Student', 'Passenger'].includes(user.userType)) {
    throw new Error('Passenger account is unavailable.');
  }
  const token = crypto.randomBytes(32).toString('base64url');
  const tokenRef = db.collection('recoveryEmailTokens')
    .doc(crypto.createHash('sha256').update(token).digest('hex'));
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 60 * 1000);
  await db.runTransaction(async (tx) => {
    const current = await tx.get(userRef);
    if (!current.exists || current.data().active === false) {
      throw new Error('Passenger account is unavailable.');
    }
    tx.set(tokenRef, {uid, email: target, expiresAt,
      createdAt: admin.firestore.FieldValue.serverTimestamp()});
    tx.update(userRef, {pendingRecoveryEmail: target,
      recoveryEmailVerificationSentAt: admin.firestore.FieldValue.serverTimestamp()});
  });
  const link = `${verificationUrl}/verify-recovery-email?token=${encodeURIComponent(token)}`;
  try {
    await sendBrevo({to: target, subject: 'Verify your Ikot La Salle recovery email',
      text: `Confirm this email as your password recovery address: ${link}\nThis link expires in 30 minutes.`,
      html: `<p>Confirm this email as your Ikot La Salle password recovery address.</p><p><a href="${link}">Verify recovery email</a></p><p>This link expires in 30 minutes. If you did not request this, ignore this message.</p>`});
  } catch (error) {
    await tokenRef.delete().catch(() => {});
    await userRef.update({pendingRecoveryEmail: admin.firestore.FieldValue.delete()}).catch(() => {});
    throw error;
  }
  return {ok: true};
}

export async function requestRecoveryPasswordReset({admin, db, email, req}) {
  const target = cleanEmail(email);
  limit(`reset-ip:${ipKey(req)}`, 10, 60 * 60 * 1000);
  if (validEmail(target)) {
    const emailKey = crypto.createHash('sha256').update(target).digest('hex');
    limit(`reset-email:${emailKey}`, 5, 60 * 60 * 1000);
  }
  if (validEmail(target)) {
    try {
      const matches = await db.collection('users').where('recoveryEmail', '==', target).limit(10).get();
      const profile = matches.docs.find((doc) => doc.data().recoveryEmailVerified === true &&
        doc.data().active !== false);
      if (profile) {
        const user = await admin.auth().getUser(profile.id);
        if (user.email) {
          const firebaseLink = new URL(await admin.auth().generatePasswordResetLink(user.email));
          const oobCode = firebaseLink.searchParams.get('oobCode');
          const apiKey = firebaseLink.searchParams.get('apiKey');
          if (!oobCode || !apiKey) throw new Error('Firebase did not create a valid reset action link.');
          const resetRef = db.collection('recoveryPasswordResetTokens').doc(hashToken(oobCode));
          await resetRef.set({uid: profile.id, email: target, apiKey,
            expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
            createdAt: admin.firestore.FieldValue.serverTimestamp()});
          const resetLink = `${appUrl()}/reset-password?oobCode=${encodeURIComponent(oobCode)}`;
          try {
          await sendBrevo({to: target, subject: 'Reset your Ikot La Salle password',
            text: `Use this secure link to reset your password: ${resetLink}\nAfter resetting, sign in with your passenger ID. If you did not request this, ignore this message.`,
            html: `<p>A password reset was requested for your Ikot La Salle account.</p><p><a href="${resetLink}">Reset password</a></p><p>After resetting, sign in with your passenger ID.</p><p>If you did not request this, ignore this message.</p>`});
          } catch (error) {
            await resetRef.delete().catch(() => {});
            throw error;
          }
        }
      }
    } catch (error) {
      // Return the same response for unknown addresses and delivery failures.
      console.error('Password recovery request could not be delivered:', error.message);
    }
  }
  return {ok: true, message: 'If this address is a verified recovery email, a reset link has been sent.'};
}

export async function handleRecoveryEmailAction(req, res, {admin, db}) {
  const url = new URL(req.url, 'http://localhost');
  if (!['/verify-recovery-email', '/reset-password'].includes(url.pathname)) return false;
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  if (url.pathname === '/reset-password') {
    return handlePasswordResetPage(req, res, {admin, db, url});
  }
  if (req.method === 'GET') {
    const token = url.searchParams.get('token') || '';
    if (!/^[A-Za-z0-9_-]{40,50}$/.test(token)) {
      res.writeHead(400).end(actionPage('Invalid verification link', 'Request a new recovery-email verification link in the app.'));
      return true;
    }
    res.writeHead(200).end(actionPage('Verify recovery email',
      'Select the button below to confirm this address for password recovery.',
      `<form method="post" action="/verify-recovery-email"><input type="hidden" name="token" value="${token}"><button type="submit">Verify recovery email</button></form>`));
    return true;
  }
  if (req.method !== 'POST') {
    res.writeHead(405).end(actionPage('Method not allowed', 'Return to the app and try again.'));
    return true;
  }
  try {
    const raw = await readBody(req, 1024);
    const token = new URLSearchParams(raw).get('token') || '';
    if (!/^[A-Za-z0-9_-]{40,50}$/.test(token)) throw new Error('Verification link is invalid or expired.');
    const hash = crypto.createHash('sha256').update(token).digest('hex');
    const tokenRef = db.collection('recoveryEmailTokens').doc(hash);
    await db.runTransaction(async (tx) => {
      const tokenDoc = await tx.get(tokenRef);
      const data = tokenDoc.data();
      if (!data) {
        throw new Error('Verification token was not found. Request a new link in the app.');
      }
      const expiry = data.expiresAt?.toMillis?.();
      if (!expiry) {
        throw new Error('Verification token is missing its expiration time. Request a new link.');
      }
      if (expiry <= Date.now()) {
        throw new Error('Verification link has expired. Request a new link in the app.');
      }
      const userRef = db.collection('users').doc(data.uid);
      const userDoc = await tx.get(userRef);
      if (!userDoc.exists || userDoc.data().pendingRecoveryEmail !== data.email) {
        throw new Error('This verification request is no longer current. Request a new link in the app.');
      }
      const duplicates = await tx.get(db.collection('users')
        .where('recoveryEmail', '==', data.email).limit(10));
      if (duplicates.docs.some((doc) => doc.id !== data.uid &&
          doc.data().recoveryEmailVerified === true && doc.data().active !== false)) {
        throw new Error('This recovery email is already linked to another active account.');
      }
      tx.update(userRef, {recoveryEmail: data.email, recoveryEmailVerified: true,
        recoveryEmailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        pendingRecoveryEmail: admin.firestore.FieldValue.delete()});
      tx.delete(tokenRef);
    });
    res.writeHead(200).end(actionPage('Email verified',
      'Your recovery email is confirmed. Return to the Ikot La Salle app.'));
  } catch (error) {
    console.error('Recovery email verification failed:', error.message);
    res.writeHead(400).end(actionPage('Could not verify email', escapeHtml(error.message)));
  }
  return true;
}

async function handlePasswordResetPage(req, res, {admin, db, url}) {
  const invalidPage = (message) => {
    res.writeHead(400).end(actionPage('Could not reset password', escapeHtml(message)));
    return true;
  };
  if (req.method === 'GET') {
    const oobCode = url.searchParams.get('oobCode') || '';
    if (!/^[A-Za-z0-9._~-]{20,512}$/.test(oobCode)) {
      return invalidPage('This password-reset link is invalid. Request a new one in the app.');
    }
    const resetRef = db.collection('recoveryPasswordResetTokens').doc(hashToken(oobCode));
    const reset = (await resetRef.get()).data();
    const expiry = reset?.expiresAt?.toMillis?.();
    if (!reset || !expiry || expiry <= Date.now()) {
      return invalidPage('This password-reset link is invalid or expired. Request a new one in the app.');
    }
    const eyeToggle = (target) => `<span class="password-field"><input id="${target}" type="password" name="${target}" minlength="8" maxlength="128" autocomplete="new-password" required><button class="toggle-password" type="button" data-password-toggle="${target}" aria-label="Show password" aria-pressed="false" title="Show password"><svg class="eye-open" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg><svg class="eye-closed" viewBox="0 0 24 24" aria-hidden="true"><path d="m3 3 18 18M10.6 5.2A10.7 10.7 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.1 3.9M6.2 6.2C3.5 8.1 2 12 2 12s3.6 7 10 7c1.4 0 2.7-.3 3.8-.8"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/></svg></button></span>`;
    const form = `<p><strong>${escapeHtml(reset.email)}</strong></p><form method="post" action="/reset-password"><input type="hidden" name="oobCode" value="${escapeHtml(oobCode)}"><label>New password${eyeToggle('newPassword')}</label><label>Confirm new password${eyeToggle('confirmPassword')}</label><button type="submit">Save new password</button></form><script>document.querySelectorAll('[data-password-toggle]').forEach(button=>{button.addEventListener('click',()=>{const input=document.getElementById(button.dataset.passwordToggle);const visible=input.type==='password';input.type=visible?'text':'password';button.setAttribute('aria-pressed',String(visible));button.setAttribute('aria-label',visible?'Hide password':'Show password');button.title=visible?'Hide password':'Show password';});});</script>`;
    res.writeHead(200).end(actionPage('Reset your password', 'Password recovery email:', form));
    return true;
  }
  if (req.method !== 'POST') {
    res.writeHead(405).end(actionPage('Method not allowed', 'Return to the app and request a new reset link.'));
    return true;
  }
  try {
    const raw = await readBody(req, 4096);
    const form = new URLSearchParams(raw);
    const oobCode = form.get('oobCode') || '';
    const newPassword = form.get('newPassword') || '';
    const confirmPassword = form.get('confirmPassword') || '';
    if (!/^[A-Za-z0-9._~-]{20,512}$/.test(oobCode)) {
      throw new Error('This password-reset link is invalid. Request a new one in the app.');
    }
    if (newPassword.length < 8 || newPassword.length > 128) {
      throw new Error('Use a password between 8 and 128 characters.');
    }
    if (!/[A-Z]/.test(newPassword)) throw new Error('Add at least one uppercase letter.');
    if (!/[^A-Za-z0-9]/.test(newPassword)) throw new Error('Add at least one special character.');
    if (newPassword !== confirmPassword) throw new Error('The passwords do not match.');
    const resetRef = db.collection('recoveryPasswordResetTokens').doc(hashToken(oobCode));
    const reset = (await resetRef.get()).data();
    const expiry = reset?.expiresAt?.toMillis?.();
    if (!reset || !expiry || expiry <= Date.now()) {
      throw new Error('This password-reset link is invalid or expired. Request a new one in the app.');
    }
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=${encodeURIComponent(reset.apiKey)}`,
      {method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({oobCode, newPassword}), signal: AbortSignal.timeout(15000)},
    );
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      const code = String(result.error?.message || '');
      if (code.includes('WEAK_PASSWORD')) throw new Error('Choose a stronger password and try again.');
      if (code.includes('EXPIRED_OOB_CODE') || code.includes('INVALID_OOB_CODE')) {
        throw new Error('This password-reset link is invalid or expired. Request a new one in the app.');
      }
      throw new Error('Firebase could not reset the password. Request a new link and try again.');
    }
    await resetRef.delete();
    res.writeHead(200).end(actionPage('Password updated',
      'Your password has been changed. Return to Ikot La Salle and sign in with your passenger ID.'));
  } catch (error) {
    console.error('Passenger password reset failed:', error.message);
    res.writeHead(400).end(actionPage('Could not reset password', escapeHtml(error.message)));
  }
  return true;
}

async function readBody(req, maxBytes) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (body.length > maxBytes) throw new Error('Request too large.');
  }
  return body;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

function actionPage(title, message, action = '') {
  return `<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title><style>body{font:16px system-ui,sans-serif;background:#f4f7f5;color:#1c2922;margin:0;padding:24px}.card{max-width:520px;margin:10vh auto;background:white;padding:28px;border-radius:16px;box-shadow:0 4px 24px #183a2518}form{display:grid;gap:16px}label{display:grid;gap:7px;color:#59645e}.password-field{position:relative;display:block}input{box-sizing:border-box;width:100%;padding:12px;border:1px solid #c8d0cb;border-radius:8px;font:inherit;color:#1c2922}.password-field input{padding-right:52px}button{background:#176b45;color:#fff;border:0;border-radius:10px;padding:14px 20px;font-weight:700;font-size:16px;cursor:pointer}.toggle-password{position:absolute;right:5px;top:50%;transform:translateY(-50%);display:grid;place-items:center;width:40px;height:40px;padding:8px;background:transparent;color:#526158}.toggle-password:hover{background:#edf4ef}.toggle-password svg{width:22px;height:22px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}.eye-closed{display:none}.toggle-password[aria-pressed="true"] .eye-open{display:none}.toggle-password[aria-pressed="true"] .eye-closed{display:block}</style><main class="card"><h1>${escapeHtml(title)}</h1><p>${message}</p>${action}</main></html>`;
}
