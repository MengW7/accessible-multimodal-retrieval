import 'dart:io';

import 'package:path/path.dart' as p;

/// Paths are resolved once at the composition root, never by Widgets.
/// Repository Python is only used after explicit development opt-in.
final class RuntimeConfig {
  const RuntimeConfig({
    required this.resourceRoot,
    required this.dataDirectory,
    required this.development,
    required this.javaExecutable,
    this.configurationErrors = const [],
  });

  factory RuntimeConfig.fromEnvironment({
    Map<String, String>? environment,
    String? executable,
    String? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = operatingSystem ?? Platform.operatingSystem;
    final exe = executable ?? Platform.resolvedExecutable;
    final devRoot = env['AMR_DEV_ROOT'];
    final errors = <String>[];
    String absolute(String? value, String fallback, String name) {
      if (value == null || value.isEmpty) return fallback;
      if (!p.isAbsolute(value)) {
        errors.add('$name 必须是绝对路径：$value');
        return fallback;
      }
      return p.normalize(value);
    }

    final resources = absolute(
      devRoot,
      p.join(p.dirname(exe), 'runtime'),
      'AMR_DEV_ROOT',
    );
    final home = env[os == 'windows' ? 'USERPROFILE' : 'HOME'];
    final String? base = switch (os) {
      'windows' =>
        env['LOCALAPPDATA'] ??
            (home == null ? null : p.join(home, 'AppData', 'Local')),
      'macos' =>
        home == null ? null : p.join(home, 'Library', 'Application Support'),
      _ =>
        env['XDG_DATA_HOME'] ??
            (home == null ? null : p.join(home, '.local', 'share')),
    };
    final dataOverride = env['AMR_DATA_DIR'];
    if ((dataOverride == null || dataOverride.isEmpty) &&
        (base == null || !p.isAbsolute(base))) {
      errors.add('无法定位用户数据目录；请设置绝对路径 AMR_DATA_DIR。');
    }
    final fallback = p.join(p.dirname(exe), 'unconfigured-data');
    final data = absolute(
      dataOverride,
      base != null && p.isAbsolute(base)
          ? p.join(base, 'AccessibleMultimodalRetrieval')
          : fallback,
      'AMR_DATA_DIR',
    );
    final java = env['AMR_JAVA'] ?? 'java';
    if (java != 'java' && !p.isAbsolute(java)) {
      errors.add('AMR_JAVA 必须是绝对路径，或使用 PATH 中的 java。');
    }
    return RuntimeConfig(
      resourceRoot: resources,
      dataDirectory: data,
      development: devRoot != null && devRoot.isNotEmpty,
      javaExecutable: java,
      configurationErrors: List.unmodifiable(errors),
    );
  }

  final String resourceRoot;
  final String dataDirectory;
  final bool development;
  final String javaExecutable;
  final List<String> configurationErrors;
  String get databasePath => p.join(dataDirectory, 'library.sqlite');
  String get python => p.join(
    resourceRoot,
    'engine',
    '.venv',
    Platform.isWindows ? 'Scripts' : 'bin',
    Platform.isWindows ? 'python.exe' : 'python',
  );
  String get serverScript => p.join(resourceRoot, 'engine', 'embed_server.py');
  String get serverHelper => p.join(resourceRoot, 'engine', 'w3_embed_lib.py');
  String get textDirectory => p.join(
    resourceRoot,
    'models',
    'raw',
    'text',
    'paraphrase-multilingual-MiniLM-L12-v2',
  );
  String get imageDirectory =>
      p.join(resourceRoot, 'models', 'raw', 'image', 'mobileclip-s0');
  String get textTokenizer => p.join(textDirectory, 'tokenizer.json');
  String get textModel => p.join(textDirectory, 'onnx', 'model.onnx');
  String get imageModel => p.join(imageDirectory, 'onnx', 'vision_model.onnx');
  String get clipTextModel => p.join(imageDirectory, 'onnx', 'text_model.onnx');
  String get clipTokenizer => p.join(imageDirectory, 'tokenizer.json');
  String get tikaHome => p.join(resourceRoot, 'tools', 'tika-app');
  String get tikaJar => p.join(tikaHome, 'tika-app-4.0.0.jar');
  Map<String, String> get requiredFiles => {
    'Python': python,
    '嵌入服务': serverScript,
    '嵌入服务辅助模块': serverHelper,
    '文本分词器': textTokenizer,
    '文本模型': textModel,
    '图像模型': imageModel,
    '图文文本模型': clipTextModel,
    '图文分词器': clipTokenizer,
    'PDF 解析器': tikaJar,
  };
}
