// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

String? readNotificationState(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void writeNotificationState(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {
    // Read state still works in memory when browser storage is unavailable.
  }
}
