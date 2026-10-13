import 'package:flutter/material.dart';
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
          subtitle: Text('${item['date'] ?? ''} • ${item['status'] ?? ''}'),
          isThreeLine: false,
        );
      },
    );
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
