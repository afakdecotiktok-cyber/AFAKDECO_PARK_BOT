import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../services/api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../widgets/app_widgets.dart';
import '../widgets/status_icons.dart';

DateTime? _readingDate(Map<String, dynamic> reading) {
  final raw = reading['date'];
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString().trim());
}

List<Map<String, dynamic>> sortReadingsNewestFirst(List<dynamic> readings) {
  final indexed = <({Map<String, dynamic> item, DateTime? date, int index})>[];
  for (var index = 0; index < readings.length; index++) {
    final raw = readings[index];
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    indexed.add((item: item, date: _readingDate(item), index: index));
  }
  indexed.sort((a, b) {
    if (a.date == null && b.date != null) return 1;
    if (a.date != null && b.date == null) return -1;
    if (a.date != null && b.date != null) {
      final byDate = b.date!.compareTo(a.date!);
      if (byDate != 0) return byDate;
    }
    return a.index.compareTo(b.index);
  });
  return indexed.map((entry) => entry.item).toList();
}

Map<String, dynamic>? selectLatestReading(List<dynamic> readings) {
  final sorted = sortReadingsNewestFirst(readings);
  return sorted.isEmpty ? null : sorted.first;
}

int? _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

class CombinedHistoryEntry {
  const CombinedHistoryEntry({
    required this.kind,
    required this.data,
    required this.date,
    required this.sourceOrder,
  });

  final String kind;
  final Map<String, dynamic> data;
  final DateTime? date;
  final int sourceOrder;
}

List<CombinedHistoryEntry> buildCombinedHistory(
  List<dynamic> problems,
  List<Map<String, dynamic>> readings,
) {
  final entries = <CombinedHistoryEntry>[];
  var order = 0;

  for (final raw in problems) {
    if (raw is! Map) continue;
    final problem = Map<String, dynamic>.from(raw);
    entries.add(CombinedHistoryEntry(
      kind: 'problem',
      data: problem,
      date: _readingDate(problem),
      sourceOrder: order++,
    ));
  }

  for (final reading in readings) {
    entries.add(CombinedHistoryEntry(
      kind: 'reading',
      data: reading,
      date: _readingDate(reading),
      sourceOrder: order++,
    ));
  }

  entries.sort((a, b) {
    if (a.date == null && b.date != null) return 1;
    if (a.date != null && b.date == null) return -1;
    if (a.date != null && b.date != null) {
      final byDate = b.date!.compareTo(a.date!);
      if (byDate != 0) return byDate;
    }
    return a.sourceOrder.compareTo(b.sourceOrder);
  });
  return entries;
}

class VehicleHistoryScreen extends StatefulWidget {
  final String vehicle;
  final Map<String, dynamic>? vehicleData;

  const VehicleHistoryScreen({
    super.key,
    required this.vehicle,
    this.vehicleData,
  });

  @override
  State<VehicleHistoryScreen> createState() => _VehicleHistoryScreenState();
}

