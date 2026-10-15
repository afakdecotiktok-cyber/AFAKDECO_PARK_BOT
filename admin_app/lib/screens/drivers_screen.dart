import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../widgets/app_widgets.dart';
import 'vehicle_history_screen.dart';

class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});

  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<dynamic> _drivers = [];
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final hadData = _drivers.isNotEmpty;
    setState(() {
      _loading = !hadData;
      _refreshing = hadData;
      _error = null;
    });
    try {
      final result = await Api.instance.drivers();
      if (!mounted) return;
      setState(() {
        _drivers = result;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      final message = friendlyError(error);
      setState(() => _error = message);
      if (hadData) AppSnackbar.error(context, message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (_loading && _drivers.isEmpty) {
      return const LoadingSkeletonList(count: 5, itemHeight: 78);
    }
    if (_error != null && _drivers.isEmpty) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    final filtered = _drivers.where((raw) {
      if (raw is! Map) return false;
      final driver = Map<String, dynamic>.from(raw);
      final name = (driver['name'] ?? '').toString().toLowerCase();
      final vehicle = (driver['vehicle'] ?? '').toString().toLowerCase();
      final userId = (driver['user_id'] ?? '').toString();
      final q = _query.trim().toLowerCase();
      return name.contains(q) || vehicle.contains(q) || userId.contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'السائقون',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${filtered.length} سائق',
                  style: AppText.body.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _search,
                  search: true,
                  hintText: 'ابحث باسم السائق أو رمز المركبة',
                  onChanged: (value) => setState(() => _query = value),
                ),
                if (_refreshing) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_error != null && _drivers.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: TextStyle(color: colors.pending, fontSize: 12),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
              ]),
            ),
          ),
          if (filtered.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: AppStrings.noDrivers,
                description: 'لا توجد نتائج تطابق البحث الحالي.',
                icon: Icons.people_outline_rounded,
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
                    final driver = Map<String, dynamic>.from(filtered[index]);
                    final name = (driver['name'] ?? '—').toString();
                    final vehicle = (driver['vehicle'] ?? '').toString().trim();
                    final approval = (driver['approval_status'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 23,
                              backgroundColor: colors.tint(colors.primary),
                              foregroundColor: colors.primary,
                              child: Text(
                                name.trim().isEmpty ? '؟' : name.trim().characters.first,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.section.copyWith(fontSize: 15),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Wrap(
                                    spacing: AppSpacing.sm,
                                    runSpacing: AppSpacing.xs,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      ActionChip(
                                        onPressed: vehicle.isEmpty
                                            ? null
                                            : () => Navigator.of(context).push(
                                                  MaterialPageRoute<void>(
                                                    builder: (_) => VehicleHistoryScreen(
                                                      vehicle: vehicle,
                                                      vehicleData: {
                                                        'vehicle': vehicle,
                                                        'drivers': [driver],
                                                      },
                                                    ),
                                                  ),
                                                ),
                                        avatar: Icon(
                                          Icons.directions_car_outlined,
                                          size: 16,
                                          color: vehicle.isEmpty ? colors.textSecondary : colors.primary,
                                        ),
                                        label: Text(vehicle.isEmpty ? 'غير مُعيَّن' : vehicle),
                                      ),
                                      if (approval.isNotEmpty)
                                        StatusChip(
                                          status: approval == 'approved' ? 'سليمة' : approval,
                                          label: approval == 'approved'
                                              ? 'معتمد'
                                              : approval == 'pending'
                                                  ? 'قيد الانتظار'
                                                  : approval == 'rejected'
                                                      ? 'مرفوض'
                                                      : approval,
                                          icon: approval == 'approved'
                                              ? Icons.verified_outlined
                                              : approval == 'rejected'
                                                  ? Icons.block_outlined
                                                  : Icons.hourglass_top_rounded,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            IconButton(
                              tooltip: 'عرض سجل السائق',
                              onPressed: () => AppBottomSheet.show<void>(
                                context,
                                builder: (_) => _DriverHistorySheet(
                                  userId: (driver['user_id'] ?? '').toString(),
                                  driverName: name,
                                ),
                              ),
                              icon: const Icon(Icons.history_rounded),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverHistorySheet extends StatefulWidget {
  const _DriverHistorySheet({
    required this.userId,
    required this.driverName,
  });

  final String userId;
  final String driverName;

  @override
  State<_DriverHistorySheet> createState() => _DriverHistorySheetState();
}

class _DriverHistorySheetState extends State<_DriverHistorySheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Api.instance.driverHistory(widget.userId);
      if (mounted) setState(() => _data = result);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? SizedBox(
                    height: 220,
                    child: ErrorState(message: _error!, onRetry: _load),
                  )
                : _buildHistory(context, colors),
      ),
    );
  }

  Widget _buildHistory(BuildContext context, AppColors colors) {
    final data = _data ?? const <String, dynamic>{};
    final driver = Map<String, dynamic>.from(data['driver'] ?? const {});
    final assignments = List<dynamic>.from(data['assignments'] ?? const []);
    final problems = List<dynamic>.from(data['problems'] ?? const []);
    final vehicle = (driver['vehicle'] ?? '').toString().trim();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (driver['name'] ?? widget.driverName).toString(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          const SectionHeader(title: 'المركبة الحالية'),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.directions_car_rounded, color: colors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(vehicle.isEmpty ? 'غير مُعيَّن' : vehicle)),
                if (vehicle.isNotEmpty)
                  IconButton(
                    tooltip: 'فتح سجل المركبة',
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (_) => VehicleHistoryScreen(
                            vehicle: vehicle,
                            vehicleData: {
                              'vehicle': vehicle,
                              'drivers': [driver],
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'سجل إسناد المركبات'),
          if (assignments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('لا يوجد سجل إسناد سابق.'),
            )
          else
            ...assignments.map((raw) {
              final item = Map<String, dynamic>.from(raw as Map);
              final until = (item['assigned_until'] ?? '').toString();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.route_outlined, color: colors.textSecondary),
                title: Text((item['vehicle'] ?? '—').toString()),
                subtitle: Text(
                  '${item['assigned_from'] ?? '—'}  ←  ${until.isEmpty ? 'حالياً' : until}',
                ),
              );
            }),
          const SizedBox(height: AppSpacing.md),
          const SectionHeader(title: 'الشكاوى والحوادث'),
          if (problems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('لا توجد شكاوى أو حوادث مسجلة لهذا السائق.'),
            )
          else
            ...problems.map((raw) {
              final item = Map<String, dynamic>.from(raw as Map);
              final accident = item['problem_type'] == 'accident';
              final status = item['ruglee'] == 'تم الإصلاح'
                  ? 'تم الإصلاح'
                  : accident
                      ? 'حادث'
                      : (item['status'] ?? 'قيد الانتظار').toString();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  accident ? Icons.warning_rounded : Icons.assignment_outlined,
                  color: colors.statusColor(accident ? 'accident' : status),
                ),
                title: Text(
                  (item['problem_text'] ?? 'سجل بدون وصف').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text((item['date'] ?? '').toString()),
                trailing: StatusChip(status: status),
              );
            }),
        ],
      ),
    );
  }
}
