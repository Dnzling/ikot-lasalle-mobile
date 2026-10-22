// Authenticated passenger operations. The caller's Firebase ID token is the
// identity; no passenger ID or fare supplied by the phone is trusted.
import {
  handleRecoveryEmailAction,
  requestRecoveryPasswordReset,
  startRecoveryEmailVerification,
} from './recovery.js';

export async function handleAppApi(req, res, {admin, db}) {
  if (await handleRecoveryEmailAction(req, res, {admin, db})) return true;
  if (!req.url?.startsWith('/api/')) return false;
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Cache-Control', 'no-store');
  if (req.method === 'OPTIONS') {
    res.writeHead(204).end();
    return true;
  }
  if (req.method !== 'POST') {
    res.writeHead(405).end();
    return true;
  }
  try {
    if (req.url === '/api/recovery/request-reset') {
      const body = await readJson(req);
      const result = await requestRecoveryPasswordReset({
        admin, db, email: body.email, req,
      });
      res.writeHead(200, {'Content-Type': 'application/json'}).end(JSON.stringify(result));
      return true;
    }
    const token = /^Bearer (.+)$/.exec(req.headers.authorization || '')?.[1];
    if (!token) throw new Error('Authentication required.');
    const {uid} = await admin.auth().verifyIdToken(token, true);
    const body = await readJson(req);
    const result = req.url === '/api/board'
      ? await boardRide({admin, db, uid, body})
      : req.url === '/api/arrive'
        ? await arrive({admin, db, uid, body})
        : req.url === '/api/recovery/start-verification'
          ? await startRecoveryEmailVerification({
            admin, db, uid, email: body.email, req,
          })
          : null;
    if (!result) {
      res.writeHead(404).end();
      return true;
    }
    res.writeHead(200, {'Content-Type': 'application/json'}).end(JSON.stringify(result));
  } catch (error) {
    console.error('App API request rejected:', error.message);
    res.writeHead(400, {'Content-Type': 'application/json'})
      .end(JSON.stringify({error: error.message}));
  }
  return true;
}

async function readJson(req) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 4096) throw new Error('Request too large.');
  }
  return JSON.parse(body);
}

function requireId(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new Error('Invalid document ID.');
  }
  return value;
}

function freshGps(vehicle) {
  const at = vehicle?.lastGpsAt?.toMillis?.();
  return at && Date.now() - at >= -5000 && Date.now() - at <= 120000;
}

function distanceMeters(a, b) {
  const radians = (n) => n * Math.PI / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLon = radians(b.longitude - a.longitude);
  const x = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) *
    Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

