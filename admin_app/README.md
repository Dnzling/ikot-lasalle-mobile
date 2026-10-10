# IKOT La Salle Admin

Desktop-first Flutter admin client connected to Firebase project
`ikot-lasalle-ccfab`.

## Firebase collections

- `users`: authentication profile, type, ID and contact details
- `vehicles`: capacity, type, status, location and live trip counters
- `drivers`: identity, assignment and performance totals
- `routes`: pickup `GeoPoint`, proximity radius and fare rules
- `transactions`: amount, type, vehicle type and `createdAt` timestamp

Run with `flutter run -d windows` for the native desktop application or
`flutter run -d chrome` for the web desktop layout. Firestore security rules
must grant authenticated administrators the required reads and writes.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
