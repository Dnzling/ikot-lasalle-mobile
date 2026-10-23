const CACHE_MS = 30_000;
let routeEndpoints = null;
let cacheExpiresAt = 0;

function distanceMeters(a, b) {
  const radians = (value) => value * Math.PI / 180;
  const lat = radians(b.latitude - a.latitude);
  const lon = radians(b.longitude - a.longitude);
  const x = Math.sin(lat / 2) ** 2 +
    Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) *
    Math.sin(lon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

async function getRouteEndpoints(db) {
  if (Date.now() < cacheExpiresAt) return routeEndpoints;
  try {
    const snapshot = await db.collection('routes').where('active', '==', true).get();
    const routes = snapshot.docs
      .filter((doc) => doc.data().archived !== true && doc.data().location)
      .sort((a, b) => (Number(a.data().order) || 0) -
        (Number(b.data().order) || 0) || a.id.localeCompare(b.id));
    routeEndpoints = routes.length >= 2
      ? [routes[0].data(), routes[routes.length - 1].data()]
      : null;
  } catch (error) {
    console.error('Could not load route endpoints for direction update:', error.message);
    routeEndpoints = null;
  }
  cacheExpiresAt = Date.now() + CACHE_MS;
  return routeEndpoints;
}

export async function routeDirectionAtEndpoint(db, latitude, longitude) {
  const endpoints = await getRouteEndpoints(db);
  if (!endpoints) return null;
  const point = {latitude, longitude};
  let nearest = null;
  for (let index = 0; index < endpoints.length; index++) {
    const endpoint = endpoints[index];
    const location = endpoint.location;
    const distance = distanceMeters(point, location);
    const radius = Number(endpoint.proximityRadius) || 50;
    if (distance <= radius && (!nearest || distance < nearest.distance)) {
      nearest = {index, distance};
    }
  }
  if (!nearest) return null;
  return nearest.index === 0 ? 'towardLastStop' : 'towardFirstStop';
}
