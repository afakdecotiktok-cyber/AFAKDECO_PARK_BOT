import 'dart:async';
import 'dart:io';

import '../services/api.dart';

abstract final class AppStrings {
  static const appName = 'AFAKDECO PARK';
  static const dashboard = 'الرئيسية';
  static const problems = 'الشكاوى';
  static const drivers = 'السائقون';
  static const settings = 'الإعدادات';
  static const waiting = 'قيد الانتظار';
  static const inProgress = 'قيد التصليح';
  static const fixed = 'تم الإصلاح';
  static const accident = 'حادث';
  static const vidange = 'Vidange';
  static const kilometres = 'الكيلومترات';
  static const retry = 'إعادة المحاولة';
  static const search = 'بحث';
  static const noVehicles = 'لا توجد مركبات';
  static const noDrivers = 'لا يوجد سائقون';
  static const noReadings = 'لا توجد قراءات كيلومترات مسجلة';
}

String friendlyError(Object error) {
  if (error is ApiRequestException) {
    switch (error.statusCode) {
      case 401:
        return 'انتهت جلسة الدخول. سجّل الدخول مجدداً.';
      case 403:
        return 'ليست لديك الصلاحية لتنفيذ هذا الإجراء.';
      case 404:
        return 'لم نعثر على العنصر المطلوب.';
      case 409:
        final message = error.message.trim();
        return message.isNotEmpty && message.length <= 180
            ? message
            : 'لا يمكن تنفيذ الإجراء بسبب تعارض في الحالة الحالية.';
      case 408:
      case 504:
        return 'انتهت مهلة الاتصال. حاول مرة أخرى.';
      default:
        if (error.statusCode >= 500) {
          return 'الخادم يواجه مشكلة مؤقتة. حاول لاحقاً.';
        }
        return 'تعذر إتمام الطلب. تحقق من البيانات وحاول مرة أخرى.';
    }
  }

  if (error is SocketException || error is TimeoutException) {
    return 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.';
  }

  final message = error.toString().toLowerCase();
  if (message.contains('failed host lookup') ||
      message.contains('socketexception') ||
      message.contains('connection timed out') ||
      message.contains('network is unreachable')) {
    return 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.';
  }
  if (message.contains('انتهت جلسة الدخول')) {
    return 'انتهت جلسة الدخول. سجّل الدخول مجدداً.';
  }

  return 'تعذر إتمام العملية. حاول مرة أخرى.';
}