async function boardRide({admin, db, uid, body}) {
  const bookingId = requireId(body.bookingId);
  const vehicleId = requireId(body.vehicleId);
  const routes = (await db.collection('routes').where('active', '==', true).get())
    .docs.filter((doc) => doc.data().archived !== true)
    .sort((a, b) => (Number(a.data().order) || 0) -
      (Number(b.data().order) || 0) || a.id.localeCompare(b.id));
  const userRef = db.collection('users').doc(uid);
  const tripRef = db.collection('trips').doc(bookingId);
  const vehicleRef = db.collection('vehicles').doc(vehicleId);
  const faresRef = db.collection('settings').doc('fares');
  return db.runTransaction(async (tx) => {
    const [userDoc, tripDoc, vehicleDoc, faresDoc] = await Promise.all([
      tx.get(userRef), tx.get(tripRef), tx.get(vehicleRef), tx.get(faresRef),
    ]);
    const user = userDoc.data();
    const trip = tripDoc.data();
    const vehicle = vehicleDoc.data();
    if (!user || user.active === false || !trip || trip.userId !== uid ||
        trip.status !== 'waiting') throw new Error('Booking is unavailable.');
    if (trip.createdAt?.toMillis?.() &&
        Date.now() - trip.createdAt.toMillis() >= 600000) {
      throw new Error('Booking expired after 10 minutes.');
    }
    if (!vehicle || vehicle.archived === true || !freshGps(vehicle) ||
        !['active', 'idle', 'onroute'].includes(String(vehicle.status || '').toLowerCase()) ||
        vehicle.type !== body.vehicleType) {
      throw new Error('Vehicle is unavailable or its GPS is stale.');
    }
    const direction = vehicle.routeDirection;
    if (!['towardLastStop', 'towardFirstStop'].includes(direction) ||
        direction !== body.confirmedDirection) throw new Error('Vehicle direction changed. Scan again.');
    const pickup = routes.findIndex((route) => route.id === trip.pickupRouteId);
    const dropoff = routes.findIndex((route) => route.id === trip.destinationRouteId);
    if (pickup < 0 || dropoff < 0 || pickup === dropoff) {
      throw new Error('Booked route is no longer active.');
    }
    const count = Number(trip.passengerCount);
    if (!Number.isInteger(count) || count < 1 || count > 6) throw new Error('Invalid passenger count.');
    const onboard = Number(vehicle.onBoardPassengers) || 0;
    const capacity = Number(vehicle.passengerCapacity) || 0;
    if (capacity > 0 && onboard + count > capacity) throw new Error('Vehicle is full.');
    const roundTrip = direction === 'towardLastStop' ? dropoff < pickup : dropoff > pickup;
    const fare = Number(roundTrip ? faresDoc.data()?.roundTripFare : faresDoc.data()?.defaultFare) * count;
    if (!Number.isFinite(fare) || fare <= 0 ||
        Math.abs(fare - Number(body.confirmedFare)) > 0.001) {
      throw new Error('Fare changed. Scan again.');
    }
    const balance = Number(user.balance) || 0;
    if (balance < fare) throw new Error('Insufficient credits.');
    const destinationId = trip.destinationRouteId;
    const expected = {...(vehicle.expectedOutboardByStop || {})};
    expected[destinationId] = (Number(expected[destinationId]) || 0) + count;
    const stamp = admin.firestore.FieldValue.serverTimestamp();
    tx.update(userRef, {balance: balance - fare});
    tx.update(tripRef, {
      status: 'onboard', fare, fareType: roundTrip ? 'roundTrip' : 'default',
      routeDirectionAtBoarding: direction, vehicleId, vehicleName: vehicle.name,
      vehicleType: vehicle.type, driverId: vehicle.driverId || null,
      driverName: vehicle.driverName || null, boardedAt: stamp,
    });
    tx.update(vehicleRef, {
      onBoardPassengers: onboard + count, expectedOutboardByStop: expected,
      tripPassengerCount: admin.firestore.FieldValue.increment(count),
      tripIncome: admin.firestore.FieldValue.increment(fare),
    });
    tx.set(db.collection('transactions').doc(), {
      userId: uid, passengerName: `${user.firstName || ''} ${user.lastName || ''}`.trim(),
      userType: user.userType || 'Passenger', title: `Ride to ${trip.destination || 'destination'}`,
      description: `Ride to ${trip.destination || 'destination'}`, amount: -fare,
      type: 'fare', createdAt: stamp, tripId: bookingId, vehicleId,
      vehicleName: vehicle.name,
    });
    tx.set(db.collection('notifications').doc(), {
      userId: uid, type: 'boarded', title: 'You are onboard',
      message: `PHP ${fare.toFixed(2)} was charged for your ride.`, createdAt: stamp,
    });
    return {ok: true, fare};
  });
}

async function arrive({admin, db, uid, body}) {
  const bookingId = requireId(body.bookingId);
  const tripRef = db.collection('trips').doc(bookingId);
  const before = (await tripRef.get()).data();
  if (!before || before.userId !== uid || !before.vehicleId ||
      !before.destinationRouteId) throw new Error('Booking is unavailable.');
  const vehicleRef = db.collection('vehicles').doc(before.vehicleId);
  const routeRef = db.collection('routes').doc(before.destinationRouteId);
  return db.runTransaction(async (tx) => {
    const [tripDoc, vehicleDoc, routeDoc] = await Promise.all([
      tx.get(tripRef), tx.get(vehicleRef), tx.get(routeRef),
    ]);
    const trip = tripDoc.data();
    const vehicle = vehicleDoc.data();
    const stop = routeDoc.data();
    if (!trip || trip.userId !== uid || trip.status !== 'onboard' ||
        trip.vehicleId !== vehicleRef.id || trip.destinationRouteId !== routeRef.id) {
      throw new Error('The ride is not onboard.');
    }
    if (!vehicle || !stop || !freshGps(vehicle) || !vehicle.location || !stop.location ||
        distanceMeters(vehicle.location, stop.location) >
          (Number(stop.proximityRadius) || 50)) {
      throw new Error('Arrived is available only near your destination stop.');
    }
    const count = Number(trip.passengerCount) || 1;
    const expected = {...(vehicle.expectedOutboardByStop || {})};
    const left = Math.max(0, (Number(expected[routeRef.id]) || 0) - count);
    if (left === 0) delete expected[routeRef.id];
    else expected[routeRef.id] = left;
    tx.update(vehicleRef, {
      onBoardPassengers: Math.max(0, (Number(vehicle.onBoardPassengers) || 0) - count),
      outBoardPassengers: admin.firestore.FieldValue.increment(count),
      expectedOutboardByStop: expected,
    });
    tx.update(tripRef, {status: 'arrived', completedAt: admin.firestore.FieldValue.serverTimestamp()});
    tx.set(db.collection('notifications').doc(), {
      userId: uid, type: 'completed', title: 'You have arrived',
      message: `You arrived at ${trip.destination || 'your destination'}.`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {ok: true};
  });
}
