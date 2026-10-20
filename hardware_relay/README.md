# SIM808 hardware relay

This relay accepts encrypted requests from `hardwarecode.cpp` (E-Jeep) and `hardwarecode1.cpp` (Jeep) over SIM808 GPRS and makes Firestore requests using Firebase Admin credentials. The devices and relay must share the configured 64-byte key. The SIM phone numbers are not used as APNs or authentication secrets.

1. Generate a key: `node -e "console.log(require('node:crypto').randomBytes(64).toString('hex'))"`.
2. Put that hex value in `RELAY_KEY_HEX` on the server and in both firmware files. Keep it private.
3. Set `VEHICLE_DOCUMENT_IDS` to a comma-separated list of existing Firestore vehicle document IDs, for example `fVzHxxqNmYGYKd5gxmqi,CuoxcUom2JLXRq4qu33L`. For one vehicle, the older `VEHICLE_DOCUMENT_ID` variable still works. Set `GOOGLE_APPLICATION_CREDENTIALS` to a service-account JSON from the new Firebase project, `ikot-lasalle-2bed1`, on the relay host. Keep that JSON on the host and out of the Flutter apps and Git.
4. Set `RELAY_HOST` and `RELAY_PORT` in both firmware files to the public DNS name/IP and TCP port of this server. Both SIM808 units use Smart APN `internet`.
5. Run `npm install` and `npm start` on an always-on host with a reachable public TCP port. Restrict the service account to the required Firestore permissions and protect the host with normal firewall controls.

The GPRS leg uses AES-256-CTR encryption and HMAC-SHA256 authentication. Messages include a random nonce and a five-minute clock window to reject replay. The server uses its own timestamp for GPS updates. The server never returns credentials to the device. The relay host needs outbound access to Google services over HTTPS.

This deployment requires the SIM808 to register on a working 2G/GPRS network. The firmware prints registration and bearer failures to Serial. A phone number alone does not activate data service.

## Deploy on Render Free

The repository root contains `render.yaml` for the relay Web Service. It uses
Render's assigned `PORT`, starts `pnpm start`, and checks `/health`.

1. Push the repository to GitHub without committing any service-account JSON,
   `.env` file, or relay key. `hardware_relay/.gitignore` excludes local secret
   files.
2. In Render, create a **Blueprint** from the GitHub repository. Render reads
   the root `render.yaml` and prompts for `VEHICLE_DOCUMENT_IDS` and
   `RELAY_KEY_HEX`. Use the Firestore vehicle document IDs and the same 128
   character key configured on the hardware.
3. In the new service, open **Environment → Secret Files → Add Secret File**.
   Name the file `firebase-service-account.json` and paste the service-account
   JSON for `ikot-lasalle-2bed1`. The blueprint points
   `GOOGLE_APPLICATION_CREDENTIALS` to `/etc/secrets/firebase-service-account.json`.
4. Deploy/redeploy. Check the assigned Render URL at `/health`; it should
   return `{"ok":true}`. The URL will be an HTTPS `onrender.com` address.
5. Build the passenger app with that URL:

   ```powershell
   flutter build apk --release --dart-define=TRUSTED_API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
   ```

Render Free can sleep after 15 minutes without inbound traffic, and waking may
take about a minute. Use it for a thesis demo, with retry handling; it does not
guarantee uninterrupted Play Store service. The current SIM808 firmware still
sends HTTP on port 80, so don't point it at the Render HTTPS hostname until its
HTTPS/TLS support has been implemented and verified on the actual modem.

## Trusted passenger operations

The same server now accepts Firebase-authenticated HTTPS requests at
`/api/board` and `/api/arrive`. It verifies the passenger's Firebase ID token,
recalculates the fare from Firestore, and commits balance, trip, vehicle, and
ledger changes in one transaction. Publish it behind a stable HTTPS address.
The passenger app must be built with
`--dart-define=TRUSTED_API_BASE_URL=https://YOUR_HOST`.
Do not put `RELAY_KEY_HEX` or the service-account JSON in a Flutter app.

Before publishing the restrictive Firestore rules, seed ID login mappings
with `node seed_login_aliases.js` on the relay host using the replacement
service-account credential. See `../docs/firestore-security-rollout.md` for
the required order.

## First admin account

Enable Email/Password in Firebase Console > Authentication, publish
`../passenger_app/firestore.rules`, and open the admin app. Choose **Create
first admin account** on the sign-in screen and set the ID and password. The
form is available only until the first admin is created; Firestore also
enforces this as a one-time claim. Later administrators must be added by an
existing administrator through a trusted server process.
