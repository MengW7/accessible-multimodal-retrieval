import 'package:flutter/services.dart';

import '../application/app_controller.dart';

const windowLifecycle = MethodChannel('accessible_retrieval/lifecycle');

void bindWindowLifecycle(AppController controller) {
  windowLifecycle.setMethodCallHandler((call) async {
    if (call.method != 'requestClose') throw MissingPluginException();
    await controller.shutdown();
    return null;
  });
}
