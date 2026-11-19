import 'package:intl/intl.dart';

/// Strips the time portion of [d] (local calendar date).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

/// Whole calendar days from [from] to [to]. Uses UTC math so daylight-saving
/// transitions (23/25 hour days) never throw the count off by one.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(to.year, to.month, to.day)
    .difference(DateTime.utc(from.year, from.month, from.day))
    .inDays;

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _two(int n) => n.toString().padLeft(2, '0');

/// Storage key for a calendar day, e.g. `2026-11-19`.
String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

DateTime parseDateKey(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// "6:00 AM", "Noon", "Midnight". Accepts minutes past 24:00 for overnight items.
String formatMinuteOfDay(int minuteOfDay) {
  final m = minuteOfDay % (24 * 60);
  if (m == 0) return 'Midnight';
  if (m == 12 * 60) return 'Noon';
  final hour = m ~/ 60;
  final minute = m % 60;
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:${_two(minute)} ${hour < 12 ? 'AM' : 'PM'}';
}

final _short = DateFormat('EEE, MMM d');
final _long = DateFormat('EEEE, MMMM d, y');
final _monthDay = DateFormat('MMM d');
final _monthDayYear = DateFormat('MMMM d, y');
final _weekday = DateFormat('EEEE');

/// "Wednesday"
String formatWeekday(DateTime d) => _weekday.format(d);

/// "November 19, 2026"
String formatMonthDayYear(DateTime d) => _monthDayYear.format(d);

/// "Wed, Nov 19"
String formatShort(DateTime d) => _short.format(d);

/// "Wednesday, November 19, 2026"
String formatLong(DateTime d) => _long.format(d);

/// "Nov 19"
String formatMonthDay(DateTime d) => _monthDay.format(d);

/// "today", "tomorrow", "in 3 days", "2 days ago".
String relativeDays(int days) {
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  return days > 1 ? 'in $days days' : '${-days} days ago';
}
