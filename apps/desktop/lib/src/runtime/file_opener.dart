import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../application/search_models.dart';

typedef FileLauncher = Future<void> Function(String absolutePath);

/// Uses only a complete local path returned by the index. No shell command is
/// constructed from a filename; relative probe keys are never guessed from cwd.
final class NativeFileOpener implements FileOpener {
  NativeFileOpener({FileLauncher? launcher})
    : _launch = launcher ?? _nativeLaunch;
  static const channel = MethodChannel('accessible_retrieval/files');
  final FileLauncher _launch;
  static Future<void> _nativeLaunch(String path) async {
    await channel.invokeMethod<void>('openFile', path);
  }

  @override
  Future<FileOpenOutcome> open(String? absolutePath) async {
    if (absolutePath == null ||
        !p.isAbsolute(absolutePath) ||
        absolutePath.contains('\u0000') ||
        absolutePath.contains('://')) {
      return const FileOpenOutcome(
        FileOpenStatus.invalidPath,
        '索引缺少可用的本地绝对路径，请重新导入该文件所在目录后重试。',
      );
    }
    try {
      final sourcePath = p.normalize(absolutePath);
      if (!await File(sourcePath).exists()) {
        return const FileOpenOutcome(
          FileOpenStatus.missing,
          '源文件不存在、不可访问或不是文件。请检查路径及权限，恢复文件后重试或更新索引。',
        );
      }
      await _launch(sourcePath);
      return const FileOpenOutcome(
        FileOpenStatus.requested,
        '已请求系统打开原文件。系统查看器可能无法自动定位到指定页或片段。',
      );
    } on MissingPluginException {
      return const FileOpenOutcome(
        FileOpenStatus.failed,
        '当前平台尚未接入系统打开功能，请复制来源路径后手动打开文件。',
      );
    } on PlatformException catch (error) {
      if (error.code == 'source_missing') {
        return const FileOpenOutcome(
          FileOpenStatus.missing,
          '源文件已丢失。请恢复文件后重试，或更新索引。',
        );
      }
      return FileOpenOutcome(
        FileOpenStatus.failed,
        '系统未能打开文件，请检查文件权限及默认查看器后重试。${error.message ?? ''}',
      );
    } catch (error) {
      return FileOpenOutcome(
        FileOpenStatus.failed,
        '打开文件失败，请检查文件权限及默认查看器后重试：$error',
      );
    }
  }
}
