import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../widgets/app_widgets.dart';
import '../widgets/status_icons.dart';
import 'vehicle_history_screen.dart';

const dashboardFilters = <String>[
  'all',
  'accident',
  'pending',
  'in_progress',
  'vidange',
  'normal',
];

bool vehicleMatchesStatusFilter(dynamic rawVehicle, String filter) {
  if (filter == 'all') return true;
  if (rawVehicle is! Map) return false;
  final vehicle = Map<String, dynamic>.from(rawVehicle);
  final icons = List<dynamic>.from(vehicle['status_icons'] ?? const ['normal'])
      .map((item) => item.toString())
      .toSet();
  if (filter == 'normal') {
    return icons.contains('normal') &&
        !icons.any((item) =>
            item == 'accident' ||
            item == 'pending' ||
            item == 'in_progress' ||
            item == 'vidange');
  }
  return icons.contains(filter);
}

List<dynamic> filterDashboardVehicles(
  List<dynamic> vehicles, {
  required String query,
  required String status,
}) {
  final normalized = query.trim().toLowerCase();
  return vehicles.where((raw) {
    if (raw is! Map) return false;
    final vehicle = Map<String, dynamic>.from(raw);
    if (!vehicleMatchesStatusFilter(vehicle, status)) return false;
    if (normalized.isEmpty) return true;
    final drivers = List<dynamic>.from(vehicle['drivers'] ?? const []);
    final names = drivers.map((driver) {
      if (driver is Map) return (driver['name'] ?? '').toString();
      return '';
    }).join(' ');
    final haystack = '${vehicle['vehicle'] ?? ''} $names'.toLowerCase();
    return haystack.contains(normalized);
  }).toList();
}

