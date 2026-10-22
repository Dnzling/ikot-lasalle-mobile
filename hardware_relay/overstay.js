const DEFAULT_PENALTY_CREDITS = 10;

function distanceMeters(a, b) {
  const rad = (n) => n * Math.PI / 180;
  const lat = rad(b.latitude - a.latitude);
  const lon = rad(b.longitude - a.longitude);
  const x = Math.sin(lat / 2) ** 2 +
    Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(lon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

export async function processOverstays({admin, db, vehicleId, latitude, longitude, routeDirection}) {
  const trips = (await db.collection('trips').where('status', '==', 'onboard').get())
    .docs.filter((doc) => doc.data().vehicleId === vehicleId);
  if (!trips.length) return;
  const penaltySnapshot = await db.collection('settings').doc('credits').get();
  const configuredPenalty = Number(penaltySnapshot.data()?.overstayingPenaltyCredits);
  const penalty = Number.isInteger(configuredPenalty) && configuredPenalty >= 1 && configuredPenalty <= 10000
    ? configuredPenalty : DEFAULT_PENALTY_CREDITS;
  const routes = (await db.collection('routes').where('active', '==', true).get())
    .docs.filter((doc) => doc.data().archived !== true && doc.data().location)
    .sort((a, b) => (Number(a.data().order) || 0) - (Number(b.data().order) || 0));
  const point = {latitude, longitude};
  for (const tripDoc of trips) {
    const trip = tripDoc.data();
    if (trip.overstayChargedAt) continue;
    const index = routes.findIndex((route) => route.id === trip.destinationRouteId);
    if (index < 0) continue;
    const route = routes[index].data();
    const radius = Number(route.proximityRadius) || 50;
    const distance = distanceMeters(point, route.location);
    if (distance <= radius) {
      if (!trip.destinationReachedAt) {
        await tripDoc.ref.update({destinationReachedAt: admin.firestore.FieldValue.serverTimestamp()});
      }
      continue;
    }
    if (!trip.destinationReachedAt || distance <= radius + 15 ||
        Date.now() - trip.destinationReachedAt.toMillis() < 10000) continue;
    const direction = routeDirection || trip.routeDirectionAtBoarding;
    const nextIndex = direction === 'towardFirstStop' ? index - 1 : index + 1;
    const nextRoute = routes[nextIndex]?.data().name || 'the next stop';
    const userRef = db.collection('users').doc(trip.userId);
    await db.runTransaction(async (tx) => {
      const [freshTripDoc, userDoc] = await Promise.all([
        tx.get(tripDoc.ref), tx.get(userRef),
      ]);
      const freshTrip = freshTripDoc.data();
      const user = userDoc.data();
      if (!user || freshTrip?.status !== 'onboard' || freshTrip.overstayChargedAt ||
          !freshTrip.destinationReachedAt ||
          Date.now() - freshTrip.destinationReachedAt.toMillis() < 10000) return;
      const stamp = admin.firestore.FieldValue.serverTimestamp();
      tx.update(userRef, {balance: (Number(user.balance) || 0) - penalty});
      tx.update(tripDoc.ref, {overstayChargedAt: stamp, overstayPenalty: penalty});
      tx.set(db.collection('transactions').doc(`overstay_${tripDoc.id}`), {
        userId: trip.userId, tripId: tripDoc.id, vehicleId,
        passengerName: `${user.firstName || ''} ${user.lastName || ''}`.trim(),
        type: 'violation', title: 'Overstaying penalty',
        description: `Stayed onboard after ${route.name || 'destination'}`,
        amount: -penalty, createdAt: stamp,
      });
      tx.set(db.collection('notifications').doc(), {
        userId: trip.userId, type: 'violation',
        title: `Overstaying: ${penalty} credits deducted`,
        message: `You are overstaying. ${penalty} credits were deducted. Please drop off at ${nextRoute}.`,
        createdAt: stamp,
      });
    });
  }
}
