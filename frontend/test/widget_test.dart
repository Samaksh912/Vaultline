// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaultline/main.dart';
import 'package:vaultline/ui.dart';

void main() {
  testWidgets('Vaultline app loads the auth screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const VaultlineApp());
    await tester.pumpAndSettle();

    expect(find.text('Vaultline'), findsOneWidget);
    expect(find.text('Confirm it\'s you to continue'), findsOneWidget);
  });

  testWidgets('SafeImagePreview shows a placeholder when the file is missing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SafeImagePreview(
            path: '/tmp/does-not-exist.jpg',
            placeholderText: 'Preview unavailable',
          ),
        ),
      ),
    );

    expect(find.text('Preview unavailable'), findsOneWidget);
  });

  test('Capture exposes manual voice recording controls', () {
    final cap = Capture();

    expect(cap.startVoiceCapture, isA<Future<void> Function()>());
    expect(cap.stopVoiceCapture, isA<Future<String> Function()>());

    cap.dispose();
  });
}
