import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';
import '../widgets/status_icons.dart';

class ProblemsScreen extends StatefulWidget {
  const ProblemsScreen({super.key});
  @override
  State<ProblemsScreen> createState() => _ProblemsScreenState();
}

class _ProblemsScreenState extends State<ProblemsScreen> {
  String filter = 'all';
  String? date;
  final search = TextEditingController();
  bool loading = true;
  String? error;
  List<dynamic> items = [];

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
      items = await Api.instance.problems(
        type: filter,
        date: date,
        search: search.text.trim(),
      );
      error = null;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: date == null ? DateTime.now() : DateTime.tryParse(date!) ?? DateTime.now(),
    );
    if (d != null) {
      setState(() => date = DateFormat('yyyy-MM-dd').format(d));
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', 'الكل'),
      ('reclamation', 'الشكاوى'),
      ('accident', 'الحوادث'),
      ('vidange', 'Vidange'),
    ];
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(10),
          child: Row(
            children: filters.map((f) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: filter == f.$1,
                onSelected: (_) {
                  setState(() => filter = f.$1);
                  load();
                },
              ),
            )).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onSubmitted: (_) => load(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'بحث بالمركبة أو السائق أو الوصف',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'تصفية حسب التاريخ',
                onPressed: pickDate,
                icon: const Icon(Icons.calendar_month),
              ),
              if (date != null)
                IconButton(
                  tooltip: 'مسح التاريخ',
                  onPressed: () { setState(() => date = null); load(); },
                  icon: const Icon(Icons.filter_alt_off),
                ),
            ],
          ),
        ),
        if (date != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Chip(label: Text('التاريخ: $date')),
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(error!), const SizedBox(height: 8), FilledButton(onPressed: load, child: const Text('إعادة المحاولة'))],
                    ))
                  : items.isEmpty
                      ? const Center(child: Text('لا توجد نتائج مطابقة'))
                      : RefreshIndicator(
                          onRefresh: load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 5),
                            itemBuilder: (_, i) {
                              final p = Map<String, dynamic>.from(items[i]);
                              final accident = p['problem_type'] == 'accident';
                              final status = p['status'] == 'قيد التصليح' ? 'in_progress' : 'pending';
                              final media = List<dynamic>.from(p['media'] ?? []);
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: accident ? const Color(0xFF7B3FF2).withValues(alpha: .12) : null,
                                    child: Icon(
                                      accident ? Icons.warning_rounded : Icons.report_problem_outlined,
                                      color: accident ? const Color(0xFF7B3FF2) : null,
                                    ),
                                  ),
                                  title: Text('${p['vehicle'] ?? '-'} • ${p['driver_name'] ?? '-'}'),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      '${p['problem_text'] ?? ''}\n${p['date'] ?? ''}${media.isEmpty ? '' : '\n📎 ${media.length} ملف'}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  isThreeLine: true,
                                  trailing: StatusIcons(icons: accident ? ['accident'] : [status]),
                                  onTap: () => showDetails(p),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Future<void> showDetails(Map<String, dynamic> p) async {
    final id = int.tryParse(p['id'].toString());
    if (id == null) return;
    final commentController = TextEditingController(text: (p['comments'] ?? '').toString());
    final media = List<dynamic>.from(p['media'] ?? []);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.values[1],
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 8,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('تفاصيل السجل #$id', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _detail('المركبة', p['vehicle']),
                  _detail('السائق', p['driver_name']),
                  _detail('التاريخ', p['date']),
                  _detail('الحالة', p['status']),
                  _detail('النوع', p['problem_type'] == 'accident' ? 'حادث' : p['problem_type'] == 'vidange' ? 'Vidange' : 'شكوى'),
                  const SizedBox(height: 8),
                  const Text('الوصف', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text((p['problem_text'] ?? 'لا يوجد وصف').toString()),
                  if ((p['comments'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('التعليقات الحالية', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(p['comments'].toString()),
                  ],
                  if (media.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('الوسائط', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...media.map((raw) {
                      final m = Map<String, dynamic>.from(raw);
                      final available = m['available_in_app'] == true;
                      final url = (m['telegram_url'] ?? '').toString();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(m['media_type'] == 'فيديو' ? Icons.videocam : Icons.photo, color: available ? null : Colors.grey),
                        title: Text(available ? 'وسائط محفوظة في Telegram' : 'مؤرشفة في Telegram'),
                        subtitle: Text(available ? 'المصدر الأصلي محفوظ في Telegram' : 'انتهت مدة العرض داخل التطبيق (30 يوماً)'),
                        trailing: url.isNotEmpty ? IconButton(
                          tooltip: 'فتح في Telegram',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _openTelegram(url),
                        ) : null,
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'إضافة / تحديث تعليق الإصلاح', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      final comment = commentController.text.trim();
                      if (comment.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب تعليقاً أولاً')));
                        return;
                      }
                      try {
                        await Api.instance.commentProblem(id, comment);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        await load();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعليق')));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ التعليق: $e')));
                      }
                    },
                    icon: const Icon(Icons.comment_outlined),
                    label: const Text('حفظ التعليق'),
                  ),
                  if (p['problem_type'] != 'accident')
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await Api.instance.convertAccident(id);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          await load();
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر التحويل: $e')));
                        }
                      },
                      icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFF7B3FF2)),
                      label: const Text('تحويل هذا السجل إلى حادث'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await Api.instance.fixProblem(id);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        await load();
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تسجيل الإصلاح: $e')));
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('تسجيل الإصلاح'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    commentController.dispose();
  }

  Widget _detail(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey))),
        Expanded(child: Text((value ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    ),
  );

  Future<void> _openTelegram(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !await canLaunchUrl(uri)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح رابط Telegram')));
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
