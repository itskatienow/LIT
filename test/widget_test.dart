import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lit/data/app_store.dart';
import 'package:lit/main.dart';
import 'package:lit/services/notification_service.dart';
import 'package:lit/util/dates.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppStore> pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await AppStore.load();
    // NotificationService is left uninitialised, so it stays a no-op in tests.
    await tester.pumpWidget(LitApp(store: store, notifications: NotificationService()));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('shows setup prompt without a start date', (tester) async {
    await pumpApp(tester);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Set your start date'), findsOneWidget);
    expect(find.text('PROTOCOL'), findsOneWidget);
  });

  testWidgets('shows the Build phase and logs domperidone', (tester) async {
    final start = addDays(today(), -11); // today is Day 12
    final store = await pumpApp(tester, prefs: {
      'lit.settings.v1': '{"startDate":"${dateKey(start)}"}',
    });

    expect(find.text('BUILD PHASE'), findsOneWidget);
    expect(find.text('Day 12'), findsOneWidget);
    expect(find.text('of 40'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Increase domperidone tablets'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase domperidone tablets'));
    await tester.pump();
    expect(store.entryFor(today()).domperidoneTablets, 1);

    // Pumping details appear once "Pumped" is switched on.
    expect(find.text('Total output'), findsNothing);
    await tester.ensureVisible(find.text('Pumped'));
    await tester.tap(find.text('Pumped'));
    await tester.pumpAndSettle();
    expect(find.text('Total output'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Total output'), '42.5');
    expect(store.entryFor(today()).outputMl, 42.5);

    // Edits are written to disk after a short debounce.
    await tester.pump(const Duration(seconds: 1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('lit.entries.v1'), contains('"outputMl":42.5'));
  });

  testWidgets('navigates to Trends and Settings', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.text('Latest 7-day average'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('Tablets on hand'), findsOneWidget);
  });
}
