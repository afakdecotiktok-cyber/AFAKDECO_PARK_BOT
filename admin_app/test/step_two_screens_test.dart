import 'package:flutter_test/flutter_test.dart';
import 'package:afakdeco_admin/screens/problems_screen.dart';
import 'package:afakdeco_admin/screens/vidange_screen.dart';

void main() {
  group('Reclamation filters and order', () {
    final problems = <dynamic>[
      {'id': 1, 'vehicle': 'A01', 'driver_name': 'Ali', 'problem_type': 'reclamation', 'status': 'قيد الانتظار', 'date': '2026-01-01 10:00:00', 'problem_text': 'brakes'},
      {'id': 2, 'vehicle': 'B02', 'driver_name': 'Samir', 'problem_type': 'accident', 'status': 'قيد الانتظار', 'date': '2026-02-01 10:00:00', 'problem_text': 'crash'},
      {'id': 3, 'vehicle': 'A01', 'driver_name': 'Ali', 'problem_type': 'reclamation', 'status': 'قيد التصليح', 'date': '2026-03-01 10:00:00', 'problem_text': 'engine'},
      {'id': 4, 'vehicle': 'C03', 'driver_name': 'Nora', 'problem_type': 'reclamation', 'status': 'قيد الانتظار', 'date': 'not-a-date', 'problem_text': 'lamp', 'media_type': 'نظام'},
      {'id': 5, 'vehicle': 'A01', 'driver_name': 'Ali', 'problem_type': 'reclamation', 'ruglee': 'تم الإصلاح', 'date': '2026-01-15 10:00:00', 'problem_text': 'fixed'},
    ];

    test('filters by type, status, date and searchable fields', () {
      expect(filterProblems(problems, type: 'accident'), hasLength(1));
      expect(filterProblems(problems, type: 'reclamation'), hasLength(3));
      expect(filterProblems(problems, type: 'vidange'), hasLength(1));
      expect(filterProblems(problems, status: 'in_progress').single['id'], 3);
      expect(filterProblems(problems, date: '2026-03-01').single['id'], 3);
      expect(filterProblems(problems, query: 'brakes').single['id'], 1);
      expect(filterProblems(problems, query: 'A01'), hasLength(3));
    });

    test('newest-first sort keeps invalid dates after valid dates', () {
      final sorted = sortProblemsNewestFirst(problems);
      expect(sorted.first['id'], 3);
      expect(sorted.last['id'], 4);
    });

    test('summary counts status and special types without losing records', () {
      final counts = problemSummary(problems);
      expect(counts['all'], 5);
      expect(counts['pending'], 1);
      expect(counts['in_progress'], 1);
      expect(counts['accident'], 1);
      expect(counts['fixed'], 1);
      expect(counts['vidange'], 1);
    });
  });

  group('Vidange overview calculations', () {
    final rows = <dynamic>[
      {'vehicle': 'A01', 'last_vidange_km': 10000, 'latest_km': 21500, 'remaining_km': -1500},
      {'vehicle': 'B02', 'last_vidange_km': 5000, 'latest_km': 14500, 'remaining_km': 500},
      {'vehicle': 'C03', 'last_vidange_km': 7000, 'latest_km': 10000, 'remaining_km': 4000},
      {'vehicle': 'D04', 'last_vidange_km': 0, 'latest_km': null, 'remaining_km': null},
    ];

    test('classifies overdue, upcoming, on-track and missing data', () {
      expect(vidangeStatusKey(Map<String, dynamic>.from(rows[0] as Map)), 'overdue');
      expect(vidangeStatusKey(Map<String, dynamic>.from(rows[1] as Map)), 'due_soon');
      expect(vidangeStatusKey(Map<String, dynamic>.from(rows[2] as Map)), 'on_track');
      expect(vidangeStatusKey(Map<String, dynamic>.from(rows[3] as Map)), 'unknown');
    });

    test('summary and filters put urgent vehicles first', () {
      expect(vidangeSummary(rows), {
        'all': 4,
        'overdue': 1,
        'due_soon': 1,
        'on_track': 1,
        'unknown': 1,
      });
      expect(filterVidangeRows(rows, status: 'overdue').single['vehicle'], 'A01');
      expect(filterVidangeRows(rows, query: 'c03').single['vehicle'], 'C03');
      expect(filterVidangeRows(rows).map((row) => row['vehicle']).toList(), ['A01', 'B02', 'D04', 'C03']);
    });
  });
}
