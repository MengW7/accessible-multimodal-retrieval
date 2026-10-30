import 'package:flutter/services.dart';

import '../application/library_service.dart';

final class NativeDirectoryPicker implements DirectoryPicker {
  const NativeDirectoryPicker();
  static const channel = MethodChannel('accessible_retrieval/directories');
  @override
  Future<String?> choose() async {
    try {
      return await channel.invokeMethod<String>('chooseDirectory');
    } on MissingPluginException {
      throw UnsupportedError('当前平台未接入文件夹对话框，请手动输入目录的绝对路径。');
    }
  }
}
