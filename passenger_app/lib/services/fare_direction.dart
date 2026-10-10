enum FareDirection { defaultFare, roundTrip }

FareDirection fareDirectionForRouteOrder(int pickupIndex, int destinationIndex) {
  if (pickupIndex < 0 || destinationIndex < 0 || pickupIndex == destinationIndex) {
    throw ArgumentError('Choose different pickup and destination routes.');
  }
  return destinationIndex > pickupIndex
      ? FareDirection.defaultFare
      : FareDirection.roundTrip;
}
