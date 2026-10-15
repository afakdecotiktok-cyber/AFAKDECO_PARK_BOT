import 'package:flutter_test/flutter_test.dart';
import 'package:afakdeco_admin/screens/dashboard_screen.dart';

void main() {
  const vehicles = <dynamic>[
    {
      'vehicle': 'A01',
      'drivers': [{'name': 'أحمد'}],
      'status_icons': ['pending', 'vidange'],
    },
    {
      'vehicle': 'B02',
      'drivers': [{'name': 'سليم'}],
      'status_icons': ['in_progress', 'vidange'],
    },
    {
      'vehicle': 'C03',
      'drivers': [],
      'status_icons': ['accident'],
    },
    {
      'vehicle': 'D04',
      'drivers': [],
      'status_icons': ['normal'],
    },
  ];

  test('a vehicle with multiple indicators matches each relevant filter', () {
    expect(filterDashboardVehicles(vehicles, query: '', status: 'pending'), hasLength(1));
    expect(filterDashboardVehicles(vehicles, query: '', status: 'vidange'), hasLength(2));
    expect(filterDashboardVehicles(vehicles, query: '', status: 'in_progress'), hasLength(1));
  });

  test('search matches vehicle code and driver name', () {
    expect(filterDashboardVehicles(vehicles, query: 'a01', status: 'all'), hasLength(1));
    expect(filterDashboardVehicles(vehicles, query: 'أحمد', status: 'all'), hasLength(1));
  });

  test('summary counts each backend indicator without collapsing combinations', () {
    final summary = dashboardSummary(vehicles);
    expect(summary['all'], 4);
    expect(summary['pending'], 1);
    expect(summary['in_progress'], 1);
    expect(summary['accident'], 1);
    expect(summary['vidange'], 2);
    expect(summary['normal'], 1);
  });
}
