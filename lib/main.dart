import 'dart:async';

import 'package:flutter/material.dart';

import 'data/app_store.dart';
import 'pages/dashboard_page.dart';
import 'pages/settings_page.dart';
import 'pages/trends_page.dart';
import 'services/notification_service.dart';
import 'ui/theme.dart';
import 'util/dates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.load();
  final notifications = NotificationService();
  await notifications.init();
  runApp(LitApp(store: store, notifications: notifications));
}

class LitApp extends StatelessWidget {
  const LitApp({super.key, required this.store, required this.notifications});

  final AppStore store;
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LIT',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeShell(store: store, notifications: notifications),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store, required this.notifications});

  final AppStore store;
  final NotificationService notifications;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  final _selectedDate = ValueNotifier<DateTime>(today());
  DateTime _knownToday = today();
  Object? _reminderSignature;
  Timer? _rescheduleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminderSignature = widget.store.settings.reminderSignature;
    widget.store.addListener(_onStoreChanged);
    _reschedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_onStoreChanged);
    _rescheduleTimer?.cancel();
    _selectedDate.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // If the app was left open on "today" overnight, follow the new day.
        final now = today();
        if (!isSameDay(now, _knownToday)) {
          if (isSameDay(_selectedDate.value, _knownToday)) _selectedDate.value = now;
          _knownToday = now;
        }
        _reschedule();
      case AppLifecycleState.inactive || AppLifecycleState.paused || AppLifecycleState.detached:
        widget.store.flush();
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _onStoreChanged() {
    final signature = widget.store.settings.reminderSignature;
    if (signature == _reminderSignature) return;
    _reminderSignature = signature;
    _rescheduleTimer?.cancel();
    _rescheduleTimer = Timer(const Duration(milliseconds: 600), _reschedule);
  }

  void _reschedule() => widget.notifications.reschedule(widget.store.settings);

  void _openDate(DateTime date) {
    _selectedDate.value = date;
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(
            store: widget.store,
            selectedDate: _selectedDate,
            onOpenSettings: () => setState(() => _index = 2),
          ),
          TrendsPage(store: widget.store, onOpenDate: _openDate),
          SettingsPage(store: widget.store, notifications: widget.notifications),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Trends',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
