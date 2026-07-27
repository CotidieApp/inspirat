import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        reportError(details.exception, details.stack ?? StackTrace.current);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        reportError(error, stack);
        return true;
      };
      runApp(const ProviderScope(child: InspiratBootstrap()));
    },
    (error, stack) => reportError(error, stack),
  );
}

/// Punto único para reportar errores no capturados. Sin un servicio de
/// crash reporting configurado, esto al menos deja rastro en los logs del
/// dispositivo en vez de que el error desaparezca sin ninguna huella;
/// reemplazar por Sentry (u otro) aquí en cuanto haya un DSN disponible.
void reportError(Object error, StackTrace stack) {
  debugPrint('UNCAUGHT ERROR: $error');
  debugPrint('$stack');
}
