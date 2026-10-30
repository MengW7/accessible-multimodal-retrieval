enum DisplayTheme { system, light, dark }

enum FontSizeMode { system, percent100, percent150, percent200 }

extension FontSizeDescription on FontSizeMode {
  String get label => switch (this) {
    FontSizeMode.system => '跟随系统',
    FontSizeMode.percent100 => '100%',
    FontSizeMode.percent150 => '150%',
    FontSizeMode.percent200 => '200%',
  };
  double? get scale => switch (this) {
    FontSizeMode.system => null,
    FontSizeMode.percent100 => 1,
    FontSizeMode.percent150 => 1.5,
    FontSizeMode.percent200 => 2,
  };
}

final class DisplaySettings {
  const DisplaySettings({
    this.theme = DisplayTheme.system,
    this.highContrast = false,
    this.fontSize = FontSizeMode.system,
  });
  final DisplayTheme theme;
  final bool highContrast;
  final FontSizeMode fontSize;
  DisplaySettings copyWith({
    DisplayTheme? theme,
    bool? highContrast,
    FontSizeMode? fontSize,
  }) => DisplaySettings(
    theme: theme ?? this.theme,
    highContrast: highContrast ?? this.highContrast,
    fontSize: fontSize ?? this.fontSize,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'theme': theme.name,
    'highContrast': highContrast,
    'fontSize': fontSize.name,
  };
  factory DisplaySettings.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['highContrast'] is! bool) {
      throw const FormatException('显示设置格式或版本不受支持。');
    }
    try {
      return DisplaySettings(
        theme: DisplayTheme.values.byName(json['theme'] as String),
        highContrast: json['highContrast'] as bool,
        fontSize: FontSizeMode.values.byName(json['fontSize'] as String),
      );
    } catch (_) {
      throw const FormatException('显示设置包含无效的选项。');
    }
  }
}

abstract interface class DisplaySettingsStore {
  Future<DisplaySettings> load();
  Future<void> save(DisplaySettings settings);
}
