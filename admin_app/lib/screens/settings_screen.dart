import 'package:flutter/material.dart';
import '../services/api.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  const SettingsScreen({super.key, required this.onLogout});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  Map<String, dynamic>? profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final value = await Api.instance.profile();
      if (mounted) setState(() => profile = value);
    } catch (_) {
      if (mounted) setState(() => profile = null);
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تنفيذ العملية: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _ask(String title, String hint) async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('متابعة')),
        ],
      ),
    );
    c.dispose();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('الإعدادات والإدارة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('تُنفّذ العمليات الإدارية عبر واجهة الخادم الحالية وتخضع لصلاحيات الحساب.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text((profile?['display_name'] ?? '').toString().trim().isEmpty
                  ? 'الملف الشخصي'
                  : profile!['display_name'].toString()),
              subtitle: Text(profile == null
                  ? 'جارٍ تحميل بيانات الحساب...'
                  : 'Telegram ID: \${profile!['user_id'] ?? '—'} • الصلاحية: \${profile!['role'] ?? '—'}'),
              trailing: IconButton(
                tooltip: 'تحديث بيانات الحساب',
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.telegram),
                  title: Text('تكامل Telegram'),
                  subtitle: Text('يبقى البوت والمجموعة المصدر الأساسي للتواصل والوسائط.'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.security),
                  title: Text('الأمان'),
                  subtitle: Text('رمز البوت ومعلومات قاعدة البيانات لا تُخزّن داخل التطبيق.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                const ListTile(leading: Icon(Icons.directions_car), title: Text('إدارة المركبات'), subtitle: Text('إضافة مركبة أو حذفها (للمشرف الأعلى فقط).')),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('إضافة مركبة'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : () async {
                    final code = await _ask('إضافة مركبة', 'رمز المركبة، مثل H01');
                    if (code == null || code.trim().isEmpty || !mounted) return;
                    await _run(() => Api.instance.addVehicle(code), 'تم إرسال طلب إضافة المركبة');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('حذف مركبة'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : () async {
                    final code = await _ask('حذف مركبة', 'رمز المركبة المراد حذفها');
                    if (code == null || code.trim().isEmpty || !mounted) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('تأكيد حذف المركبة'),
                        content: Text('هل تريد حذف المركبة ${code.toUpperCase()}؟ راجع ارتباطاتها قبل المتابعة.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الحذف')),
                        ],
                      ),
                    );
                    if (ok == true) await _run(() => Api.instance.removeVehicle(code), 'تم إرسال طلب حذف المركبة');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                const ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('إدارة المشرفين'), subtitle: Text('إضافة مشرف جديد باستخدام Telegram User ID.')),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: const Text('إضافة مشرف'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : () async {
                    final uid = await _ask('إضافة مشرف', 'Telegram User ID');
                    if (uid == null || uid.isEmpty || !mounted) return;
                    await _run(() => Api.instance.addAdmin(uid), 'تم إرسال طلب إضافة المشرف');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('عرض المشرفين الحاليين'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : _showAdmins,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                const ListTile(leading: Icon(Icons.build_circle_outlined), title: Text('صيانة البيانات'), subtitle: Text('تحديث القيم يتم عبر صفحات السجلات المخصصة.')),
                const ListTile(leading: Icon(Icons.speed), title: Text('Vidange والكيلومترات'), subtitle: Text('عرض القيم المسجلة وتعديل قيمة Vidange للمركبة.')),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('عرض حالة Vidange لكل المركبات'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : _showVidange,
                ),
                ListTile(
                  leading: const Icon(Icons.cached),
                  title: const Text('مسح التخزين المؤقت'),
                  subtitle: const Text('حذف النسخ المحلية المؤقتة وإعادة تحميل البيانات عند الطلب.'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : () => _run(Api.instance.clearApiCache, 'تم مسح التخزين المؤقت'),
                ),
                const ListTile(leading: Icon(Icons.archive_outlined), title: Text('الأرشفة'), subtitle: Text('تُعرض مراجع الوسائط القديمة لفتحها من رسالة Telegram الأصلية.')),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: busy ? null : widget.onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
          ),
          if (busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Future<void> _showVidange() async {
    setState(() => busy = true);
    try {
      final rows = await Api.instance.vidange();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('حالة Vidange للمركبات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (rows.isEmpty) const Text('لا توجد بيانات.'),
                ...rows.map((raw) {
                  final v = Map<String, dynamic>.from(raw);
                  final remaining = v['remaining_km'];
                  return ListTile(
                    leading: const Icon(Icons.directions_car_outlined),
                    title: Text((v['vehicle'] ?? '—').toString()),
                    subtitle: Text('آخر Vidange: \${v['last_vidange_km'] ?? 'غير مسجل'} KM • آخر قراءة: \${v['latest_km'] ?? 'غير متوفرة'} KM\nالمتبقي: \${remaining ?? 'غير متوفر'} KM'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'تعديل القيمة',
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final controller = TextEditingController(text: v['last_vidange_km']?.toString() ?? '');
                        final value = await showDialog<String>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: Text('تعديل Vidange • \${v['vehicle']}'),
                            content: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'قيمة آخر Vidange (KM)', border: OutlineInputBorder()),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
                              FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('حفظ')),
                            ],
                          ),
                        );
                        controller.dispose();
                        final km = int.tryParse(value ?? '');
                        if (km == null || km < 0) {
                          if (mounted && value != null) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل قيمة كيلومترات صحيحة')));
                          return;
                        }
                        await _run(() async { await Api.instance.setVidange(v['vehicle'].toString(), km); }, 'تم حفظ قيمة Vidange');
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر جلب بيانات Vidange: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showAdmins() async {
    setState(() => busy = true);
    try {
      final admins = await Api.instance.admins();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('المشرفون الحاليون', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (admins.isEmpty) const Text('لا توجد بيانات مشرفين.'),
                ...admins.map((raw) {
                  final a = Map<String, dynamic>.from(raw);
                  final id = (a['user_id'] ?? a['telegram_user_id'] ?? '').toString();
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.admin_panel_settings)),
                    title: Text((a['display_name'] ?? a['name'] ?? id).toString()),
                    subtitle: Text('ID: $id • ${a['role'] ?? 'admin'}'),
                    trailing: IconButton(
                      tooltip: 'حذف المشرف',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: id.isEmpty ? null : () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('حذف المشرف'),
                            content: Text('هل تريد إزالة المشرف $id؟'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
                              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
                            ],
                          ),
                        );
                        if (ok == true && mounted) {
                          Navigator.pop(ctx);
                          await _run(() => Api.instance.removeAdmin(id), 'تم إرسال طلب إزالة المشرف');
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر جلب المشرفين: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
