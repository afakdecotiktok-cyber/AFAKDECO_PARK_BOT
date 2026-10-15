import 'package:flutter/foundation.dart';

/// Broadcasts successful writes so every mounted data screen can refresh from
/// the API after another screen changes server state.
abstract final class AppDataEvents {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyChanged() {
    revision.value = revision.value + 1;
  }
}
