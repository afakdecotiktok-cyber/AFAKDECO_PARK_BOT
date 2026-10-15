import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api.dart';
import '../theme/app_colors.dart';

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

  Future<String?> _ask(String title, String hint, {String initialValue = ''}) async {
    final c = TextEditingController(text: initialValue);
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
    return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('الإعدادات والإدارة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('تُنفّذ العمليات الإدارية عبر واجهة الخادم الحالية وتخضع لصلاحيات الحساب.', style: TextStyle(color: AppColors.of(context).textSecondary)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text((profile?['display_name'] ?? '').toString().trim().isEmpty
                  ? 'الملف الشخصي'
                  : profile!['display_name'].toString()),
              subtitle: Text(profile == null
                  ? 'جارٍ تحميل بيانات الحساب...'
                  : 'Telegram ID: ${profile!['user_id'] ?? '—'} • الصلاحية: ${profile!['role'] ?? '—'}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'تعديل الاسم الظاهر',
                    onPressed: busy ? null : _editProfile,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'تحديث بيانات الحساب',
                    onPressed: _loadProfile,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
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
                  leading: Icon(Icons.delete_outline, color: AppColors.of(context).pending),
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
                const ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('التقارير والتصحيح'),
                  subtitle: Text('تصدير ملفات Excel وتصحيح آخر قراءة عداد عند إدخالها بالخطأ.'),
                ),
                ListTile(
                  leading: const Icon(Icons.table_view_outlined),
                  title: const Text('تصدير جميع الشكاوى إلى Excel'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : () => _shareExport('/api/export/problems', 'reclamations.xlsx', 'تم تجهيز ملف الشكاوى للمشاركة'),
                ),
                ListTile(
                  leading: const Icon(Icons.local_gas_station_outlined),
                  title: const Text('تصدير تقرير Vidange إلى Excel'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : () => _shareExport('/api/export/vidange', 'vidange.xlsx', 'تم تجهيز ملف Vidange للمشاركة'),
                ),
                ListTile(
                  leading: const Icon(Icons.directions_car_filled_outlined),
                  title: const Text('تصدير Vidange لمركبة محددة'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : _shareVehicleVidange,
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('تصحيح آخر قراءة عداد (fixkm)'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: busy ? null : _fixLatestKm,
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
    );
  }

  Future<void> _editProfile() async {
    final current = (profile?['display_name'] ?? '').toString();
    final displayName = await _ask('تعديل الملف الشخصي', 'الاسم الظاهر داخل التطبيق', initialValue: current);
    if (displayName == null || displayName.trim().isEmpty || !mounted) return;
    if (displayName.trim().length < 2 || displayName.trim().length > 60) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم يجب أن يكون بين حرفين و60 حرفاً')));
      return;
    }
    // Avoid writing a new name if the dialog was cancelled or unchanged.
    if (displayName.trim() == current.trim()) return;
    await _run(() async {
      final updated = await Api.instance.updateProfile(displayName);
      if (mounted) setState(() => profile = updated);
    }, 'تم تحديث بيانات الملف الشخصي');
  }

  Future<void> _shareExport(String path, String filename, String success) async {
    await _run(() async {
      final filePath = await Api.instance.downloadExport(path, filename);
      await Share.shareXFiles([XFile(filePath)], text: filename);
    }, success);
  }

  Future<void> _shareVehicleVidange() async {
    final vehicle = await _ask('تصدير Vidange لمركبة', 'رمز المركبة، مثل M15');
    if (vehicle == null || vehicle.trim().isEmpty || !mounted) return;
    final code = Uri.encodeComponent(vehicle.trim().toUpperCase());
    await _shareExport('/api/export/vidange?vehicle=$code', 'vidange_${vehicle.trim().toUpperCase()}.xlsx', 'تم تجهيز تقرير المركبة للمشاركة');
  }

  Future<void> _fixLatestKm() async {
    final vehicle = await _ask('تصحيح قراءة العداد', 'رمز المركبة، مثل M15');
    if (vehicle == null || vehicle.trim().isEmpty || !mounted) return;
    final kmText = await _ask('القيمة الصحيحة', 'آخر قراءة عداد صحيحة بالكيلومتر');
    if (kmText == null || kmText.trim().isEmpty || !mounted) return;
    final km = int.tryParse(kmText.trim());
    if (km == null || km <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل قيمة كيلومترات صحيحة أكبر من صفر')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد تصحيح العداد'),
        content: Text('سيتم استبدال آخر قراءة مسجلة للمركبة ${vehicle.trim().toUpperCase()} بالقيمة $km KM. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد التصحيح')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final result = await Api.instance.fixLatestKm(vehicle.trim().toUpperCase(), km);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تصحيح ${result['vehicle']}: ${result['previous_km']} → ${result['corrected_km']} KM')),
        );
      }
    }, 'تم تصحيح آخر قراءة عداد');
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
                    subtitle: Text('آخر Vidange: ${v['last_vidange_km'] ?? 'غير مسجل'} KM • آخر قراءة: ${v['latest_km'] ?? 'غير متوفرة'} KM\nالمتبقي: ${remaining ?? 'غير متوفر'} KM'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'تعديل القيمة',
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final controller = TextEditingController(text: v['last_vidange_km']?.toString() ?? '');
                        final value = await showDialog<String>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: Text('تعديل Vidange • ${v['vehicle']}'),
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
                      icon: Icon(Icons.delete_outline, color: AppColors.of(ctx).pending),
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
