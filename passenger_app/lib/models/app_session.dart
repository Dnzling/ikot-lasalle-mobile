import 'package:flutter/foundation.dart';
import 'passenger.dart';

class AppSession extends ChangeNotifier {
  AppSession({
    required this.uid,
    required this.sessionId,
    required Passenger passenger,
  }) : _passenger = passenger;
  final String uid;
  final String sessionId;
  Passenger _passenger;
  Passenger get passenger => _passenger;

  void updatePassenger(Passenger passenger) {
    _passenger = passenger;
    notifyListeners();
  }
}
