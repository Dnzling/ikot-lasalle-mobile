# Local admin-office password reset tool

This tool is separate from the web admin app. It uses the Firebase Admin SDK on a trusted admin-office computer only. Do not put a service-account key in Flutter, a website, this repository, or a shared drive.

1. In Firebase Console, open **Project settings → Service accounts → Generate new private key**. Save the JSON file outside the repository on the admin-office computer; restrict its filesystem permissions.
2. Install Node.js, then run `npm.cmd install` in this folder (PowerShell may block `npm.ps1`).
3. In PowerShell, set the environment variable for that terminal session:

   `$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\private\ikot-service-account.json'`

4. One-time setup: run `npm.cmd run grant-admin -- admin@example.com` for each trusted admin account, then sign out and back in in the admin app. Do **not** rely on the editable `userType` Firestore field as proof of admin status.
5. Merge `firestore.rules.snippet` into the existing Firestore rules and deploy the merged rules. This is required for the passenger login screen to create requests and for verified admins to view them.
6. In the admin app, open **Password resets** and copy the pending Request ID.
7. Verify the passenger in person, then run `npm.cmd run reset -- REQUEST_ID` in this folder. Confirm by typing `RESET <passenger ID>` when prompted.
8. Give the displayed temporary password directly to the passenger. They must change it at next login.

The passenger app needs a Firestore rule permitting *create only* on `passwordResetRequests` from the login screen. Only authenticated admins with an Admin SDK-issued custom claim should read or update requests. The provided snippet is not deployed automatically; merge it with the project's existing rules rather than replacing the whole ruleset. Public request creation can be abused, so use App Check and monitor/rate-limit submissions before production. The app cannot enforce a trustworthy three-attempt security-question limit without a backend.

The tool marks a request `processing` before changing the Auth password. If it fails after the Auth change, it prints the temporary password and leaves the request `processing` for manual reconciliation. Never rerun a processing request without checking the Auth/account state.
