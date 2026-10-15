import 'package:flutter_test/flutter_test.dart';
import 'package:afakdeco_admin/screens/vehicle_history_screen.dart';

void main() {
  test('selects the newest reading even when API input is unsorted', () {
    final latest = selectLatestReading([
      {'km': 12000, 'date': '2026-01-01 10:00:00'},
      {'km': 24000, 'date': '2026-03-08 09:30:00'},
      {'km': 18000, 'date': '2026-02-01 12:00:00'},
    ]);
    expect(latest?['km'], 24000);
  });

  test('valid dates sort before missing or invalid dates', () {
    final sorted = sortReadingsNewestFirst([
      {'km': 7000, 'date': 'not-a-date'},
      {'km': 9000, 'date': null},
      {'km': 11000, 'date': '2026-04-20 08:00:00'},
    ]);
    expect(sorted.first['km'], 11000);
    expect(sorted[1]['km'], 7000);
    expect(sorted[2]['km'], 9000);
  });

  test('equal timestamps keep stable source order', () {
    final latest = selectLatestReading([
      {'km': 8000, 'date': '2026-05-01 10:00:00'},
      {'km': 8100, 'date': '2026-05-01 10:00:00'},
    ]);
    expect(latest?['km'], 8000);
  });

  test('returns null when there are no readings', () {
    expect(selectLatestReading([]), isNull);
    expect(sortReadingsNewestFirst([]), isEmpty);
  });
}
