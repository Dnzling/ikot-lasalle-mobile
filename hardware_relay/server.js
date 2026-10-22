import http from 'node:http';
import crypto from 'node:crypto';
import {readFileSync} from 'node:fs';
import admin from 'firebase-admin';
import {handleAppApi} from './app_api.js';
import {processOverstays} from './overstay.js';

const port = Number(process.env.PORT || 8080);
const privacyPolicyHtml = readFileSync(new URL('./privacy-policy.html', import.meta.url), 'utf8');
const deviceIds = new Set((process.env.VEHICLE_DOCUMENT_IDS ||
    process.env.VEHICLE_DOCUMENT_ID || '').split(',').map((id) => id.trim()).filter(Boolean));
const keyHex = process.env.RELAY_KEY_HEX || '';
if (!/^[a-fA-F0-9]{128}$/.test(keyHex) || deviceIds.size === 0) {
  throw new Error('Set RELAY_KEY_HEX (64 random bytes in hex) and VEHICLE_DOCUMENT_IDS.');
}
const key = Buffer.from(keyHex, 'hex');
const encryptionKey = key.subarray(0, 32);
const macKey = key.subarray(32);
const seenNonces = new Map();
const maxAgeMs = 5 * 60 * 1000;
const firebaseCredential = admin.credential.applicationDefault();
admin.initializeApp({credential: firebaseCredential});
const db = admin.firestore();

try {
  await firebaseCredential.getAccessToken();
} catch (error) {
  console.error('Firebase credential rejected before relay startup:', error.message);
  process.exit(1);
}

function mac(direction, nonce, ciphertext) {
  return crypto.createHmac('sha256', macKey)
    .update(direction).update(nonce).update(ciphertext).digest();
}

function decrypt(envelope, direction) {
  if (envelope?.v !== 1 ||
      !/^[a-f0-9]{24}$/i.test(envelope.nonce || '') ||
      !/^(?:[a-f0-9]{2})*$/i.test(envelope.data || '') ||
      !/^[a-f0-9]{64}$/i.test(envelope.mac || '')) {
    throw new Error('Invalid envelope.');
  }
  const nonce = Buffer.from(envelope.nonce, 'hex');
  const ciphertext = Buffer.from(envelope.data, 'hex');
  const actual = Buffer.from(envelope.mac, 'hex');
  if (!crypto.timingSafeEqual(actual, mac(direction, nonce, ciphertext))) {
    throw new Error('Invalid message authentication.');
  }
  const decipher = crypto.createDecipheriv('aes-256-ctr', encryptionKey,
    Buffer.concat([nonce, Buffer.alloc(4)]));
  return JSON.parse(Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8'));
}

function encrypt(value, direction) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-ctr', encryptionKey,
    Buffer.concat([nonce, Buffer.alloc(4)]));
  const data = Buffer.concat([cipher.update(JSON.stringify(value)), cipher.final()]);
  return JSON.stringify({
    v: 1, nonce: nonce.toString('hex'), data: data.toString('hex'),
    mac: mac(direction, nonce, data).toString('hex'),
  });
}

