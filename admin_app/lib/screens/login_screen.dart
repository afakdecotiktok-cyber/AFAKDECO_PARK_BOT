import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../widgets/app_widgets.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uid = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _uid.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.instance.login(_uid.text.trim(), _code.text.trim());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.tint(colors.primary),
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: Icon(
                            Icons.local_shipping_rounded,
                            color: colors.primary,
                            size: 33,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        AppStrings.appName,
                        textAlign: TextAlign.center,
                        style: AppText.title.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'لوحة إدارة المركبات',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(
                        title: 'تسجيل الدخول',
                        subtitle: 'أدخل بيانات التحقق التي حصلت عليها عبر Telegram.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        controller: _uid,
                        labelText: 'معرّف مستخدم Telegram',
                        hintText: 'أدخل المعرّف الرقمي',
                        keyboardType: TextInputType.number,
                        digitsOnly: true,
                        textInputAction: TextInputAction.next,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'أدخل معرّف مستخدم Telegram.';
                          }
                          if (int.tryParse(value.trim()) == null) {
                            return 'يجب أن يتكون المعرّف من أرقام.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: _code,
                        labelText: 'كود التحقق',
                        hintText: 'أدخل الكود المستلم من البوت',
                        keyboardType: TextInputType.number,
                        digitsOnly: true,
                        textInputAction: TextInputAction.done,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        onSubmitted: (_) => _submit(),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'أدخل كود التحقق.';
                          }
                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: colors.tint(colors.pending),
                            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                          ),
                          child: Text(
                            _error!,
                            style: AppText.body.copyWith(color: colors.pending),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: 'دخول آمن',
                        icon: Icons.login_rounded,
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'تبقى الجلسة محفوظة بأمان على هذا الجهاز حتى تنتهي صلاحيتها أو تسجّل الخروج.',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
