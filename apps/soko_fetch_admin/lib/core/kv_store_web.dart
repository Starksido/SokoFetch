import 'package:web/web.dart' as web;

/// Browser tab storage: cleared when the tab is closed.
class KeyValueStore {
  String? read(String key) => web.window.sessionStorage.getItem(key);
  void write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);
  void delete(String key) => web.window.sessionStorage.removeItem(key);
}
