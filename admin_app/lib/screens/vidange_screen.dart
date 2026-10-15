import 'package:flutter/material.dart';

import '../l10n/strings.dart';

import '../services/api.dart';
import '../services/app_data_events.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../widgets/app_widgets.dart';

int? _km(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

String vidangeStatusKey(Map<String, dynamic> row) {
  final last = _km(row['last_vidange_km']);
  final latest = _km(row['latest_km']);
  final remaining = _km(row['remaining_km']) ??
      (last != null && latest != null && last > 0 ? last + 10000 - latest : null);
  if (last == null || latest == null || last <= 0 || remaining == null) {
    return 'unknown';
  }
  if (remaining < 0) return 'overdue';
  if (remaining <= 1000) return 'due_soon';
  return 'on_track';
}

String vidangeStatusLabel(String status) => switch (status) {
      'overdue' => 'تجاوز الموعد',
      'due_soon' => 'اقترب الموعد',
      'on_track' => 'ضمن الموعد',
      _ => 'بيانات ناقصة',
    };

Map<String, int> vidangeSummary(List<dynamic> input) {
  var overdue = 0;
  var dueSoon = 0;
  var onTrack = 0;
  var unknown = 0;
  for (final raw in input) {
    if (raw is! Map) continue;
    switch (vidangeStatusKey(Map<String, dynamic>.from(raw))) {
      case 'overdue':
        overdue++;
      case 'due_soon':
        dueSoon++;
      case 'on_track':
        onTrack++;
      default:
        unknown++;
    }
  }
  return {
    'all': input.length,
    'overdue': overdue,
    'due_soon': dueSoon,
    'on_track': onTrack,
    'unknown': unknown,
  };
}

List<Map<String, dynamic>> filterVidangeRows(
  List<dynamic> input, {
  String query = '',
  String status = 'all',
}) {
  final normalized = query.trim().toLowerCase();
  final result = input.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
      .where((row) {
    final key = vidangeStatusKey(row);
    final matchesStatus = switch (status) {
      'overdue' => key == 'overdue',
      'due_soon' => key == 'due_soon',
      'on_track' => key == 'on_track',
      'unknown' => key == 'unknown',
      _ => true,
    };
    return matchesStatus &&
        (row['vehicle'] ?? '').toString().toLowerCase().contains(normalized);
  }).toList();
  const priority = {'overdue': 0, 'due_soon': 1, 'unknown': 2, 'on_track': 3};
  result.sort((a, b) {
    final byStatus = (priority[vidangeStatusKey(a)] ?? 9)
        .compareTo(priority[vidangeStatusKey(b)] ?? 9);
    return byStatus != 0
        ? byStatus
        : (a['vehicle'] ?? '').toString().compareTo((b['vehicle'] ?? '').toString());
  });
  return result;
}

class VidangeOverviewScreen extends StatefulWidget {
  const VidangeOverviewScreen({super.key});

  @override
  State<VidangeOverviewScreen> createState() => _VidangeOverviewScreenState();
}

class _VidangeOverviewScreenState extends State<VidangeOverviewScreen> {
  final _search = TextEditingController();
  List<dynamic> _rows = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _savingCode;
  String? _error;
  String _filter = 'all';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    AppDataEvents.revision.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    AppDataEvents.revision.removeListener(_onDataChanged);
    _search.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    final hadData = _rows.isNotEmpty;
    setState(() {
      _loading = !hadData;
      _refreshing = hadData;
      _error = null;
    });
    try {
      final result = await Api.instance.vidange();
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = result;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = friendlyError(error));
      if (hadData) AppSnackbar.error(context, friendlyError(error));
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    if (_savingCode != null) return;
    final vehicle = (row['vehicle'] ?? '').toString();
    final oldValue = _km(row['last_vidange_km']);
    final latest = _km(row['latest_km']);
    final controller = TextEditingController(text: oldValue?.toString() ?? '');
    try {
      final raw = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('تعديل Vidange • $vehicle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('القيمة السابقة: ${oldValue == null || oldValue == 0 ? 'غير مسجلة' : '$oldValue KM'}'),
              Text('آخر قراءة: ${latest == null ? 'غير متوفرة' : '$latest KM'}'),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: controller,
                labelText: 'قيمة آخر Vidange (KM)',
                digitsOnly: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('متابعة')),
          ],
        ),
      );
      if (raw == null || !mounted) return;
      final value = int.tryParse(raw);
      if (value == null || value < 0) {
        AppSnackbar.error(context, 'أدخل قيمة كيلومترات صحيحة لا تقل عن صفر.');
        return;
      }
      final accepted = await ConfirmDialog.show(
        context,
        title: 'تأكيد حفظ Vidange',
        message: 'المركبة: $vehicle\nالقيمة السابقة: ${oldValue ?? 'غير مسجلة'} KM\nالقيمة الجديدة: $value KM\nالقيمة القادمة: ${value + 10000} KM',
        confirmLabel: 'تأكيد وحفظ',
      );
      if (accepted != true || !mounted) return;
      setState(() => _savingCode = vehicle);
      try {
        final result = await Api.instance.setVidange(vehicle, value);
        if (mounted) {
          AppSnackbar.success(
            context,
            'تم الحفظ. القيمة القادمة: ${result['next_vidange_km'] ?? value + 10000} KM',
          );
        }
      } catch (error) {
        if (mounted) AppSnackbar.error(context, friendlyError(error));
      } finally {
        if (mounted) setState(() => _savingCode = null);
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (_loading && _rows.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('متابعة Vidange')),
        body: const LoadingSkeletonList(count: 5, itemHeight: 130),
      );
    }
    if (_error != null && _rows.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('متابعة Vidange')),
        body: ErrorState(message: _error!, onRetry: _load),
      );
    }
    final summary = vidangeSummary(_rows);
    final visible = filterVidangeRows(_rows, query: _search.text, status: _filter);
    return Scaffold(
      appBar: AppBar(
        title: const Text('متابعة Vidange'),
        actions: [
          IconButton(
            tooltip: 'تحديث بيانات الصيانة',
            onPressed: _refreshing ? null : _load,
            icon: _refreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'موعد الصيانة لكل مركبة',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'المركبات المتجاوزة للموعد تظهر أولاً. القيم تُحدّث من الخادم.',
                    style: AppText.body.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    height: 108,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        SummaryTile(value: '${summary['all']}', label: 'كل المركبات', icon: Icons.directions_car_filled_rounded, selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                        const SizedBox(width: AppSpacing.sm),
                        SummaryTile(value: '${summary['overdue']}', label: 'تجاوزت الموعد', statusKey: 'pending', icon: Icons.warning_amber_rounded, selected: _filter == 'overdue', onTap: () => setState(() => _filter = 'overdue')),
                        const SizedBox(width: AppSpacing.sm),
                        SummaryTile(value: '${summary['due_soon']}', label: 'اقترب الموعد', statusKey: 'in_progress', icon: Icons.timelapse_rounded, selected: _filter == 'due_soon', onTap: () => setState(() => _filter = 'due_soon')),
                        const SizedBox(width: AppSpacing.sm),
                        SummaryTile(value: '${summary['on_track']}', label: 'ضمن الموعد', statusKey: 'normal', icon: Icons.check_circle_outline_rounded, selected: _filter == 'on_track', onTap: () => setState(() => _filter = 'on_track')),
                        const SizedBox(width: AppSpacing.sm),
                        SummaryTile(value: '${summary['unknown']}', label: 'بيانات ناقصة', icon: Icons.help_outline_rounded, selected: _filter == 'unknown', onTap: () => setState(() => _filter = 'unknown')),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: _search,
                    search: true,
                    hintText: 'ابحث برمز المركبة',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _StatusFilter(label: 'الكل', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                        _StatusFilter(label: 'تجاوزت الموعد', selected: _filter == 'overdue', color: colors.pending, onTap: () => setState(() => _filter = 'overdue')),
                        _StatusFilter(label: 'اقترب الموعد', selected: _filter == 'due_soon', color: colors.inProgress, onTap: () => setState(() => _filter = 'due_soon')),
                        _StatusFilter(label: 'ضمن الموعد', selected: _filter == 'on_track', color: colors.normal, onTap: () => setState(() => _filter = 'on_track')),
                        _StatusFilter(label: 'بيانات ناقصة', selected: _filter == 'unknown', color: colors.textSecondary, onTap: () => setState(() => _filter = 'unknown')),
                      ],
                    ),
                  ),
                  if (_error != null && _rows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!, style: AppText.caption.copyWith(color: colors.pending)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(child: Text('المركبات', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                      Text('${visible.length} نتيجة', style: AppText.caption.copyWith(color: colors.textSecondary)),
                    ],
                  ),
                ]),
              ),
            ),
            if (visible.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: 'لا توجد مركبات مطابقة',
                  description: 'غيّر البحث أو الفلتر المحدد.',
                  icon: Icons.local_gas_station_outlined,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _VidangeCard(
                        row: visible[index],
                        saving: _savingCode == (visible[index]['vehicle'] ?? '').toString(),
                        onEdit: () => _edit(visible[index]),
                      ),
                    ),
                    childCount: visible.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tint = color ?? colors.primary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: colors.tint(tint),
        side: BorderSide(color: selected ? tint.withValues(alpha: .5) : colors.border),
        labelStyle: TextStyle(
          color: selected ? tint : colors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _VidangeCard extends StatelessWidget {
  const _VidangeCard({required this.row, required this.saving, required this.onEdit});

  final Map<String, dynamic> row;
  final bool saving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final status = vidangeStatusKey(row);
    final last = _km(row['last_vidange_km']);
    final latest = _km(row['latest_km']);
    final next = last == null || last <= 0 ? null : last + 10000;
    final remaining = _km(row['remaining_km']) ?? (next != null && latest != null ? next - latest : null);
    final color = switch (status) {
      'overdue' => colors.pending,
      'due_soon' => colors.inProgress,
      'on_track' => colors.normal,
      _ => colors.textSecondary,
    };
    final progress = next != null && last != null && latest != null && next > last
        ? ((latest - last) / (next - last)).clamp(0.0, 1.0).toDouble()
        : null;
    final chipStatus = switch (status) {
      'overdue' => 'pending',
      'due_soon' => 'in_progress',
      'on_track' => 'normal',
      _ => 'unknown',
    };
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: colors.tint(color), borderRadius: BorderRadius.circular(15)),
                child: Icon(Icons.directions_car_filled_rounded, color: color, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        (row['vehicle'] ?? '—').toString(),
                        style: AppText.section.copyWith(color: colors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    StatusChip(status: chipStatus, label: vidangeStatusLabel(status)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: _Metric(label: 'آخر Vidange', value: last != null && last > 0 ? last : null)),
              Expanded(child: _Metric(label: 'آخر قراءة', value: latest)),
              Expanded(child: _Metric(label: 'الموعد القادم', value: next)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: colors.tint(color), borderRadius: BorderRadius.circular(AppSpacing.controlRadius)),
            child: Row(
              children: [
                Icon(Icons.speed_rounded, color: color, size: 19),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    remaining == null
                        ? 'المتبقي غير متوفر لغياب بيانات كافية'
                        : remaining < 0
                            ? 'تجاوز الموعد بمقدار'
                            : 'المتبقي حتى موعد Vidange',
                    style: AppText.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
                if (remaining != null)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${remaining.abs()} KM',
                      style: AppText.numeric.copyWith(color: color, fontSize: 15),
                    ),
                  ),
              ],
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: Text('استهلاك دورة الصيانة', style: AppText.caption.copyWith(color: colors.textSecondary))),
                Text('${(progress * 100).round()}%', style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: progress, minHeight: 7, color: color, backgroundColor: colors.surfaceAlt),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: saving ? 'جارٍ الحفظ…' : 'تعديل / تأكيد قيمة Vidange',
            icon: Icons.edit_road_rounded,
            loading: saving,
            onPressed: saving ? null : onEdit,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: colors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          if (value == null)
            Text('—', style: AppText.section.copyWith(color: colors.textSecondary))
          else
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('$value KM', style: AppText.numeric.copyWith(fontSize: 14, color: colors.textPrimary)),
            ),
        ],
      ),
    );
  }
}
