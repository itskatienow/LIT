import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lit/data/app_store.dart';
import 'package:lit/main.dart';
import 'package:lit/models/protocol.dart';
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

  testWidgets('shows the Prime phase and logs domperidone', (tester) async {
    final start = addDays(today(), -11); // today is Day 12
    final store = await pumpApp(tester, prefs: {
      'lit.settings.v1': '{"startDate":"${dateKey(start)}"}',
    });

    expect(find.text('PRIME PHASE'), findsOneWidget);
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

  testWidgets('estradiol method and doses in Settings, logged on the dashboard', (tester) async {
    // A small phone (360 × 780) to catch layout overflow.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await pumpApp(tester, prefs: {
      'lit.settings.v1': '{"startDate":"${dateKey(addDays(today(), -11))}"}',
    });
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    Future<void> type(String field, String text) async {
      final finder = find.widgetWithText(TextField, field);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.enterText(finder, text);
      await tester.pump();
    }

    Future<void> tapText(String text, {Finder? within}) async {
      final finder = within == null ? find.text(text) : find.descendant(of: within, matching: find.text(text));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    // Injection is the default: 6 mg a week over 3 injections.
    expect(find.text('2 mg per injection'), findsOneWidget);

    await type('Weekly dose', '5');
    await type('Strength', '5');
    expect(find.text('2 mg · 0.4 mL per injection'), findsOneWidget); // 1.67 mg rounded up

    await tapText('2', within: find.byType(SegmentedButton<int>));
    expect(find.text('2.5 mg · 0.5 mL per injection'), findsOneWidget);
    expect(find.text('Saturday injection'), findsOneWidget); // the evening time's use

    await tapText('Sublingual');
    expect(find.text('Enter your daily dose'), findsOneWidget);
    final estradiolDaily = find.byKey(const ValueKey('estradiol-daily'));
    await tester.ensureVisible(estradiolDaily);
    await tester.pumpAndSettle();
    await tester.enterText(estradiolDaily, '3');
    await tester.pump();
    expect(find.text('1.5 mg morning + 1.5 mg evening'), findsOneWidget);

    final progesterone = find.byKey(const ValueKey('progesterone-dose'));
    expect(tester.widget<TextField>(progesterone).controller!.text, '300');
    await tester.ensureVisible(progesterone);
    await tester.pumpAndSettle();
    await tester.enterText(progesterone, '200');
    await tester.pump();
    expect(store.settings.progesteroneMg, 200);

    final plan = store.settings.estradiol;
    expect(plan.method, EstradiolMethod.sublingual);
    expect(plan.dailyDoseMg, 3);
    expect(plan.weeklyDoseMg, 5); // injection settings are kept for switching back
    expect(plan.injectionsPerWeek, 2);

    // The dashboard logs sublingual doses with a 0–2 counter.
    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle();
    expect(find.text('Sublingual Estradiol'), findsOneWidget);
    expect(find.text('1.5 mg morning + 1.5 mg evening'), findsOneWidget);
    expect(find.textContaining('200 mg tonight'), findsOneWidget); // Day 12
    final increase = find.byTooltip('Increase estradiol doses');
    await tester.ensureVisible(increase);
    await tester.pumpAndSettle();
    await tester.tap(increase);
    await tester.pump();
    await tester.tap(increase);
    await tester.pump();
    expect(store.entryFor(today()).estradiolDoses, 2);
    await tester.tap(increase, warnIfMissed: false); // disabled at 2
    await tester.pump(const Duration(seconds: 1)); // lets the debounced save run
    expect(store.entryFor(today()).estradiolDoses, 2);
  });

  testWidgets('navigates to Trends and Settings', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.text('Latest 7-day average'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('10 mg Tablets'), findsOneWidget);
  });
}
