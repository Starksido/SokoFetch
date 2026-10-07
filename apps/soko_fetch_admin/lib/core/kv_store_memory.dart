/// In-memory storage, used outside the browser (tests).
class KeyValueStore {
  final _values = <String, String>{};

  String? read(String key) => _values[key];
  void write(String key, String value) => _values[key] = value;
  void delete(String key) => _values.remove(key);
}
