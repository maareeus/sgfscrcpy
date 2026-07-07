import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/reverse_rule.dart';

/// Persists per-device `adb reverse` rules to a JSON file so they survive
/// restarts. Keyed by device serial.
class ReverseConfigStore {
  Map<String, List<ReverseRule>> _rules = {};

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/reverse_rules.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _rules = json.map((serial, list) => MapEntry(
            serial,
            (list as List)
                .map((e) => ReverseRule.fromJson(e as Map<String, dynamic>))
                .toList(),
          ));
    } catch (_) {
      _rules = {};
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      final json = _rules.map(
        (serial, list) => MapEntry(serial, list.map((r) => r.toJson()).toList()),
      );
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  List<ReverseRule> rulesFor(String serial) =>
      List.unmodifiable(_rules[serial] ?? const []);

  Future<void> setRules(String serial, List<ReverseRule> rules) async {
    if (rules.isEmpty) {
      _rules.remove(serial);
    } else {
      _rules[serial] = List.of(rules);
    }
    await _save();
  }
}