Map<String, int> dashboardSummary(List<dynamic> vehicles) {
  var pending = 0;
  var inProgress = 0;
  var accident = 0;
  var vidange = 0;
  var normal = 0;
  for (final raw in vehicles) {
    if (raw is! Map) continue;
    final vehicle = Map<String, dynamic>.from(raw);
    final icons = List<dynamic>.from(vehicle['status_icons'] ?? const ['normal'])
        .map((item) => item.toString())
        .toSet();
    if (icons.contains('pending')) pending++;
    if (icons.contains('in_progress')) inProgress++;
    if (icons.contains('accident')) accident++;
    if (icons.contains('vidange')) vidange++;
    if (icons.contains('normal') &&
        !icons.any((item) =>
            item == 'accident' ||
            item == 'pending' ||
            item == 'in_progress' ||
            item == 'vidange')) {
      normal++;
    }
  }
  return {
    'all': vehicles.length,
    'pending': pending,
    'in_progress': inProgress,
    'accident': accident,
    'vidange': vidange,
    'normal': normal,
  };
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<dynamic> _vehicles = [];
  String _query = '';
  String _filter = 'all';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> refreshFromShell() => _load(showSuccess: true);

  Future<void> _load({bool showSuccess = false}) async {
    if (!mounted) return;
    final hadData = _vehicles.isNotEmpty;
    setState(() {
      _loading = !hadData;
      _refreshing = hadData;
      _error = null;
    });

    var succeeded = false;
    try {
      final fresh = await Api.instance.dashboard();
      if (!mounted) return;
      setState(() {
        _vehicles = fresh;
        _error = null;
      });
      succeeded = true;
    } catch (error) {
      if (!mounted) return;
      final message = friendlyError(error);
      setState(() => _error = message);
      if (hadData) {
        AppSnackbar.error(context, message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
    if (succeeded && showSuccess && mounted) {
      AppSnackbar.success(context, 'تم تحديث بيانات المركبات');
    } else if (!succeeded && !hadData && mounted && _error == null) {
      setState(() => _error = 'تعذر تحميل بيانات المركبات.');
    }
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _filter = 'all';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (_loading && _vehicles.isEmpty) {
      return const LoadingSkeletonList(count: 6, itemHeight: 82);
    }
    if (_error != null && _vehicles.isEmpty) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    final counts = dashboardSummary(_vehicles);
    final visible = filterDashboardVehicles(
      _vehicles,
      query: _query,
      status: _filter,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'لوحة المركبات',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'نظرة سريعة على حالة الأسطول',
                            style: AppText.body.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'شرح رموز الحالات',
                      onPressed: _showLegend,
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 112,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      SummaryTile(
                        value: '${counts['all']}',
                        label: 'كل المركبات',
                        icon: Icons.directions_car_filled_rounded,
                        statusKey: 'primary',
                        selected: _filter == 'all',
                        onTap: () => setState(() => _filter = 'all'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${counts['pending']}',
                        label: AppStrings.waiting,
                        icon: Icons.hourglass_top_rounded,
                        statusKey: 'pending',
                        selected: _filter == 'pending',
                        onTap: () => setState(() => _filter = 'pending'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${counts['in_progress']}',
                        label: AppStrings.inProgress,
                        icon: Icons.build_circle_rounded,
                        statusKey: 'in_progress',
                        selected: _filter == 'in_progress',
                        onTap: () => setState(() => _filter = 'in_progress'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${counts['accident']}',
                        label: AppStrings.accident,
                        icon: Icons.warning_rounded,
                        statusKey: 'accident',
                        selected: _filter == 'accident',
                        onTap: () => setState(() => _filter = 'accident'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${counts['vidange']}',
                        label: AppStrings.vidange,
                        icon: Icons.handyman_rounded,
                        statusKey: 'vidange',
                        selected: _filter == 'vidange',
                        onTap: () => setState(() => _filter = 'vidange'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${counts['normal']}',
                        label: 'سليمة',
                        icon: Icons.check_circle_rounded,
                        statusKey: 'normal',
                        selected: _filter == 'normal',
                        onTap: () => setState(() => _filter = 'normal'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppTextField(
                  controller: _searchController,
                  search: true,
                  hintText: 'ابحث برقم المركبة أو اسم السائق',
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _filter == 'all' ? 'المركبات' : _filterLabel(_filter),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Text(
                      '${visible.length} نتيجة',
                      style: AppText.caption.copyWith(color: colors.textSecondary),
                    ),
                    if (_query.isNotEmpty || _filter != 'all')
                      TextButton(
                        onPressed: _clearFilters,
                        child: const Text('مسح التصفية'),
                      ),
                  ],
                ),
                if (_refreshing) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_error != null && _vehicles.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.tint(colors.pending),
                      borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                    ),
                    child: Text(
                      _error!,
                      style: AppText.caption.copyWith(color: colors.pending),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: _vehicles.isEmpty ? Icons.directions_car_outlined : Icons.search_off_rounded,
                title: _vehicles.isEmpty ? AppStrings.noVehicles : 'لا توجد نتائج مطابقة',
                description: _vehicles.isEmpty ? null : 'جرّب تغيير البحث أو الحالة المحددة.',
                actionLabel: _query.isNotEmpty || _filter != 'all' ? 'مسح التصفية' : null,
                onAction: _query.isNotEmpty || _filter != 'all' ? _clearFilters : null,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final vehicle = Map<String, dynamic>.from(visible[index]);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _VehicleCard(
                        vehicle: vehicle,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => VehicleHistoryScreen(
                              vehicle: (vehicle['vehicle'] ?? '').toString(),
                              vehicleData: vehicle,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showLegend() {
    AppBottomSheet.show<void>(
      context,
      builder: (sheetContext) {
        final colors = AppColors.of(sheetContext);
        const data = <(String, String, IconData)>[
          ('accident', 'حادث', Icons.warning_rounded),
          ('pending', 'قيد الانتظار', Icons.hourglass_top_rounded),
          ('in_progress', 'قيد التصليح', Icons.build_circle_rounded),
          ('vidange', 'Vidange', Icons.handyman_rounded),
          ('normal', 'سليمة', Icons.check_circle_rounded),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('شرح رموز الحالات', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              ...data.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(item.$3, color: colors.statusColor(item.$1)),
                    title: Text(item.$2),
                  )),
            ],
          ),
        );
      },
    );
  }
}

String _filterLabel(String value) => switch (value) {
      'accident' => AppStrings.accident,
      'pending' => AppStrings.waiting,
      'in_progress' => AppStrings.inProgress,
      'vidange' => AppStrings.vidange,
      'normal' => 'سليمة',
      _ => AppStrings.dashboard,
    };

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.onTap});

  final Map<String, dynamic> vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final code = (vehicle['vehicle'] ?? '—').toString();
    final drivers = List<dynamic>.from(vehicle['drivers'] ?? const []);
    final driverNames = drivers
        .whereType<Map>()
        .map((driver) => (driver['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .join(' • ');
    final rawRemaining = vehicle['remaining_km'];
    final remaining = rawRemaining is num ? rawRemaining.toInt() : int.tryParse('$rawRemaining');
    final overdue = remaining != null && remaining < 0;
    final icons = List<dynamic>.from(vehicle['status_icons'] ?? const ['normal']);
    final dominant = icons.contains('accident')
        ? 'accident'
        : icons.contains('pending')
            ? 'pending'
            : icons.contains('in_progress')
                ? 'in_progress'
                : icons.contains('vidange')
                    ? 'vidange'
                    : 'normal';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (dominant != 'normal')
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: colors.statusColor(dominant)),
            ),
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 14, 13),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.tint(colors.statusColor(dominant)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.directions_car_filled_rounded,
                      color: colors.statusColor(dominant),
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(color: colors.textPrimary, fontSize: 15),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          driverNames.isEmpty ? 'بدون سائق حالي' : driverNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: colors.textSecondary),
                        ),
                        if (remaining != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.speed_rounded,
                                size: 14,
                                color: overdue ? colors.pending : colors.vidange,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    overdue
                                        ? 'تجاوز موعد Vidange بـ ${remaining.abs()} KM'
                                        : 'المتبقي لـ Vidange: $remaining KM',
                                    textAlign: TextAlign.start,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.caption.copyWith(
                                      color: overdue ? colors.pending : colors.textSecondary,
                                      fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 76),
                    child: StatusIcons(icons: icons),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
