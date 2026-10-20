# Firestore security rollout

These changes use the hardware relay as the trusted fare endpoint for the new
Firebase project, `ikot-lasalle-2bed1`. **Do not publish the new rules until
the replacement app and relay are deployed and the new project has its admin
and passenger accounts.** The current project rules stay unchanged until you
explicitly publish different rules in the selected project.

1. Configure `GOOGLE_APPLICATION_CREDENTIALS` on the relay host to point to a
   service-account JSON for `ikot-lasalle-2bed1`. Never copy this file into
   either Flutter app or commit it to Git.
2. After creating the admin and passenger records in the new project, run
   `node seed_login_aliases.js` from `hardware_relay` on the relay host. This
   creates ID-to-email mappings in `loginAliases`; it does not copy passwords.
3. Deploy the updated `hardware_relay` to its stable public HTTPS host. Keep
   the existing `/relay` endpoint for SIM808 devices. The new passenger API
   endpoints are `/api/board` and `/api/arrive` on the same host. A GET to
   `https://YOUR_HOST/health` should return `{"ok":true}`.
4. Build and distribute the updated passenger app with
   `--dart-define=TRUSTED_API_BASE_URL=https://YOUR_HOST`. The URL must be
   HTTPS and point to the host running the updated relay. Distribute the
   updated admin app with ID login using `loginAliases`.
5. In Firebase Console > Firestore Database > Rules, paste the contents of
   `passenger_app/firestore.rules`, review the project selection, and click
   Publish. Alternatively, from `passenger_app`, use
   `firebase deploy --only firestore:rules --project ikot-lasalle-2bed1`.
   The project file `passenger_app/firebase.json` now points to these rules.
6. Publish the updated `passenger_app/storage.rules` through Firebase Storage
   Rules or use `firebase deploy --only storage --project ikot-lasalle-2bed1`.
   This closes cross-passenger access to older receipt images in Storage.

The rules deny direct passenger writes to balances, transactions, and vehicle
occupancy. The relay uses the Admin SDK, which is governed by service-account
IAM rather than Firestore client rules. Admin top-up approval remains an
authenticated admin transaction. Phone GPS remains a display fallback only;
the automatic 15-credit arrival penalty is disabled because phone proximity
is not reliable proof for a charge.

If the trusted API URL is absent, boarding and arrival fail closed with a
configuration error. Older passenger builds using direct Firestore fare writes
will fail after the new rules are published; retire them before that step.
