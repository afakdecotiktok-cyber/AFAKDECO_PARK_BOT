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
                const ListTile(leading: Icon(Icons.speed), title: Text('Vidange والكيلومترات'), subtitle: Text('افتح سجل المركبة لتعديل قيمة Vidange ومراجعة جميع القراءات.')),
                const ListTile(leading: Icon(Icons.archive_outlined), title: Text('الأرشفة'), subtitle: Text('بعد 30 يوماً تُفتح الوسائط القديمة من رسالة Telegram الأصلية.')),
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
