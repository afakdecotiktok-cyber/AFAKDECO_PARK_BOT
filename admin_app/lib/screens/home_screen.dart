import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/status_icons.dart';
import 'problems_screen.dart';
import 'drivers_screen.dart';
import 'vehicle_history_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  bool loading = true;
  String? error;
  List<dynamic> vehicles = [];
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      vehicles = await Api.instance.dashboard();
      error = null;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> logout() async {
    await Api.instance.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Dash(
        vehicles: vehicles,
        loading: loading,
        error: error,
        search: search,
        reload: load,
        onSearchChanged: () => setState(() {}),
        onVehicle: (v) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VehicleHistoryScreen(vehicle: v)),
        ),
      ),
      const ProblemsScreen(),
      const DriversScreen(),
      SettingsScreen(onLogout: logout),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AFAKDECO PARK'),
          actions: [
            IconButton(onPressed: load, tooltip: 'تحديث البيانات', icon: const Icon(Icons.refresh)),
          ],
        ),
        body: pages[tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.report_problem_outlined), label: 'الشكاوى'),
            NavigationDestination(icon: Icon(Icons.people_outline), label: 'السائقون'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }
}

class _Dash extends StatelessWidget {
  final List<dynamic> vehicles;
  final bool loading;
  final String? error;
  final TextEditingController search;
  final Future<void> Function() reload;
  final VoidCallback onSearchChanged;
  final void Function(String) onVehicle;

  const _Dash({
    required this.vehicles,
    required this.loading,
    required this.error,
    required this.search,
    required this.reload,
    required this.onSearchChanged,
    required this.onVehicle,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(error!), const SizedBox(height: 10), FilledButton(onPressed: reload, child: const Text('إعادة المحاولة'))],
        ),
      );
    }
    final query = search.text.trim().toLowerCase();
    final filtered = vehicles.where((raw) {
      final v = Map<String, dynamic>.from(raw);
      final drivers = List<dynamic>.from(v['drivers'] ?? []);
      final haystack = '${v['vehicle'] ?? ''} ${drivers.map((d) => (d as Map)['name'] ?? '').join(' ')}'.toLowerCase();
      return haystack.contains(query);
    }).toList();

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('لوحة المركبات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${filtered.length} من ${vehicles.length} مركبة', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: search,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ابحث برقم المركبة أو اسم السائق',
              suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: () { search.clear(); onSearchChanged(); }, icon: const Icon(Icons.close)),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('لا توجد مركبات مطابقة'))),
          ...filtered.map((raw) {
            final v = Map<String, dynamic>.from(raw);
            final drivers = List<dynamic>.from(v['drivers'] ?? []);
            final remaining = v['remaining_km'];
            final int? remainingKm = remaining is num ? remaining.toInt() : int.tryParse('$remaining');
            final bool overdue = remainingKm != null && remainingKm < 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 5),
              child: ListTile(
                dense: true,
                visualDensity: const VisualDensity(vertical: -1),
                leading: const Icon(Icons.directions_car_outlined, size: 27),
                title: Text(v['vehicle'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drivers.isEmpty ? 'بدون سائق حالي' : drivers.map((d) => (d as Map)['name'] ?? '').join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (remainingKm != null)
                      Text(
                        overdue ? 'تجاوز موعد Vidange بـ ${remainingKm.abs()} KM' : 'المتبقي لـ Vidange: $remainingKm KM',
                        style: TextStyle(color: overdue ? Colors.red : Colors.grey.shade700, fontSize: 12, fontWeight: overdue ? FontWeight.w700 : FontWeight.normal),
                      ),
                  ],
                ),
                trailing: StatusIcons(icons: List<dynamic>.from(v['status_icons'] ?? ['normal'])),
                onTap: () => onVehicle(v['vehicle'].toString()),
              ),
            );
          }),
        ],
      ),
    );
  }
}
