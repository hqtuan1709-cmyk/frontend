// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huynh_quang_tuan_23dhtc5_nhom_dasani/main.dart';
import 'package:huynh_quang_tuan_23dhtc5_nhom_dasani/services/api_client.dart';

void main() {
  testWidgets('Shows sign-in screen when there is no saved session', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AttendanceApi.initialize();
    await tester.pumpWidget(const AttendanceApp());
    await tester.pumpAndSettle();

    expect(find.text('Chấm công Dasani'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
  });
}
