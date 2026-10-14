import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';

class VehicleHistoryScreen extends StatefulWidget {
  final String vehicle;
  const VehicleHistoryScreen({super.key, required this.vehicle});

  @override
  State<VehicleHistoryScreen> createState() => _VehicleHistoryScreenState();
}

class _VehicleHistoryScreenState extends State<VehicleHistoryScreen> {
  bool loading = true;
  bool savingVidange = false;
  String? error;
  Map<String, dynamic>? data;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = await Api.instance.vehicleHistory(widget.vehicle);
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.vehicle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!),
              const SizedBox(height: 12),
              FilledButton(onPressed: load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final problems = List<dynamic>.from(data?['problems'] ?? []);
    final readings = List<dynamic>.from(data?['readings'] ?? []);
    final vidange = Map<String, dynamic>.from(data?['vidange'] ?? {});
    const tabs = ['الكل', 'الشكاوى', 'الحوادث', 'Vidange', 'الكيلومترات'];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('سجل المركبة • ${widget.vehicle}'),
          actions: [IconButton(tooltip: 'تحديث', onPressed: load, icon: const Icon(Icons.refresh))],
        ),
        body: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              child: Row(
                children: List.generate(
                  tabs.length,
                  (i) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(tabs[i]),
                      selected: tab == i,
                      onSelected: (_) => setState(() => tab = i),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: _body(problems, readings, vidange)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    List<dynamic> problems,
    List<dynamic> readings,
    Map<String, dynamic> vidange,
  ) {
    if (tab == 4) {
      if (readings.isEmpty) return _empty('لا توجد قراءات كيلومترات مسجلة');
      return ListView.separated(
        itemCount: readings.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final item = Map<String, dynamic>.from(readings[i]);
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.speed)),
            title: Text('${item['km'] ?? '-'} KM'),
            subtitle: Text((item['date'] ?? '').toString()),
          );
        },
      );
    }

    if (tab == 3) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ملخص Vidange', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _metric('آخر قيمة Vidange', vidange['last_vidange_km']),
                  _metric('القيمة القادمة', vidange['next_vidange_km']),
                  _metric('آخر كيلومترات مسجلة', vidange['latest_km']),
                  _metric('المتبقي', vidange['remaining_km'], suffix: ' KM'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: savingVidange ? null : () => _editVidange(vidange),
                      icon: const Icon(Icons.edit_road),
                      label: Text(savingVidange ? 'جارٍ الحفظ...' : 'تعديل / تأكيد قيمة Vidange'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'تعديل هذه القيمة يتطلب صلاحية المشرف الأعلى. سيتم عرض القيمة السابقة والجديدة قبل التأكيد.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final filtered = tab == 2
        ? problems.where((p) => p['problem_type'] == 'accident').toList()
        : tab == 1
            ? problems.where((p) => p['problem_type'] != 'accident' && p['problem_type'] != 'vidange').toList()
            : problems;

    if (filtered.isEmpty) return _empty('لا توجد سجلات في هذا القسم');
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = Map<String, dynamic>.from(filtered[i]);
        final accident = item['problem_type'] == 'accident';
        return ListTile(
          leading: Icon(
            accident ? Icons.warning_rounded : Icons.report_problem_outlined,
            color: accident ? const Color(0xFF7B3FF2) : null,
          ),
          title: Text((item['problem_text'] ?? 'سجل بدون وصف').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item['date'] ?? ''} • ${item['ruglee'] == 'تم الإصلاح' ? 'تم الإصلاح' : item['status'] ?? ''}'),
          isThreeLine: false,
          onTap: () => _showProblemActions(item),
        );
      },
    );
  }

  Future<void> _showProblemActions(Map<String, dynamic> item) async {
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    final comment = TextEditingController(text: (item['comments'] ?? '').toString());
    final media = List<dynamic>.from(item['media'] ?? []);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16, 8, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('الشكوى #$id', style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text((item['problem_text'] ?? 'لا يوجد وصف').toString()),
                  const SizedBox(height: 6),
                  Text('الحالة: ${item['ruglee'] == 'تم الإصلاح' ? 'تم الإصلاح' : item['status'] ?? '—'}'),
                  if (media.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('الوسائط', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...media.map((raw) {
                      final m = Map<String, dynamic>.from(raw);
                      final mediaId = int.tryParse(m['id']?.toString() ?? '');
                      final url = (m['telegram_url'] ?? '').toString();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: m['available_in_app'] == true && mediaId != null && m['media_type'] == 'صورة'
                            ? FutureBuilder<Map<String, String>>(
                                future: Api.instance.mediaHeaders(),
                                builder: (context, snapshot) => snapshot.hasData
                                    ? Image.network(
                                        Api.instance.mediaUrl(id, mediaId),
                                        headers: snapshot.data,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                                      )
                                    : const SizedBox(width: 56, height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                              )
                            : Icon(m['media_type'] == 'فيديو' ? Icons.videocam : Icons.photo),
                        title: Text('الوسائط • ${m['media_type'] ?? 'Telegram'}'),
                        subtitle: Text((m['media_type'] ?? 'وسائط').toString()),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: url.isEmpty ? null : () async {
                            final uri = Uri.tryParse(url);
                            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                          },
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: comment,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'تعليق الإصلاح',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      if (comment.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب تعليقاً أولاً')));
                        return;
                      }
                      try {
                        await Api.instance.commentProblem(id, comment.text.trim());
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
                  if (item['problem_type'] != 'accident')
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await Api.instance.convertAccident(id);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          await load();
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر التحويل إلى حادث: $e')));
                        }
                      },
                      icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFF7B3FF2)),
                      label: const Text('تحويل إلى حادث'),
                    ),
                  if (item['ruglee'] != 'تم الإصلاح')
                    OutlinedButton.icon(
                      onPressed: () async {
                        final nextStatus = item['status'] == 'قيد التصليح' ? 'قيد الانتظار' : 'قيد التصليح';
                        try {
                          await Api.instance.setProblemStatus(id, nextStatus);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          await load();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(nextStatus == 'قيد التصليح' ? 'تم نقل الشكوى إلى قيد المعالجة' : 'تمت إعادة الشكوى إلى قيد الانتظار')),
                          );
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث الحالة: $e')));
                        }
                      },
                      icon: Icon(item['status'] == 'قيد التصليح' ? Icons.undo : Icons.build_outlined),
                      label: Text(item['status'] == 'قيد التصليح' ? 'إعادة إلى En attente' : 'En cours de traitement'),
                    ),
                  if (item['ruglee'] != 'تم الإصلاح' && item['status'] == 'قيد التصليح')
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await Api.instance.fixProblem(id);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          await load();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الإصلاح')));
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تسجيل الإصلاح: $e')));
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Mark as fixed / تم الإصلاح'),
                    ),
                  if (item['ruglee'] == 'تم الإصلاح')
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('تم الإصلاح'),
                    ),
                  if (item['ruglee'] != 'تم الإصلاح')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('حذف الشكوى؟'),
                            content: const Text('سيتم حذف هذا السجل من قاعدة البيانات.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
                              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          await Api.instance.deleteProblem(id);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          await load();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الشكوى')));
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الشكوى: $e')));
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete / حذف'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    comment.dispose();
  }

  Widget _metric(String label, dynamic value, {String suffix = ' KM'}) {
    final shown = value == null ? 'غير متوفر' : '$value$suffix';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(shown, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [const Icon(Icons.history, size: 38, color: Colors.grey), const SizedBox(height: 8), Text(text)],
          ),
        ),
      );

  Future<void> _editVidange(Map<String, dynamic> current) async {
    final old = current['last_vidange_km'];
    final controller = TextEditingController(text: old?.toString() ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل قيمة Vidange'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المركبة: ${widget.vehicle}'),
            Text('القيمة الحالية: ${old ?? 'غير مسجلة'} KM'),
            Text('آخر قراءة مسجلة: ${current['latest_km'] ?? 'غير متوفرة'} KM'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'القيمة الجديدة (KM)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final km = int.tryParse(controller.text.trim());
    if (km == null || km < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل قيمة كيلومترات صحيحة')));
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحفظ'),
        content: Text('القيمة السابقة: ${old ?? 'غير مسجلة'} KM\nالقيمة الجديدة: $km KM\nالقيمة القادمة المقترحة: ${km + 10000} KM'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد وحفظ')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => savingVidange = true);
    try {
      final result = await Api.instance.setVidange(widget.vehicle, km);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الحفظ • التالي: ${result['next_vidange_km'] ?? km + 10000} KM')),
      );
      await load();
      if (mounted) setState(() => tab = 3);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    } finally {
      if (mounted) setState(() => savingVidange = false);
    }
  }
}