async function execute(message) {
  if (!deviceIds.has(message.deviceId)) throw new Error('Unknown device.');
  if (!Number.isFinite(message.ts) || Math.abs(Date.now() - message.ts * 1000) > maxAgeMs) {
    throw new Error('Device clock outside allowed window.');
  }
  if (message.op === 'gps') {
    const {latitude, longitude, speedKmh, status, locationLabel, type,
      routeDirection} = message;
    if (![latitude, longitude, speedKmh].every(Number.isFinite) ||
        latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 ||
        speedKmh < 0 || speedKmh > 250 ||
        !['active', 'break', 'fueling gas'].includes(status) ||
        (type !== undefined && !['Jeep', 'E-Jeep'].includes(type)) ||
        (routeDirection !== undefined &&
          !['towardLastStop', 'towardFirstStop'].includes(routeDirection)) ||
        (locationLabel !== undefined &&
          (typeof locationLabel !== 'string' || locationLabel.length > 40 ||
            !/^LOC: [^\r\n]+$/.test(locationLabel)))) {
      throw new Error('Invalid GPS payload.');
    }
    const ref = db.collection('vehicles').doc(message.deviceId);
    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      if (!snapshot.exists) throw new Error('Configured vehicle does not exist.');
      const vehicleType = snapshot.data().type || type;
      const update = {
        location: new admin.firestore.GeoPoint(latitude, longitude),
        latitude, longitude, speedKmh,
        status: vehicleType === 'E-Jeep' && status === 'fueling gas'
          ? 'active' : status,
        lastGpsAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (locationLabel !== undefined) update.locationLabel = locationLabel;
      if (routeDirection !== undefined) update.routeDirection = routeDirection;
      if (!snapshot.data().type && type) update.type = type;
      tx.update(ref, update);
    });
    // Acknowledge the GPS write as soon as Firestore commits it. Overstay
    // checks are ancillary and can take longer than the SIM808 HTTP window;
    // do not let their latency turn a saved GPS point into a lost ACK.
    void processOverstays({admin, db, vehicleId: message.deviceId,
      latitude, longitude, routeDirection})
      .catch((error) => console.error('Overstay check failed:', error.message));
    return {ok: true};
  }
  if (message.op === 'routes') {
    const snapshot = await db.collection('routes').limit(100).get();
    const routes = snapshot.docs.filter((doc) => {
      const data = doc.data();
      return data.active === true && data.archived !== true && data.location;
    }).sort((a, b) => {
      const aOrder = Number(a.data().order) || 0;
      const bOrder = Number(b.data().order) || 0;
      return aOrder - bOrder || a.id.localeCompare(b.id);
    }).slice(0, 30).map((doc) => {
      const data = doc.data();
      return {id: doc.id, name: String(data.name || doc.id), latitude: data.location.latitude,
        longitude: data.location.longitude,
        radius: Number(data.proximityRadius) || 40};
    });
    return {ok: true, routes};
  }
  if (message.op === 'fueling') {
    const snapshot = await db.collection('settings').doc('fuelingLocations').get();
    if (!snapshot.exists) throw new Error('Fueling locations are not configured.');
    const data = snapshot.data();
    const entrance = data.entrance;
    const exit = data.exit;
    const entranceRadiusMeters = Number(data.entranceRadiusMeters);
    const exitRadiusMeters = Number(data.exitRadiusMeters);
    const validPoint = (point) => point &&
      Number.isFinite(point.latitude) && Number.isFinite(point.longitude) &&
      point.latitude >= -90 && point.latitude <= 90 &&
      point.longitude >= -180 && point.longitude <= 180 &&
      (point.latitude !== 0 || point.longitude !== 0);
    if (!validPoint(entrance) || !validPoint(exit) ||
        !Number.isFinite(entranceRadiusMeters) || entranceRadiusMeters <= 0 ||
        !Number.isFinite(exitRadiusMeters) || exitRadiusMeters <= 0) {
      throw new Error('Fueling locations have invalid coordinates or radii.');
    }
    return {ok: true,
      entrance: {latitude: entrance.latitude, longitude: entrance.longitude,
        radius: entranceRadiusMeters},
      exit: {latitude: exit.latitude, longitude: exit.longitude,
        radius: exitRadiusMeters}};
  }
  if (message.op === 'vehicle') {
    const snapshot = await db.collection('vehicles').doc(message.deviceId).get();
    if (!snapshot.exists) throw new Error('Configured vehicle does not exist.');
    const data = snapshot.data();
    return {ok: true, type: String(data.type || ''),
      status: String(data.status || ''),
      locationLabel: String(data.locationLabel || ''),
      onboard: Number(data.onBoardPassengers) || 0,
      expected: data.expectedOutboardByStop || {}};
  }
  throw new Error('Unknown operation.');
}

http.createServer(async (req, res) => {
  const pathname = new URL(req.url || '/', 'http://localhost').pathname;
  if (req.method === 'GET' && pathname === '/privacy-policy') {
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
      'X-Content-Type-Options': 'nosniff',
    });
    res.end(privacyPolicyHtml);
    return;
  }
  if (req.method === 'GET' && pathname === '/health') {
    res.writeHead(200, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'});
    res.end(JSON.stringify({ok: true}));
    return;
  }
  if (await handleAppApi(req, res, {admin, db})) return;
  if (req.method !== 'POST' || req.url !== '/relay') {
    res.writeHead(404).end();
    return;
  }
  let body = '';
  req.on('data', (chunk) => {
    body += chunk;
    if (body.length > 16384) req.destroy();
  });
  req.on('end', async () => {
    try {
      const envelope = JSON.parse(body);
      const message = decrypt(envelope, 'req');
      const now = Date.now();
      for (const [nonce, expires] of seenNonces) {
        if (expires < now) seenNonces.delete(nonce);
      }
      if (seenNonces.has(envelope.nonce)) throw new Error('Repeated request.');
      seenNonces.set(envelope.nonce, now + maxAgeMs);
      const result = await execute(message);
      res.writeHead(200, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'});
      res.end(encrypt({...result, requestNonce: envelope.nonce}, 'res'));
    } catch (error) {
      console.error('Relay request rejected:', error.message);
      res.writeHead(400, {'Content-Type': 'text/plain', 'Cache-Control': 'no-store'});
      res.end('Request rejected');
    }
  });
}).listen(port, '0.0.0.0', () => console.log(`Hardware relay listening on ${port}`));
