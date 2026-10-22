import 'package:flutter/foundation.dart';

/// Lets the Dashboard refresh its attendance summary after a punch succeeds.
final ValueNotifier<int> attendanceRefreshSignal = ValueNotifier<int>(0);

void notifyAttendanceChanged() {
  attendanceRefreshSignal.value++;
}
