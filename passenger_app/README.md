# Ikot La Salle Passenger App

Passenger accounts use Firebase Authentication, with profile and app data stored
in the shared Firestore project `ikot-lasalle-ccfab`. Top-up receipt previews
are stored as bounded Firestore bytes with their requests.

## Firebase data

- `users/{uid}`: passenger profile and credit balance
- `users/{uid}/sessions/{sessionId}`: login session metadata
- `routes/{routeId}`: active destinations and per-passenger fare
- `vehicles/{vehicleId}`: vehicle status and live `location` (`GeoPoint`)
- `trips/{tripId}`: bookings and ride status
- `transactions/{transactionId}`: wallet changes
- `topUpRequests/{requestId}`: payment screenshot and approval status
- `notifications/{notificationId}`: passenger alerts
- `settings/payment`: `gcashNumber` shown on the top-up page

Passengers create accounts with an ID number and password. Firebase
Authentication uses a generated internal email alias for those accounts, so no
email field is required in the passenger form. Accounts created with the old
school-email sign-in can also be resolved by matching the entered ID number to
the Firestore profile's `email` field.

Each passenger profile's `session` field identifies the latest login, and the
subcollection stores each login's active state and timestamps. Firebase Auth
tokens remain managed by Firebase Authentication and are not copied into
Firestore.

If a second passenger login is attempted while a session is active, the app
marks the old session ended with `endReason: newDevice`, signs out the new
attempt, and shows "New Device Detected, Logging Out" on both running clients.
The locally saved session ID lets a hot restart on the same installation resume
its existing session. This is an app-level concurrent-login safeguard, **not**
server-side Firebase token revocation; offline or modified clients cannot be
reliably logged out without a trusted backend and matching security rules.

Phone-number OTP password reset is not enabled yet. The SIM808 GPS firmware
does not provide a trusted OTP issuer/verifier or Firebase Admin password
reset. Do not store OTP codes or reset passwords in client-side Firestore
documents. A secure implementation needs an authenticated backend, expiry,
attempt/rate limits, and server-side session revocation before the SIM808 is
used as an SMS delivery channel.

Configure Firestore and Storage security rules to allow each signed-in passenger
to read their own profile and session history, update their session metadata,
and create their own trips, alerts, and top-up requests. The current ride flow
updates the passenger balance in a Firestore transaction when boarding;
production rules should validate that debit against the linked trip or move it
to a trusted server function. The top-up page reads its recipient number from
`settings/payment.gcashNumber`.
Legacy ID-to-email lookup happens before authentication, so do not make the
`users` collection publicly readable in production; move that lookup to a
trusted server endpoint.

## Mapbox and GPS

The public Mapbox access token is configured in
`lib/config/mapbox_config.dart`. Restrict its allowed URLs or app identifiers
and scopes in Mapbox before distributing the app. Run with:

```shell
flutter run
```

The app requests location only while it is in use.

## Top-up receipt upload on web

The passenger app stores a receipt of at most 800 KB directly in its
`topUpRequests` Firestore document. This avoids the Firebase Storage browser
CORS upload path that previously left top-up submissions waiting. The admin
Top-up page reads the same document, displays the receipt, and can approve or
reject it. Existing requests with Storage download URLs remain viewable.
Firestore rules must permit each signed-in passenger to create and read their
own `topUpRequests` documents, and admins to read/update requests. The
notification write is best-effort and cannot prevent a request from reaching
the admin queue.
