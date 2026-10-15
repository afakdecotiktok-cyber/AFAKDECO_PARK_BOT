import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: AppText.caption.copyWith(color: colors.textSecondary)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(label),
            ],
          );
    return SizedBox(
      width: expand ? double.infinity : null,
      child: FilledButton(onPressed: loading ? null : onPressed, child: child),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: expand ? double.infinity : null,
        child: OutlinedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon ?? Icons.arrow_forward_rounded, size: 18),
          label: Text(label),
        ),
      );
}

class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: expand ? double.infinity : null,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.pending,
          side: BorderSide(color: colors.pending.withValues(alpha: 0.55)),
        ),
        icon: loading
            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.delete_outline_rounded, size: 18),
        label: Text(label),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.digitsOnly = false,
    this.search = false,
    this.enabled = true,
    this.maxLines = 1,
    this.textInputAction,
    this.suffixIcon,
    this.prefixIcon,
    this.autofillHints,
    this.validator,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final bool digitsOnly;
  final bool search;
  final bool enabled;
  final int maxLines;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType ?? (digitsOnly ? TextInputType.number : null),
      inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      maxLines: maxLines,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: prefixIcon ?? (search ? const Icon(Icons.search_rounded) : null),
        suffixIcon: suffixIcon ??
            (search && controller.text.isNotEmpty
                ? IconButton(
                    tooltip: 'مسح البحث',
                    onPressed: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  )
                : null),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.label,
    this.icon,
  });

  final String status;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final key = _statusKey(status);
    final color = colors.statusColor(key);
    final text = label ?? _statusLabel(status, key);
    return Semantics(
      label: 'الحالة: $text',
      child: Tooltip(
        message: text,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.tint(color),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon ?? _statusIcon(key), size: 14, color: color),
              const SizedBox(width: 5),
              Text(text, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusKey(String value) {
  final normal = value.trim().toLowerCase();
  if (normal == 'pending' || normal == 'قيد الانتظار') return 'pending';
  if (normal == 'in_progress' || normal == 'قيد التصليح') return 'in_progress';
  if (normal == 'accident' || normal == 'حادث') return 'accident';
  if (normal == 'vidange') return 'vidange';
  if (normal == 'تم الإصلاح' || normal == 'fixed') return 'fixed';
  if (normal == 'normal' || normal == 'سليمة') return 'normal';
  return 'other';
}

String _statusLabel(String value, String key) => switch (key) {
      'pending' => AppStrings.waiting,
      'in_progress' => AppStrings.inProgress,
      'accident' => AppStrings.accident,
      'vidange' => AppStrings.vidange,
      'fixed' => AppStrings.fixed,
      'normal' => 'سليمة',
      _ => value.isEmpty ? 'غير محدد' : value,
    };

IconData _statusIcon(String key) => switch (key) {
      'pending' => Icons.hourglass_top_rounded,
      'in_progress' => Icons.build_circle_rounded,
      'accident' => Icons.warning_rounded,
      'vidange' => Icons.handyman_rounded,
      'fixed' || 'normal' => Icons.check_circle_rounded,
      _ => Icons.info_outline_rounded,
    };

class SummaryTile extends StatelessWidget {
  const SummaryTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.statusKey = 'primary',
    this.selected = false,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final String statusKey;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = statusKey == 'primary' ? colors.primary : colors.statusColor(statusKey);
    return SizedBox(
      width: 112,
      child: Material(
        color: selected ? colors.tint(color) : colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: selected ? color.withValues(alpha: 0.55) : colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 19),
                const SizedBox(height: AppSpacing.sm),
                Text(value, style: AppText.title.copyWith(color: colors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? description;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: colors.surfaceAlt, borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, size: 28, color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center, style: AppText.section),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(description!, textAlign: TextAlign.center, style: AppText.body.copyWith(color: colors.textSecondary)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 38, color: colors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(AppStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingSkeletonList extends StatelessWidget {
  const LoadingSkeletonList({super.key, this.count = 5, this.itemHeight = 82});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, __) => Container(
        height: itemHeight,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(14))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 12, width: 128, color: colors.border),
                  const SizedBox(height: AppSpacing.sm),
                  Container(height: 10, width: 180, color: colors.border),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

abstract final class AppSnackbar {
  static void success(BuildContext context, String message) => _show(context, message, Icons.check_circle_outline_rounded);
  static void error(BuildContext context, String message) => _show(context, message, Icons.error_outline_rounded);
  static void info(BuildContext context, String message) => _show(context, message, Icons.info_outline_rounded);

  static void _show(BuildContext context, String message, IconData icon) {
    final foreground = Theme.of(context).snackBarTheme.contentTextStyle?.color;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, size: 19, color: foreground),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}

abstract final class ConfirmDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String cancelLabel = 'إلغاء',
    bool destructive = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.of(context).pending) : null,
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
}

abstract final class AppBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: isScrollControlled,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: AppColors.of(context).surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.sheetRadius)),
        ),
        builder: builder,
      );
}
