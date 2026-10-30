import 'dart:isolate';

import '../runtime/runtime_config.dart';
import '../runtime/runtime_diagnostics.dart';
import '../runtime/runtime_session.dart';

enum CheckStatus { passed, blocked, warning }

final class RuntimeCheck {
  const RuntimeCheck(this.name, this.status, this.detail);
  final String name;
  final CheckStatus status;
  final String detail;
  Map<String, Object?> toJson() => {
    'name': name,
    'status': status.name,
    'detail': detail,
  };
}

final class RuntimeReport {
  const RuntimeReport({
    required this.config,
    required this.checks,
    this.documents,
    this.chunks,
  });
  final RuntimeConfig config;
  final List<RuntimeCheck> checks;
  final int? documents;
  final int? chunks;
  bool get ready =>
      checks.isNotEmpty && !checks.any((c) => c.status == CheckStatus.blocked);
  Map<String, Object?> toJson() => {
    'ready': ready,
    'mode': config.development ? 'development' : 'release',
    'resourceRoot': config.resourceRoot,
    'databasePath': config.databasePath,
    'documents': documents,
    'chunks': chunks,
    'checks': checks.map((c) => c.toJson()).toList(),
  };
}

/// inspect() checks availability, not inference correctness. verify() explicitly
/// exercises real models in an independent smoke database.
abstract interface class DesktopService {
  Future<RuntimeReport> inspect();
  Future<Map<String, Object?>> verify(String fixtureDirectory);
}

final class LocalDesktopService implements DesktopService {
  const LocalDesktopService(this.config);
  final RuntimeConfig config;
  @override
  Future<RuntimeReport> inspect() {
    final settings = config;
    return Isolate.run(() => inspectRuntime(settings));
  }

  @override
  Future<Map<String, Object?>> verify(String fixtureDirectory) {
    final settings = config;
    return Isolate.run(() => verifyRuntime(settings, fixtureDirectory));
  }
}
