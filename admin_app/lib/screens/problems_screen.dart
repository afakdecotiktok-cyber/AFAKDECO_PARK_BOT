import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../services/api.dart';
import '../services/app_data_events.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../widgets/app_widgets.dart';

const problemTypeFilters = <String>[
  'all',
  'reclamation',
  'accident',
  'vidange',
];

const problemStatusFilters = <String>[
  'all',
  'pending',
  'in_progress',
  'fixed',
];

String problemStatusKey(Map<String, dynamic> problem) {
  if (problem['problem_type'] == 'accident') return 'accident';
  if (problem['problem_type'] == 'vidange' || problem['media_type'] == 'نظام') {
    return 'vidange';
  }
  if (problem['ruglee'] == 'تم الإصلاح') return 'fixed';
  if (problem['status'] == AppStrings.inProgress) return 'in_progress';
  return 'pending';
}

String problemTypeLabel(Map<String, dynamic> problem) {
  if (problem['problem_type'] == 'accident') return AppStrings.accident;
  if (problem['problem_type'] == 'vidange' || problem['media_type'] == 'نظام') {
    return AppStrings.vidange;
  }
  return 'شكوى';
}

DateTime? _problemDate(Map<String, dynamic> problem) {
  return DateTime.tryParse((problem['date'] ?? '').toString().trim());
}

List<Map<String, dynamic>> sortProblemsNewestFirst(List<dynamic> input) {
  final rows = <({Map<String, dynamic> item, DateTime? date, int index})>[];
  for (var index = 0; index < input.length; index++) {
    final raw = input[index];
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    rows.add((item: item, date: _problemDate(item), index: index));
  }
  rows.sort((a, b) {
    if (a.date == null && b.date != null) return 1;
    if (a.date != null && b.date == null) return -1;
    if (a.date != null && b.date != null) {
      final byDate = b.date!.compareTo(a.date!);
      if (byDate != 0) return byDate;
    }
    return a.index.compareTo(b.index);
  });
  return rows.map((row) => row.item).toList();
}