class _VehicleHistoryScreenState extends State<VehicleHistoryScreen> {
  bool _loading = true;
  bool _refreshing = false;
  bool _savingVidange = false;
  String? _error;
  Map<String, dynamic>? _data;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final hadData = _data != null;
    setState(() {
      _loading = !hadData;
      _refreshing = hadData;
      _error = null;
    });
    try {
      final result = await Api.instance.vehicleHistory(widget.vehicle);
      if (!mounted) return;
      setState(() {
        _data = result;
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
    if (_loading && _data == null) {
      return const Scaffold(body: LoadingSkeletonList(count: 4));
    }
    if (_error != null && _data == null) {
      return Scaffold(
        appBar: AppBar(title: Text('سجل المركبة')),
        body: ErrorState(message: _error!, onRetry: _load),
      );
    }

    final data = _data ?? const <String, dynamic>{};
    final problems = List<dynamic>.from(data['problems'] ?? const []);
    // The API's actual key is "readings" (not "km_readings").
    final readings = List<dynamic>.from(data['readings'] ?? const []);
    final sortedReadings = sortReadingsNewestFirst(readings);
    final latest = selectLatestReading(readings);
    final vidange = Map<String, dynamic>.from(data['vidange'] ?? const {});
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المركبة'),
        actions: [
          IconButton(
            tooltip: 'تحديث السجل',
            onPressed: _refreshing ? null : _load,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: _VehicleSummary(
              vehicle: widget.vehicle,
              vehicleData: widget.vehicleData,
              latest: latest,
              readingCount: readings.length,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              children: List.generate(5, (index) {
                const labels = [
                  'الكل',
                  'الشكاوى',
                  'الحوادث',
                  AppStrings.vidange,
                  AppStrings.kilometres,
                ];
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(labels[index]),
                    selected: _tab == index,
                    onSelected: (_) => setState(() => _tab = index),
                  ),
                );
              }),
            ),
          ),
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          if (_error != null && _data != null)
            Container(
              width: double.infinity,
              color: colors.tint(colors.pending),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Text(_error!, style: AppText.caption.copyWith(color: colors.pending)),
            ),
          Expanded(
            child: _buildTab(
              problems: problems,
              readings: sortedReadings,
              vidange: vidange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required List<dynamic> problems,
    required List<Map<String, dynamic>> readings,
    required Map<String, dynamic> vidange,
  }) {
    if (_tab == 4) {
      if (readings.isEmpty) {
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 60),
              EmptyState(
                title: AppStrings.noReadings,
                description: 'ستظهر هنا القراءات المسجلة لهذه المركبة.',
                icon: Icons.speed_rounded,
              ),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          itemCount: readings.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final reading = readings[index];
            final km = _asInt(reading['km']);
            final previous = index + 1 < readings.length ? _asInt(readings[index + 1]['km']) : null;
            final delta = km != null && previous != null ? km - previous : null;
            return AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.speed_rounded,
                      color: AppColors.of(context).primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                km == null ? '— KM' : '$km KM',
                                style: AppText.section.copyWith(fontSize: 16),
                              ),
                            ),
                            if (index == 0) const StatusChip(status: 'normal', label: 'الأحدث', icon: Icons.new_releases_outlined),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            (reading['date'] ?? 'تاريخ غير متاح').toString(),
                            style: AppText.caption.copyWith(color: AppColors.of(context).textSecondary),
                          ),
                        ),
                        if ((reading['driver_name'] ?? '').toString().trim().isNotEmpty)
                          Text(
                            'السائق: ${reading['driver_name']}',
                            style: AppText.caption.copyWith(color: AppColors.of(context).textSecondary),
                          ),
                        if (delta != null)
                          Text(
                            'الفرق عن القراءة السابقة: ${delta >= 0 ? '+' : ''}$delta KM',
                            style: AppText.caption.copyWith(color: AppColors.of(context).textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    if (_tab == 3) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: 'ملخص Vidange',
                    subtitle: 'مؤشرات الصيانة اعتماداً على بيانات الخادم.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _metric('آخر قيمة Vidange', vidange['last_vidange_km']),
                  _metric('القيمة القادمة', vidange['next_vidange_km']),
                  _metric('آخر قراءة كيلومترات', vidange['latest_km']),
                  _metric('المتبقي', vidange['remaining_km']),
                  _vidangeProgress(vidange),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: _savingVidange ? 'جارٍ الحفظ…' : 'تعديل / تأكيد قيمة Vidange',
                    icon: Icons.edit_road_rounded,
                    loading: _savingVidange,
                    onPressed: () => _editVidange(vidange),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'يتطلب تعديل هذه القيمة صلاحية المشرف الأعلى. ستُعرض القيم السابقة والجديدة قبل الحفظ.',
                    style: AppText.caption.copyWith(color: AppColors.of(context).textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_tab == 0) {
      return _buildCombinedTimeline(problems, readings);
    }

    final filtered = _tab == 2
        ? problems.where((p) => p is Map && p['problem_type'] == 'accident').toList()
        : _tab == 1
            ? problems.where((p) => p is Map && p['problem_type'] != 'accident' && p['problem_type'] != 'vidange' && p['media_type'] != 'نظام').toList()
            : problems;

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 56),
            EmptyState(
              title: 'لا توجد سجلات في هذا القسم',
              description: 'يمكنك السحب إلى الأسفل لتحديث السجل.',
              icon: Icons.history_rounded,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = Map<String, dynamic>.from(filtered[index] as Map);
          final accident = item['problem_type'] == 'accident';
          final fixed = item['ruglee'] == 'تم الإصلاح';
          final status = accident
              ? AppStrings.accident
              : fixed
                  ? AppStrings.fixed
                  : (item['status'] ?? AppStrings.waiting).toString();
          final colors = AppColors.of(context);
          return AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            onTap: () => _showProblemActions(item),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.tint(colors.statusColor(accident ? 'accident' : status)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    accident ? Icons.warning_rounded : Icons.assignment_outlined,
                    color: colors.statusColor(accident ? 'accident' : status),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['problem_text'] ?? 'سجل بدون وصف').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        (item['date'] ?? '').toString(),
                        style: AppText.caption.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      StatusChip(status: status),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _buildCombinedTimeline(
    List<dynamic> problems,
    List<Map<String, dynamic>> readings,
  ) {
    final entries = buildCombinedHistory(problems, readings);
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 56),
            EmptyState(
              title: 'لا يوجد سجل لهذه المركبة',
              description: 'ستظهر هنا الشكاوى والحوادث وقراءات الكيلومترات.',
              icon: Icons.history_rounded,
            ),
          ],
        ),
      );
    }

    final colors = AppColors.of(context);
    final children = <Widget>[];
    String? previousGroup;

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final rawDate = (entry.data['date'] ?? '').toString().trim();
      final group = rawDate.length >= 10
          ? rawDate.substring(0, 10)
          : 'تاريخ غير متاح';

      if (group != previousGroup) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              2,
              AppSpacing.md,
              2,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  group,
                  style: AppText.label.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        );
        previousGroup = group;
      }

      final isReading = entry.kind == 'reading';
      final data = entry.data;
      final accident = !isReading && data['problem_type'] == 'accident';
      final systemVidange = !isReading &&
          (data['media_type'] == 'نظام' || data['problem_type'] == 'vidange');
      final fixed = !isReading && data['ruglee'] == 'تم الإصلاح';
      final status = isReading
          ? AppStrings.kilometres
          : accident
              ? AppStrings.accident
              : systemVidange
                  ? AppStrings.vidange
                  : fixed
                      ? AppStrings.fixed
                      : (data['status'] ?? AppStrings.waiting).toString();
      final statusKey = isReading
          ? 'primary'
          : accident
              ? 'accident'
              : systemVidange
                  ? 'vidange'
                  : status;
      final statusColor = statusKey == 'primary'
          ? colors.primary
          : colors.statusColor(statusKey);
      final km = isReading ? _asInt(data['km']) : null;
      final title = isReading
          ? (km == null ? 'قراءة كيلومترات' : 'قراءة عداد • $km KM')
          : (data['problem_text'] ?? 'سجل بدون وصف').toString();

      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 17),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    if (index < entries.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: colors.border,
                          margin: const EdgeInsets.only(top: 4),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  onTap: isReading ? null : () => _showProblemActions(data),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colors.tint(statusColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isReading
                              ? Icons.speed_rounded
                              : accident
                                  ? Icons.warning_rounded
                                  : systemVidange
                                      ? Icons.handyman_rounded
                                      : Icons.assignment_outlined,
                          color: statusColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label.copyWith(
                                fontSize: 14,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                rawDate.isEmpty ? 'تاريخ غير متاح' : rawDate,
                                style: AppText.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            if (isReading &&
                                (data['driver_name'] ?? '').toString().trim().isNotEmpty)
                              Text(
                                'السائق: ${data['driver_name']}',
                                style: AppText.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            const SizedBox(height: AppSpacing.sm),
                            StatusChip(
                              status: isReading ? 'vidange' : status,
                              label: isReading ? AppStrings.kilometres : status,
                              icon: isReading ? Icons.speed_rounded : null,
                            ),
                          ],
                        ),
                      ),
                      if (!isReading) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.chevron_left_rounded,
                          color: colors.textSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: children,
      ),
    );
  }

  Widget _metric(String label, dynamic value) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body.copyWith(color: colors.textSecondary))),
          if (value == null)
            Text('غير متوفر', style: AppText.body.copyWith(color: colors.textSecondary))
          else
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '$value KM',
                style: AppText.numeric.copyWith(fontSize: 15, color: colors.textPrimary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vidangeProgress(Map<String, dynamic> vidange) {
    final last = _asInt(vidange['last_vidange_km']);
    final latest = _asInt(vidange['latest_km']);
    final next = _asInt(vidange['next_vidange_km']);
    if (last == null || latest == null || next == null || next <= last) {
      return const SizedBox.shrink();
    }
    final fraction = ((latest - last) / (next - last)).clamp(0.0, 1.0).toDouble();
    final remaining = _asInt(vidange['remaining_km']);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('استهلاك دورة Vidange', style: AppText.label)),
              Text(
                '${(fraction * 100).round()}%',
                style: AppText.caption.copyWith(
                  color: remaining != null && remaining < 0 ? colors.pending : colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              color: remaining != null && remaining < 0 ? colors.pending : colors.vidange,
              backgroundColor: colors.surfaceAlt,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProblemActions(Map<String, dynamic> item) async {
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    final comment = TextEditingController(text: (item['comments'] ?? '').toString());
    final media = List<dynamic>.from(item['media'] ?? const []);
    var working = false;

    await AppBottomSheet.show<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> perform(
            Future<void> Function() action,
            String successMessage,
          ) async {
            if (working) return;
            setSheetState(() => working = true);
            try {
              await action();
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
              await _load();
              if (mounted) AppSnackbar.success(this.context, successMessage);
            } catch (error) {
              if (mounted) AppSnackbar.error(this.context, friendlyError(error));
            } finally {
              if (sheetContext.mounted) setSheetState(() => working = false);
            }
          }

          final fixed = item['ruglee'] == 'تم الإصلاح';
          final status = (item['status'] ?? AppStrings.waiting).toString();
          final isAccident = item['problem_type'] == 'accident';
          final isVidangeSystem = item['media_type'] == 'نظام' || item['problem_type'] == 'vidange';
          return Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.82,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAccident ? 'تفاصيل الحادث #$id' : 'تفاصيل السجل #$id',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text((item['problem_text'] ?? 'لا يوجد وصف').toString()),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        StatusChip(status: isAccident ? AppStrings.accident : fixed ? AppStrings.fixed : status),
                        if (isVidangeSystem) const StatusChip(status: 'vidange'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (media.isNotEmpty) ...[
                      const SectionHeader(title: 'الوسائط المرفقة'),
                      const SizedBox(height: AppSpacing.sm),
                      ...media.map((raw) {
                        final m = Map<String, dynamic>.from(raw as Map);
                        final mediaId = int.tryParse(m['id']?.toString() ?? '');
                        final url = (m['telegram_url'] ?? '').toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: m['available_in_app'] == true && mediaId != null && m['media_type'] == 'صورة'
                              ? FutureBuilder<Map<String, String>>(
                                  future: Api.instance.mediaHeaders(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const SizedBox(
                                        width: 52,
                                        height: 52,
                                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                      );
                                    }
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        Api.instance.mediaUrl(id, mediaId),
                                        headers: snapshot.data,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                                      ),
                                    );
                                  },
                                )
                              : Icon(m['media_type'] == 'فيديو' ? Icons.videocam_outlined : Icons.photo_outlined),
                          title: Text((m['media_type'] ?? 'وسائط Telegram').toString()),
                          subtitle: Text(
                            m['available_in_app'] == true ? 'متاحة مؤقتاً داخل التطبيق' : 'افتح الرسالة الأصلية في Telegram',
                            style: AppText.caption.copyWith(color: AppColors.of(context).textSecondary),
                          ),
                          trailing: IconButton(
                            tooltip: 'فتح في Telegram',
                            icon: const Icon(Icons.open_in_new_rounded),
                            onPressed: url.isEmpty || working
                                ? null
                                : () async {
                                    final uri = Uri.tryParse(url);
                                    if (uri == null) {
                                      AppSnackbar.error(this.context, 'رابط Telegram غير صالح.');
                                      return;
                                    }
                                    try {
                                      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      if (!opened && mounted) {
                                        AppSnackbar.error(this.context, 'تعذر فتح رابط Telegram.');
                                      }
                                    } catch (_) {
                                      if (mounted) AppSnackbar.error(this.context, 'تعذر فتح رابط Telegram.');
                                    }
                                  },
                          ),
                        );
                      }),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    AppTextField(
                      controller: comment,
                      labelText: 'تعليق الإصلاح',
                      hintText: 'اكتب تعليقاً أو توضيحاً',
                      maxLines: 3,
                      enabled: !working,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(
                      label: 'حفظ التعليق',
                      icon: Icons.comment_outlined,
                      loading: working,
                      onPressed: () async {
                        if (comment.text.trim().isEmpty) {
                          AppSnackbar.info(this.context, 'اكتب تعليقاً أولاً.');
                          return;
                        }
                        await perform(
                          () => Api.instance.commentProblem(id, comment.text.trim()),
                          'تم حفظ التعليق.',
                        );
                      },
                    ),
                    if (!isAccident && !isVidangeSystem) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SecondaryButton(
                        label: 'تحويل هذه الشكوى إلى حادث',
                        icon: Icons.warning_amber_rounded,
                        loading: working,
                        onPressed: () => perform(
                          () => Api.instance.convertAccident(id),
                          'تم تحويل السجل إلى حادث.',
                        ),
                      ),
                    ],
                    if (!fixed && !isVidangeSystem) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SecondaryButton(
                        label: status == AppStrings.inProgress
                            ? 'إعادة إلى قيد الانتظار'
                            : 'نقل إلى قيد التصليح',
                        icon: status == AppStrings.inProgress
                            ? Icons.undo_rounded
                            : Icons.build_outlined,
                        loading: working,
                        onPressed: () => perform(
                          () => Api.instance.setProblemStatus(
                            id,
                            status == AppStrings.inProgress
                                ? AppStrings.waiting
                                : AppStrings.inProgress,
                          ),
                          status == AppStrings.inProgress
                              ? 'تمت إعادة الحالة إلى قيد الانتظار.'
                              : 'تم نقل الشكوى إلى قيد التصليح.',
                        ),
                      ),
                    ],
                    if (!fixed && status == AppStrings.inProgress && !isVidangeSystem) ...[
                      const SizedBox(height: AppSpacing.sm),
                      PrimaryButton(
                        label: 'تسجيل الإصلاح',
                        icon: Icons.check_circle_outline_rounded,
                        loading: working,
                        onPressed: () => perform(
                          () => Api.instance.fixProblem(id),
                          'تم تسجيل الإصلاح.',
                        ),
                      ),
                    ],
                    if (fixed) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const StatusChip(status: 'fixed', label: 'تم الإصلاح'),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    DestructiveButton(
                      label: 'حذف السجل',
                      loading: working,
                      onPressed: () async {
                        final accepted = await ConfirmDialog.show(
                          sheetContext,
                          title: 'حذف السجل؟',
                          message: 'سيتم حذف هذا السجل من قاعدة البيانات. لا يمكن التراجع عن هذا الإجراء.',
                          confirmLabel: 'حذف',
                          destructive: true,
                        );
                        if (accepted != true || !sheetContext.mounted) return;
                        await perform(
                          () => Api.instance.deleteProblem(id),
                          'تم حذف السجل.',
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    comment.dispose();
  }

  Future<void> _editVidange(Map<String, dynamic> current) async {
    final oldValue = _asInt(current['last_vidange_km']);
    final lastReading = _asInt(current['latest_km']);
    final controller = TextEditingController(text: oldValue?.toString() ?? '');
    try {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعديل قيمة Vidange'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المركبة: ${widget.vehicle}'),
                const SizedBox(height: AppSpacing.sm),
                Text('القيمة الحالية: ${oldValue ?? 'غير مسجلة'} KM'),
                Text('آخر قراءة: ${lastReading ?? 'غير متوفرة'} KM'),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: controller,
                  labelText: 'القيمة الجديدة (KM)',
                  digitsOnly: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('متابعة')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
      final km = int.tryParse(controller.text.trim());
      if (km == null || km < 0) {
        AppSnackbar.error(context, 'أدخل قيمة كيلومترات صحيحة لا تقل عن صفر.');
        return;
      }
      final accepted = await ConfirmDialog.show(
        context,
        title: 'تأكيد حفظ Vidange',
        message: 'القيمة السابقة: ${oldValue ?? 'غير مسجلة'} KM\nالقيمة الجديدة: $km KM\nالقيمة القادمة: ${km + 10000} KM',
        confirmLabel: 'تأكيد وحفظ',
      );
      if (accepted != true || !mounted) return;

      setState(() => _savingVidange = true);
      try {
        final result = await Api.instance.setVidange(widget.vehicle, km);
        if (!mounted) return;
        AppSnackbar.success(
          context,
          'تم الحفظ. القيمة القادمة: ${result['next_vidange_km'] ?? km + 10000} KM',
        );
        await _load();
        if (mounted) setState(() => _tab = 3);
      } catch (error) {
        if (mounted) AppSnackbar.error(context, friendlyError(error));
      } finally {
        if (mounted) setState(() => _savingVidange = false);
      }
    } finally {
      controller.dispose();
    }
  }
}

class _VehicleSummary extends StatelessWidget {
  const _VehicleSummary({
    required this.vehicle,
    required this.vehicleData,
    required this.latest,
    required this.readingCount,
  });

  final String vehicle;
  final Map<String, dynamic>? vehicleData;
  final Map<String, dynamic>? latest;
  final int readingCount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final drivers = List<dynamic>.from(vehicleData?['drivers'] ?? const []);
    final names = drivers.whereType<Map>()
        .map((driver) => (driver['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .join(' • ');
    final statusIcons = List<dynamic>.from(vehicleData?['status_icons'] ?? const []);
    final km = latest == null ? null : _asInt(latest!['km']);
    final date = latest?['date']?.toString().trim();
    final driverName = latest?['driver_name']?.toString().trim();

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.tint(colors.primary),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.directions_car_filled_rounded, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        vehicle,
                        style: AppText.section,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      names.isEmpty ? 'السائق الحالي غير متوفر' : names,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (statusIcons.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 70),
                  child: StatusIcons(icons: statusIcons),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.speed_rounded, size: 19, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('آخر كيلومترات مسجلة', style: AppText.label.copyWith(color: colors.textSecondary)),
                    const SizedBox(height: AppSpacing.xs),
                    if (readingCount == 0)
                      Text(AppStrings.noReadings, style: AppText.body.copyWith(color: colors.textSecondary))
                    else if (km == null)
                      Text('تعذر قراءة قيمة الكيلومترات.', style: AppText.body.copyWith(color: colors.textSecondary))
                    else
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '$km KM',
                          style: AppText.title.copyWith(color: colors.textPrimary),
                        ),
                      ),
                    if (readingCount > 0 && date != null && date.isNotEmpty)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          date,
                          style: AppText.caption.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    if (driverName != null && driverName.isNotEmpty)
                      Text(
                        'أدخلها السائق: $driverName',
                        style: AppText.caption.copyWith(color: colors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
