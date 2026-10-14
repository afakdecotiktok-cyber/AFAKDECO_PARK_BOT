import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/status_icons.dart';
import 'problems_screen.dart';
import 'drivers_screen.dart';
import 'vehicle_history_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

const _ink = Color(0xFF172033);
const _muted = Color(0xFF68748A);
const _blue = Color(0xFF315AE7);

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
    if (mounted) setState(() => loading = true);
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
          titleSpacing: 20,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 11),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AFAKDECO PARK'),
                  Text('لوحة الإدارة', style: TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w500, letterSpacing: 0)),
                ],
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: IconButton.filledTonal(
                onPressed: load,
                tooltip: 'تحديث البيانات',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _blue,
                  side: const BorderSide(color: Color(0xFFE3E8F2)),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ],
        ),
        body: pages[tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment_rounded), label: 'الشكاوى'),
            NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt_rounded), label: 'السائقون'),
            NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'الإعدادات'),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 42, color: _muted),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF315AE7), Color(0xFF243FB3)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Color(0x1C315AE7), blurRadius: 22, offset: Offset(0, 9))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إدارة أسطول المركبات', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      const SizedBox(height: 6),
                      Text('متابعة المركبات وحالاتها من مكان واحد', style: TextStyle(color: Colors.white.withValues(alpha: .84), fontSize: 13)),
                      const SizedBox(height: 17),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
                        child: Text('${filtered.length} مركبة معروضة', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(19)),
                  child: const Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 31),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: Text('المركبات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.3))),
              Text('${filtered.length} نتيجة', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 11),
          TextField(
            controller: search,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'ابحث برقم المركبة أو اسم السائق',
              suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: () { search.clear(); onSearchChanged(); }, icon: const Icon(Icons.close_rounded)),
            ),
          ),
          const SizedBox(height: 13),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE7EBF3))),
              child: const Column(
                children: [
                  Icon(Icons.search_off_rounded, color: _muted, size: 32),
                  SizedBox(height: 8),
                  Text('لا توجد مركبات مطابقة', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ...filtered.map((raw) {
            final v = Map<String, dynamic>.from(raw);
            final drivers = List<dynamic>.from(v['drivers'] ?? []);
            final remaining = v['remaining_km'];
            final int? remainingKm = remaining is num ? remaining.toInt() : int.tryParse('$remaining');
            final bool overdue = remainingKm != null && remainingKm < 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onVehicle(v['vehicle'].toString()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.directions_car_rounded, color: _blue, size: 25),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v['vehicle'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(
                                drivers.isEmpty ? 'بدون سائق حالي' : drivers.map((d) => (d as Map)['name'] ?? '').join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _muted, fontSize: 12),
                              ),
                              if (remainingKm != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.speed_rounded, size: 14, color: overdue ? const Color(0xFFDC4545) : const Color(0xFF199B78)),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        overdue ? 'تجاوز موعد Vidange بـ ${remainingKm.abs()} KM' : 'المتبقي لـ Vidange: $remainingKm KM',
                                        style: TextStyle(color: overdue ? const Color(0xFFDC4545) : const Color(0xFF199B78), fontSize: 11, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusIcons(icons: List<dynamic>.from(v['status_icons'] ?? ['normal'])),
                            const SizedBox(height: 8),
                            const Icon(Icons.chevron_left_rounded, color: Color(0xFF9AA4B5), size: 20),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
