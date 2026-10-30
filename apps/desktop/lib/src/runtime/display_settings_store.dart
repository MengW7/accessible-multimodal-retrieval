import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../application/display_settings.dart';

final class FileDisplaySettingsStore implements DisplaySettingsStore {
  FileDisplaySettingsStore(String dataDirectory)
    : file = File(p.join(dataDirectory, 'display-settings.json')) {
    if (!p.isAbsolute(dataDirectory)) throw ArgumentError('设置目录必须是绝对路径。');
  }
  final File file;
  @override
  Future<DisplaySettings> load() async {
    if (!await file.exists()) return const DisplaySettings();
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('显示设置不是 JSON 对象。');
    }
    return DisplaySettings.fromJson(json);
  }

  @override
  Future<void> save(DisplaySettings settings) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}