List<Map<String, dynamic>> filterProblems(
  List<dynamic> input, {
  String type = 'all',
  String status = 'all',
  String? date,
  String query = '',
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final normalizedDate = date?.trim();
  final rows = sortProblemsNewestFirst(input);
  return rows.where((problem) {
    final problemType = (problem['problem_type'] ?? 'reclamation').toString();
    final systemVidange = problem['media_type'] == 'نظام';
    final matchesType = switch (type) {
      'reclamation' =>
        problemType != 'accident' && problemType != 'vidange' && !systemVidange,
      'accident' => problemType == 'accident',
      'vidange' => problemType == 'vidange' || systemVidange,
      _ => true,
    };
    if (!matchesType) return false;
    if (status != 'all' && problemStatusKey(problem) != status) return false;
    if (normalizedDate != null &&
        normalizedDate.isNotEmpty &&
        !(problem['date'] ?? '').toString().startsWith(normalizedDate)) {
      return false;
    }
    if (normalizedQuery.isNotEmpty) {
      final searchable = [
        problem['id'],
        problem['vehicle'],
        problem['driver_name'],
        problem['problem_text'],
        problem['comments'],
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      if (!searchable.contains(normalizedQuery)) return false;
    }
    return true;
  }).toList();
}

Map<String, int> problemSummary(List<dynamic> input) {
  var pending = 0;
  var inProgress = 0;
  var accidents = 0;
  var fixed = 0;
  var vidange = 0;
  for (final raw in input) {
    if (raw is! Map) continue;
    final problem = Map<String, dynamic>.from(raw);
    switch (problemStatusKey(problem)) {
      case 'pending':
        pending++;
      case 'in_progress':
        inProgress++;
      case 'accident':
        accidents++;
      case 'fixed':
        fixed++;
      case 'vidange':
        vidange++;
    }
  }
  return {
    'all': input.length,
    'pending': pending,
    'in_progress': inProgress,
    'accident': accidents,
    'fixed': fixed,
    'vidange': vidange,
  };
}

class ProblemsScreen extends StatefulWidget {
  const ProblemsScreen({super.key});

  @override
  State<ProblemsScreen> createState() => _ProblemsScreenState();
}

class _ProblemsScreenState extends State<ProblemsScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _items = [];
  String _type = 'all';
  String _status = 'all';
  String? _date;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    AppDataEvents.revision.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    AppDataEvents.revision.removeListener(_onDataChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final hadData = _items.isNotEmpty;
    setState(() {
      _loading = !hadData;
      _refreshing = hadData;
      _error = null;
    });
    try {
      // Request the full list once; filter locally so summary counts and
      // combinations of type/date/status stay consistent across the screen.
      final fresh = await Api.instance.problems(type: 'all');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = fresh;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = friendlyError(error));
      if (hadData) AppSnackbar.error(context, friendlyError(error));
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _date == null
          ? DateTime.now()
          : DateTime.tryParse(_date!) ?? DateTime.now(),
      helpText: 'تصفية السجلات حسب اليوم',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (selected == null || !mounted) return;
    setState(() => _date = DateFormat('yyyy-MM-dd').format(selected));
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _type = 'all';
      _status = 'all';
      _date = null;
    });
  }

  Future<void> _openDetails(Map<String, dynamic> problem) async {
    final result = await AppBottomSheet.show<String>(
      context,
      builder: (_) => _ProblemDetailsSheet(problem: problem),
    );
    if (!mounted || result == null || result.isEmpty) return;
    AppSnackbar.success(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final summary = problemSummary(_items);
    final visible = filterProblems(
      _items,
      type: _type,
      status: _status,
      date: _date,
      query: _searchController.text,
    );
    final activeFilters = _type != 'all' ||
        _status != 'all' ||
        _date != null ||
        _searchController.text.trim().isNotEmpty;

    if (_loading && _items.isEmpty) {
      return const LoadingSkeletonList(count: 5, itemHeight: 108);
    }
    if (_error != null && _items.isEmpty) {
      return ErrorState(message: _error!, onRetry: _load);
    }

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الشكاوى والحوادث',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'متابعة الحالة والإصلاح والمرفقات من مكان واحد.',
                            style: AppText.body.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'تحديث السجلات',
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
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      SummaryTile(
                        value: '${summary['all']}',
                        label: 'كل السجلات',
                        icon: Icons.inventory_2_outlined,
                        selected: _status == 'all',
                        onTap: () => setState(() => _status = 'all'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${summary['pending']}',
                        label: AppStrings.waiting,
                        statusKey: 'pending',
                        icon: Icons.hourglass_top_rounded,
                        selected: _status == 'pending',
                        onTap: () => setState(() => _status = 'pending'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${summary['in_progress']}',
                        label: AppStrings.inProgress,
                        statusKey: 'in_progress',
                        icon: Icons.build_circle_outlined,
                        selected: _status == 'in_progress',
                        onTap: () => setState(() => _status = 'in_progress'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${summary['accident']}',
                        label: AppStrings.accident,
                        statusKey: 'accident',
                        icon: Icons.warning_amber_rounded,
                        selected: _type == 'accident',
                        onTap: () => setState(() => _type = 'accident'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SummaryTile(
                        value: '${summary['fixed']}',
                        label: AppStrings.fixed,
                        statusKey: 'fixed',
                        icon: Icons.check_circle_outline_rounded,
                        selected: _status == 'fixed',
                        onTap: () => setState(() => _status = 'fixed'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _searchController,
                  search: true,
                  hintText: 'ابحث برقم المركبة أو السائق أو الوصف',
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {},
                  textInputAction: TextInputAction.search,
                ),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'الكل',
                        selected: _type == 'all',
                        onTap: () => setState(() => _type = 'all'),
                      ),
                      _FilterChip(
                        label: 'الشكاوى',
                        selected: _type == 'reclamation',
                        onTap: () => setState(() => _type = 'reclamation'),
                      ),
                      _FilterChip(
                        label: AppStrings.accident,
                        selected: _type == 'accident',
                        onTap: () => setState(() => _type = 'accident'),
                        color: colors.accident,
                      ),
                      _FilterChip(
                        label: AppStrings.vidange,
                        selected: _type == 'vidange',
                        onTap: () => setState(() => _type = 'vidange'),
                        color: colors.vidange,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _date == null ? 'كل التواريخ' : 'التاريخ: $_date',
                        style: AppText.caption.copyWith(color: colors.textSecondary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: const Text('اختيار تاريخ'),
                    ),
                    if (_date != null)
                      IconButton(
                        tooltip: 'مسح التاريخ',
                        onPressed: () => setState(() => _date = null),
                        icon: const Icon(Icons.filter_alt_off_rounded),
                      ),
                    if (activeFilters)
                      IconButton(
                        tooltip: 'مسح جميع الفلاتر',
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear_all_rounded),
                      ),
                  ],
                ),
                if (_refreshing) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_error != null && _items.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
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
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _type == 'all' ? 'السجلات' : _typeLabel(_type),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Text(
                      '${visible.length} نتيجة',
                      style: AppText.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ]),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: _items.isEmpty ? 'لا توجد سجلات حتى الآن' : 'لا توجد نتائج مطابقة',
                description: _items.isEmpty
                    ? 'ستظهر الشكاوى والحوادث الجديدة هنا.'
                    : 'غيّر البحث أو الفلاتر أو امسحها لعرض المزيد من السجلات.',
                icon: _items.isEmpty ? Icons.assignment_outlined : Icons.search_off_rounded,
                actionLabel: activeFilters ? 'مسح الفلاتر' : null,
                onAction: activeFilters ? _clearFilters : null,
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
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ProblemCard(
                      problem: visible[index],
                      onTap: () => _openDetails(visible[index]),
                    ),
                  ),
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _typeLabel(String type) => switch (type) {
      'reclamation' => 'الشكاوى',
      'accident' => AppStrings.accident,
      'vidange' => AppStrings.vidange,
      _ => 'السجلات',
    };

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
        selectedColor: colors.tint(tint),
        side: BorderSide(
          color: selected ? tint.withValues(alpha: 0.5) : colors.border,
        ),
        labelStyle: TextStyle(
          color: selected ? tint : colors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        showCheckmark: false,
      ),
    );
  }
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.problem, required this.onTap});

  final Map<String, dynamic> problem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final status = problemStatusKey(problem);
    final statusColor = colors.statusColor(status);
    final code = (problem['vehicle'] ?? '—').toString();
    final driver = (problem['driver_name'] ?? 'غير معروف').toString();
    final description = (problem['problem_text'] ?? 'سجل بدون وصف').toString();
    final media = List<dynamic>.from(problem['media'] ?? const []);
    final id = problem['id']?.toString() ?? '—';

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.tint(statusColor),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  status == 'accident'
                      ? Icons.warning_rounded
                      : status == 'vidange'
                          ? Icons.handyman_rounded
                          : Icons.assignment_outlined,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(
                              fontSize: 15,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '#$id',
                          style: AppText.caption.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      driver,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                status: status,
                label: status == 'accident'
                    ? AppStrings.accident
                    : status == 'vidange'
                        ? AppStrings.vidange
                        : status == 'fixed'
                            ? AppStrings.fixed
                            : status == 'in_progress'
                                ? AppStrings.inProgress
                                : AppStrings.waiting,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppText.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 15, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  (problem['date'] ?? 'تاريخ غير متاح').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: colors.textSecondary),
                ),
              ),
              if (media.isNotEmpty) ...[
                Icon(Icons.attach_file_rounded, size: 16, color: colors.textSecondary),
                const SizedBox(width: 3),
                Text(
                  '${media.length}',
                  style: AppText.caption.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProblemDetailsSheet extends StatefulWidget {
  const _ProblemDetailsSheet({required this.problem});

  final Map<String, dynamic> problem;

  @override
  State<_ProblemDetailsSheet> createState() => _ProblemDetailsSheetState();
}

class _ProblemDetailsSheetState extends State<_ProblemDetailsSheet> {
  late final TextEditingController _commentController;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(
      text: (widget.problem['comments'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _perform(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(successMessage);
    } catch (error) {
      if (mounted) AppSnackbar.error(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openTelegram(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      AppSnackbar.error(context, 'رابط Telegram غير صالح.');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) AppSnackbar.error(context, 'تعذر فتح رابط Telegram.');
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'تعذر فتح رابط Telegram.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = widget.problem;
    final colors = AppColors.of(context);
    final id = int.tryParse(problem['id']?.toString() ?? '');
    final status = problemStatusKey(problem);
    final type = problemTypeLabel(problem);
    final description = (problem['problem_text'] ?? 'لا يوجد وصف').toString();
    final media = List<dynamic>.from(problem['media'] ?? const []);
    final isFixed = status == 'fixed';
    final isAccident = status == 'accident';
    final isVidange = status == 'vidange';
    final currentStatus = problem['status'] == AppStrings.inProgress
        ? AppStrings.inProgress
        : AppStrings.waiting;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAccident ? 'تفاصيل الحادث #${id ?? '—'}' : 'تفاصيل السجل #${id ?? '—'}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(
                    status: status,
                    label: status == 'accident'
                        ? AppStrings.accident
                        : status == 'vidange'
                            ? AppStrings.vidange
                            : status == 'fixed'
                                ? AppStrings.fixed
                                : status == 'in_progress'
                                    ? AppStrings.inProgress
                                    : AppStrings.waiting,
                  ),
                  StatusChip(status: type, label: type),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    _DetailLine(label: 'المركبة', value: problem['vehicle']),
                    _DetailLine(label: 'السائق', value: problem['driver_name']),
                    _DetailLine(label: 'التاريخ', value: problem['date']),
                    _DetailLine(label: 'المعرّف', value: id),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'الوصف',
                        style: AppText.label.copyWith(color: colors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(description, style: AppText.body),
                    ),
                    if ((problem['comments'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'التعليق الحالي',
                          style: AppText.label.copyWith(color: colors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(problem['comments'].toString()),
                      ),
                    ],
                  ],
                ),
              ),
              if (media.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'المرفقات'),
                const SizedBox(height: AppSpacing.sm),
                ...media.map((raw) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  final mediaId = int.tryParse(item['id']?.toString() ?? '');
                  final url = (item['telegram_url'] ?? '').toString();
                  final available = item['available_in_app'] == true;
                  final isImage = item['media_type'] == 'صورة';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        children: [
                          if (available && isImage && id != null && mediaId != null)
                            FutureBuilder<Map<String, String>>(
                              future: Api.instance.mediaHeaders(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: colors.surfaceAlt,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    Api.instance.mediaUrl(id, mediaId),
                                    headers: snapshot.data,
                                    width: 54,
                                    height: 54,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 54,
                                      height: 54,
                                      color: colors.surfaceAlt,
                                      child: Icon(Icons.broken_image_outlined, color: colors.textSecondary),
                                    ),
                                  ),
                                );
                              },
                            )
                          else
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: colors.surfaceAlt,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                item['media_type'] == 'فيديو'
                                    ? Icons.videocam_outlined
                                    : Icons.photo_outlined,
                                color: colors.textSecondary,
                              ),
                            ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (item['media_type'] ?? 'وسائط Telegram').toString(),
                                  style: AppText.label,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  available
                                      ? 'معاينة مؤقتة داخل التطبيق'
                                      : 'افتح الرسالة الأصلية في Telegram',
                                  style: AppText.caption.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'فتح في Telegram',
                            onPressed: _working || url.isEmpty ? null : () => _openTelegram(url),
                            icon: const Icon(Icons.open_in_new_rounded),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _commentController,
                labelText: 'تعليق الإصلاح',
                hintText: 'أضف ملاحظة أو تحديثاً للإصلاح',
                maxLines: 3,
                enabled: !_working,
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: 'حفظ التعليق',
                icon: Icons.comment_outlined,
                loading: _working,
                onPressed: id == null
                    ? null
                    : () {
                        if (_commentController.text.trim().isEmpty) {
                          AppSnackbar.info(context, 'اكتب تعليقاً أولاً.');
                          return;
                        }
                        _perform(
                          () => Api.instance.commentProblem(
                            id,
                            _commentController.text.trim(),
                          ),
                          'تم حفظ التعليق.',
                        );
                      },
              ),
              if (!isAccident && !isVidange && id != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'تحويل هذا السجل إلى حادث',
                  icon: Icons.warning_amber_rounded,
                  loading: _working,
                  onPressed: () => _perform(
                    () => Api.instance.convertAccident(id),
                    'تم تحويل السجل إلى حادث.',
                  ),
                ),
              ],
              if (!isAccident && !isVidange && !isFixed && id != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: currentStatus == AppStrings.inProgress
                      ? 'إعادة إلى قيد الانتظار'
                      : 'نقل إلى قيد التصليح',
                  icon: currentStatus == AppStrings.inProgress
                      ? Icons.undo_rounded
                      : Icons.build_outlined,
                  loading: _working,
                  onPressed: () => _perform(
                    () => Api.instance.setProblemStatus(
                      id,
                      currentStatus == AppStrings.inProgress
                          ? AppStrings.waiting
                          : AppStrings.inProgress,
                    ),
                    currentStatus == AppStrings.inProgress
                        ? 'تمت إعادة الحالة إلى قيد الانتظار.'
                        : 'تم نقل الشكوى إلى قيد التصليح.',
                  ),
                ),
              ],
              if (!isAccident &&
                  !isVidange &&
                  !isFixed &&
                  currentStatus == AppStrings.inProgress &&
                  id != null) ...[
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: 'تسجيل الإصلاح',
                  icon: Icons.check_circle_outline_rounded,
                  loading: _working,
                  onPressed: () => _perform(
                    () => Api.instance.fixProblem(id),
                    'تم تسجيل الإصلاح.',
                  ),
                ),
              ],
              if (isFixed) ...[
                const SizedBox(height: AppSpacing.md),
                StatusChip(status: 'fixed', label: AppStrings.fixed),
              ],
              const SizedBox(height: AppSpacing.lg),
              DestructiveButton(
                label: 'حذف السجل',
                loading: _working,
                onPressed: id == null
                    ? null
                    : () async {
                        final accepted = await ConfirmDialog.show(
                          context,
                          title: 'حذف السجل؟',
                          message: 'سيتم حذف هذا السجل من قاعدة البيانات. لا يمكن التراجع عن هذا الإجراء.',
                          confirmLabel: 'حذف',
                          destructive: true,
                        );
                        if (accepted != true || !mounted) return;
                        await _perform(
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
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: AppText.caption.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(child: Text((value ?? '—').toString())),
        ],
      ),
    );
  }
}
