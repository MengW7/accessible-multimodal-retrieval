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
    this.operatingSystem,
  });

  factory RuntimeConfig.fromEnvironment({
    Map<String, String>? environment,
    String? executable,
    String? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = operatingSystem ?? Platform.operatingSystem;
    final paths = os == 'windows' ? p.windows : p.posix;
    final exe = executable ?? Platform.resolvedExecutable;
    final devRoot = env['AMR_DEV_ROOT'];
    final errors = <String>[];
    String absolute(String? value, String fallback, String name) {
      if (value == null || value.isEmpty) return fallback;
      if (!paths.isAbsolute(value)) {
        errors.add('$name 必须是绝对路径：$value');
        return fallback;
      }
      return paths.normalize(value);
    }

    final resources = absolute(
      devRoot,
      paths.join(paths.dirname(exe), 'runtime'),
      'AMR_DEV_ROOT',
    );
    final home = env[os == 'windows' ? 'USERPROFILE' : 'HOME'];
    final String? base = switch (os) {
      'windows' =>
        env['LOCALAPPDATA'] ??
            (home == null ? null : paths.join(home, 'AppData', 'Local')),
      'macos' =>
        home == null
            ? null
            : paths.join(home, 'Library', 'Application Support'),
      _ =>
        env['XDG_DATA_HOME'] ??
            (home == null ? null : paths.join(home, '.local', 'share')),
    };
    final dataOverride = env['AMR_DATA_DIR'];
    if ((dataOverride == null || dataOverride.isEmpty) &&
        (base == null || !paths.isAbsolute(base))) {
      errors.add('无法定位用户数据目录；请设置绝对路径 AMR_DATA_DIR。');
    }
    final fallback = paths.join(paths.dirname(exe), 'unconfigured-data');
    final data = absolute(
      dataOverride,
      base != null && paths.isAbsolute(base)
          ? paths.join(base, 'AccessibleMultimodalRetrieval')
          : fallback,
      'AMR_DATA_DIR',
    );
    final java = env['AMR_JAVA'] ?? 'java';
    if (java != 'java' && !paths.isAbsolute(java)) {
      errors.add('AMR_JAVA 必须是绝对路径，或使用 PATH 中的 java。');
    }
    return RuntimeConfig(
      resourceRoot: resources,
      dataDirectory: data,
      development: devRoot != null && devRoot.isNotEmpty,
      javaExecutable: java,
      configurationErrors: List.unmodifiable(errors),
      operatingSystem: os,
    );
  }

  final String resourceRoot;
  final String dataDirectory;
  final bool development;
  final String javaExecutable;
  final List<String> configurationErrors;

  /// Overrides path semantics for configuration tests; null uses the host OS.
  final String? operatingSystem;

  bool get _isWindows =>
      (operatingSystem ?? Platform.operatingSystem) == 'windows';
  p.Context get _paths => _isWindows ? p.windows : p.posix;

  String get databasePath => _paths.join(dataDirectory, 'library.sqlite');
  String get python => _paths.join(
    resourceRoot,
    'engine',
    '.venv',
    _isWindows ? 'Scripts' : 'bin',
    _isWindows ? 'python.exe' : 'python',
  );
  String get serverScript =>
      _paths.join(resourceRoot, 'engine', 'embed_server.py');
  String get serverHelper =>
      _paths.join(resourceRoot, 'engine', 'w3_embed_lib.py');
  String get textDirectory => _paths.join(
    resourceRoot,
    'models',
    'raw',
    'text',
    'paraphrase-multilingual-MiniLM-L12-v2',
  );
  String get imageDirectory =>
      _paths.join(resourceRoot, 'models', 'raw', 'image', 'mobileclip-s0');
  String get textTokenizer => _paths.join(textDirectory, 'tokenizer.json');
  String get textModel => _paths.join(textDirectory, 'onnx', 'model.onnx');
  String get imageModel =>
      _paths.join(imageDirectory, 'onnx', 'vision_model.onnx');
  String get clipTextModel =>
      _paths.join(imageDirectory, 'onnx', 'text_model.onnx');
  String get clipTokenizer => _paths.join(imageDirectory, 'tokenizer.json');
  String get tikaHome => _paths.join(resourceRoot, 'tools', 'tika-app');
  String get tikaJar => _paths.join(tikaHome, 'tika-app-4.0.0.jar');
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
