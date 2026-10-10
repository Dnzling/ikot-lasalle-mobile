class MapboxConfig {
  const MapboxConfig._();

  // Public Mapbox token supplied for the IKOT La Salle admin map.
  static const accessToken =
      'pk.eyJ1IjoiZW56bzY0MTAiLCJhIjoiY210dnhwOHNsMDM5eTJ6cWJ1ZTdjbGFvdSJ9.FZkPC_QFcFgXLypBjbJWug';

  static const streetsTileUrl =
      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=$accessToken';
}
