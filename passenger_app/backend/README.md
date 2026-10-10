# Ikot spreadsheet backend

1. Open the Google Sheet that will be used as the database.
2. Select **Extensions > Apps Script** and replace `Code.gs` with this folder's `Code.gs`.
3. Run `setup` once, then run `authorizeServices` once, and approve the requested spreadsheet, Drive, and email access.
4. Select **Deploy > Manage deployments**, edit the web app, choose **New version**, execute as yourself, and allow access to anyone using the app.
5. Copy the `/exec` URL into `lib/config/api_config.dart` if it differs from the current URL.

The backend creates `users`, `sessions`, `bookings`, `transactions`, and `buses` worksheet tabs. Passwords are salted and hashed; plain-text passwords are never written to the workbook.

To publish a bus position, add or update a row in `buses` with a unique ID, label, latitude, longitude, `active` status, and update timestamp. The app refreshes active bus positions every 15 seconds. A future driver/GPS integration can update these same rows without changing the passenger app.

## Top-up approval

After running `setup`, open the `settings` tab and enter the receiving GCash number beside `GCASH_NUMBER`. Optionally enter an administrator address beside `ADMIN_EMAIL` to receive request emails.

Passengers submit an amount and required payment screenshot. The backend stores the image in the `Ikot Top-up Screenshots` Drive folder and creates a `pending` row in `topUpRequests`. An administrator reviews the attachment and changes only the row's `status` cell to `approved` or `rejected`. Changing it to `approved` credits the passenger exactly once and creates a ledger transaction. The `adminNote` column can contain the rejection or approval note shown to the passenger.
