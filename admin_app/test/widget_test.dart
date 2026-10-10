import 'package:admin_page/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows desktop admin login', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const MyApp());
    expect(find.text('IKOT LA SALLE'), findsNWidgets(3));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
