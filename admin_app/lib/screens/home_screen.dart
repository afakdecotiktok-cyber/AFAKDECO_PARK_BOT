import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_widgets.dart';
import 'dashboard_screen.dart';
import 'drivers_screen.dart';
import 'login_screen.dart';
import 'problems_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dashboardKey = GlobalKey<DashboardScreenState>();
  int _tab = 0;
  bool _refreshing = false;

  Future<void> _refreshDashboard() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _dashboardKey.currentState?.refreshFromShell();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    try {
      await Api.instance.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) AppSnackbar.error(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pages = <Widget>[
      DashboardScreen(key: _dashboardKey),
      const ProblemsScreen(),
      const DriversScreen(),
      SettingsScreen(onLogout: _logout),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.local_shipping_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 21,
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 3),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppStrings.appName),
                  Text(
                    'لوحة الإدارة',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
            child: IconButton(
              tooltip: 'تحديث البيانات',
              onPressed: _refreshing ? null : _refreshDashboard,
              icon: _refreshing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: AppStrings.dashboard,
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: AppStrings.problems,
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt_rounded),
            label: AppStrings.drivers,
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: AppStrings.settings,
          ),
        ],
      ),
    );
  }
}
