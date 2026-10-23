# Set up the hardware relay on another PC with ngrok

This guide runs the Ikot La Salle hardware relay on a Windows PC and exposes it to the SIM808 through ngrok. The relay listens on that PC's localhost port `8080`; ngrok provides the public address. Keep both programs running while the hardware is sending GPS updates.

## 1. Prepare the other PC

Install Node.js, pnpm, and ngrok. Sign in to ngrok on that PC and configure its authtoken locally using the command shown in your ngrok account. Do not paste the token into this file, the project, or chat.

Copy the project to the PC, or clone the repository. Open PowerShell in the project's `hardware_relay` folder and install dependencies:

```powershell
pnpm install
```

## 2. Add the private relay configuration

Copy `.env.example` to `.env` in the `hardware_relay` folder. For example, from that folder:

```powershell
Copy-Item .env.example .env
```

Edit `.env` and set these values:

```env
PORT=8080
GOOGLE_APPLICATION_CREDENTIALS=./firebase-service-account.json
VEHICLE_DOCUMENT_IDS=jeep-firestore-document-id,ejeep-firestore-document-id
RELAY_KEY_HEX=your-existing-128-character-hex-key
```

- Put the Firebase Admin service-account JSON for the `ikot-lasalle-2bed1` project in this folder and name it `firebase-service-account.json`.
- Use the actual Firestore **document IDs** for the Jeep and E-Jeep in `VEHICLE_DOCUMENT_IDS`.
- Use the exact same `RELAY_KEY_HEX` already configured in both hardware sketches. Do not generate a replacement unless you also update and reflash both devices.
- Keep `.env` and the service-account JSON private. They are excluded from Git; never send them in chat or commit them.
- If the passenger recovery-email endpoints are needed on this local relay, also set `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME`, and `APP_PUBLIC_URL` as described in `hardware_relay/README.md`.

## 3. Start the relay

In PowerShell, from the `hardware_relay` folder, run:

```powershell
pnpm start
```

Leave this window running. The relay should report that it is listening on port `8080`.

## 4. Start ngrok on the same PC

Open a second PowerShell window on that PC and run:

```powershell
ngrok http 8080
```

Leave ngrok running too. Copy the public forwarding hostname from its output, for example `example.ngrok-free.dev`. The free ngrok hostname can change when a new tunnel session starts.

## 5. Verify the public relay

From PowerShell, substitute the hostname ngrok showed:

```powershell
curl.exe -i http://YOUR-NGROK-HOST/health
```

The response should have HTTP status `200` and body `{"ok":true}`. If not, check that `pnpm start` is still running and that ngrok forwards to port `8080` on this same PC.

## 6. Point both hardware sketches at this tunnel

In both `hardwarecode.cpp` and `hardwarecode1.cpp`, set the relay host and port to the current ngrok hostname and port `80`:

```cpp
const char* RELAY_HOST = "YOUR-NGROK-HOST";
const uint16_t RELAY_PORT = 80;
```

Use only the hostname in `RELAY_HOST`: omit `http://`, `https://`, and any path. The SIM808 firmware sends plain HTTP, so it must connect to ngrok's **HTTP** forwarding address on port `80`. ngrok then forwards the request to the local relay. Keep both the relay and ngrok running during the demo.

Upload the updated sketch to each ESP8266. Both devices can use the same relay endpoint and hostname; the relay identifies each vehicle using the configured document IDs and the encrypted request.

## If the tunnel address changes

Run `ngrok http 8080` again and update `RELAY_HOST` in both sketches to the new hostname, then upload both sketches again. A stable ngrok domain avoids changing the firmware hostname each time; it still requires the relay and ngrok processes to be running on the PC.

## Troubleshooting

- **Port 8080 already in use:** stop the other relay process using port `8080`, then run `pnpm start` again.
- **`RELAY_KEY_HEX` or vehicle IDs error:** confirm `.env` is in `hardware_relay`, has no placeholder values, and the key is the same as in the firmware.
- **Firebase default credentials error:** verify the service-account JSON path and filename in `.env` and that the file exists in `hardware_relay`.
- **`/health` works locally but not through ngrok:** make sure ngrok is running `ngrok http 8080` on the same PC as the relay and use the exact forwarding hostname it prints.
- **SIM808 reports HTTP 601 or 603:** verify the firmware hostname and port, ensure the ngrok HTTP endpoint is running, and check SIM808 GPRS registration/data connectivity. The SIM808 needs an active GPRS data service.
