import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/strings.dart';
import '../services/api.dart';
import '../services/app_data_events.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../widgets/app_widgets.dart';
import 'vidange_screen.dart';
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تنفيذ العملية: ${friendlyError(e)}')));
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
    final colors = AppColors.of(context);
    final rawName = (profile?['display_name'] ?? '').toString().trim();
    final displayName = rawName.isEmpty ? 'الملف الشخصي' : rawName;
    final role = (profile?['role'] ?? '—').toString();
    final userId = (profile?['user_id'] ?? '—').toString();

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
        children: [
          Text(
            'الإعدادات والإدارة',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'إدارة الحساب والمركبات والتقارير والصيانة من مكان واحد.',
            style: AppText.body.copyWith(color: colors.textSecondary),
          ),
          if (busy) ...[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(color: colors.tint(colors.primary), borderRadius: BorderRadius.circular(18)),
                  child: Icon(Icons.person_rounded, color: colors.primary, size: 29),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.section.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(profile == null ? 'بيانات الحساب غير متوفرة بعد' : 'Telegram ID: $userId', style: AppText.caption.copyWith(color: colors.textSecondary)),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  role == 'super_admin' ? 'المشرف الأعلى' : role == 'admin' ? 'مشرف' : role,
                  style: AppText.caption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
                    ],
                  ),
                ),
                IconButton(tooltip: 'تعديل الاسم الظاهر', onPressed: busy ? null : _editProfile, icon: const Icon(Icons.edit_outlined)),
                IconButton(tooltip: 'تحديث الحساب', onPressed: busy ? null : _loadProfile, icon: const Icon(Icons.refresh_rounded)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _SettingsSection(
            title: 'الاتصال والأمان',
            subtitle: 'مصدر البيانات والوسائط وحماية بيانات الدخول.',
            icon: Icons.shield_outlined,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.telegram_rounded),
                title: Text('تكامل Telegram'),
                subtitle: Text('تبقى المجموعة ورسائل Telegram المرجع الأصلي للشكاوى والوسائط.'),
              ),
              const Divider(height: AppSpacing.lg),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline_rounded),
                title: Text('حماية بيانات الدخول'),
                subtitle: Text('لا تُضمّن مفاتيح البوت أو معلومات قاعدة البيانات داخل التطبيق.'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SettingsSection(
            title: 'إدارة المركبات',
            subtitle: 'إضافة المركبات أو حذفها وفق صلاحيات الحساب.',
            icon: Icons.directions_car_filled_outlined,
            children: [
              _SettingsActionTile(
                icon: Icons.add_circle_outline_rounded,
                title: 'إضافة مركبة',
                subtitle: 'تسجيل مركبة جديدة في النظام',
                onTap: busy ? null : () async {
                  final code = await _ask('إضافة مركبة', 'رمز المركبة، مثل H01');
                  if (code == null || code.trim().isEmpty || !mounted) return;
                  await _run(() => Api.instance.addVehicle(code), 'تم إرسال طلب إضافة المركبة');
                },
              ),
              _SettingsActionTile(
                icon: Icons.delete_outline_rounded,
                title: 'حذف مركبة',
                subtitle: 'إزالة مركبة بعد مراجعة ارتباطاتها',
                color: colors.pending,
                onTap: busy ? null : () async {
                  final code = await _ask('حذف مركبة', 'رمز المركبة المراد حذفها');
                  if (code == null || code.trim().isEmpty || !mounted) return;
                  final ok = await ConfirmDialog.show(
                    context,
                    title: 'تأكيد حذف المركبة',
                    message: 'هل تريد حذف المركبة ${code.toUpperCase()}؟ راجع ارتباطاتها قبل المتابعة.',
                    confirmLabel: 'تأكيد الحذف',
                    destructive: true,
                  );
                  if (ok == true && mounted) {
                    await _run(() => Api.instance.removeVehicle(code), 'تم إرسال طلب حذف المركبة');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SettingsSection(
            title: 'إدارة المشرفين',
            subtitle: 'تعديل قائمة المشرفين باستخدام Telegram User ID.',
            icon: Icons.admin_panel_settings_outlined,
            children: [
              _SettingsActionTile(
                icon: Icons.person_add_alt_1_rounded,
                title: 'إضافة مشرف',
                subtitle: 'إرسال طلب إضافة مشرف',
                onTap: busy ? null : () async {
                  final uid = await _ask('إضافة مشرف', 'Telegram User ID');
                  if (uid == null || uid.isEmpty || !mounted) return;
                  await _run(() => Api.instance.addAdmin(uid), 'تم إرسال طلب إضافة المشرف');
                },
              ),
              _SettingsActionTile(
                icon: Icons.people_alt_outlined,
                title: 'عرض المشرفين الحاليين',
                subtitle: 'عرض الأدوار وإدارة القائمة',
                onTap: busy ? null : _showAdmins,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SettingsSection(
            title: 'Vidange والكيلومترات',
            subtitle: 'متابعة الصيانة ومواعيدها وتصحيح قراءات العداد.',
            icon: Icons.handyman_outlined,
            children: [
              _SettingsActionTile(
                icon: Icons.local_gas_station_outlined,
                title: 'لوحة متابعة Vidange',
                subtitle: 'عرض كل المركبات والموعد القادم ومقدار التجاوز',
                onTap: busy ? null : _showVidange,
              ),
              _SettingsActionTile(
                icon: Icons.edit_road_outlined,
                title: 'تصحيح آخر قراءة عداد',
                subtitle: 'تصحيح آخر قيمة مسجلة باستخدام fixkm',
                onTap: busy ? null : _fixLatestKm,
              ),
              _SettingsActionTile(
                icon: Icons.cached_rounded,
                title: 'مسح التخزين المؤقت',
                subtitle: 'إزالة النسخ المحلية وإعادة تحميل البيانات',
                onTap: busy ? null : () => _run(() async {
                  await Api.instance.clearApiCache();
                  AppDataEvents.notifyChanged();
                }, 'تم مسح التخزين المؤقت وإعادة تحميل البيانات'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SettingsSection(
            title: 'التقارير والأرشفة',
            subtitle: 'تصدير ملفات Excel والرجوع إلى الوسائط الأصلية في Telegram.',
            icon: Icons.file_present_outlined,
            children: [
              _SettingsActionTile(
                icon: Icons.table_view_outlined,
                title: 'تصدير جميع الشكاوى',
                subtitle: 'إنشاء ملف Excel للمشاركة',
                onTap: busy ? null : () => _shareExport('/api/export/problems', 'reclamations.xlsx', 'تم تجهيز ملف الشكاوى للمشاركة'),
              ),
              _SettingsActionTile(
                icon: Icons.local_gas_station_outlined,
                title: 'تصدير تقرير Vidange',
                subtitle: 'تقرير صيانة لجميع المركبات',
                onTap: busy ? null : () => _shareExport('/api/export/vidange', 'vidange.xlsx', 'تم تجهيز تقرير Vidange للمشاركة'),
              ),
              _SettingsActionTile(
                icon: Icons.directions_car_outlined,
                title: 'تصدير Vidange لمركبة محددة',
                subtitle: 'اختيار رمز المركبة ثم مشاركة التقرير',
                onTap: busy ? null : _shareVehicleVidange,
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.archive_outlined),
                title: Text('الوسائط المؤرشفة'),
                subtitle: Text('تبقى الوسائط القديمة قابلة للوصول من رسالة Telegram الأصلية.'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: busy ? null : widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('تسجيل الخروج'),
          ),
        ],
      ),
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const VidangeOverviewScreen(),
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
        builder: (ctx) => SafeArea(
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
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر جلب المشرفين: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: colors.tint(colors.primary), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: colors.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: SectionHeader(title: title, subtitle: subtitle)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tint = color ?? colors.primary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: colors.tint(tint), borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, color: tint, size: 21),
      ),
      title: Text(title, style: AppText.label.copyWith(fontSize: 14)),
      subtitle: Text(subtitle, style: AppText.caption.copyWith(color: colors.textSecondary)),
      trailing: Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
    );
  }
}
