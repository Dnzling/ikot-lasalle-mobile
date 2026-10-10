import 'package:flutter_test/flutter_test.dart';
import 'package:ikot_lasalle/services/fare_direction.dart';

void main() {
  test('Route 1 to Route 5 uses default fare', () {
    expect(fareDirectionForRouteOrder(0, 4), FareDirection.defaultFare);
  });

  test('Route 4 to Route 2 wraps around and uses round trip fare', () {
    expect(fareDirectionForRouteOrder(3, 1), FareDirection.roundTrip);
  });

  test('same route cannot be booked', () {
    expect(() => fareDirectionForRouteOrder(2, 2), throwsArgumentError);
  });
}
