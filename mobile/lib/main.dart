import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';

/// Vacío en builds sin `--dart-define=SENTRY_DSN=...` (ej. desarrollo local):
/// en ese caso no se activa Sentry, solo el logging local de siempre.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_sentryDsn.isEmpty) {
    runZonedGuarded(
      () {
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
    return;
  }
  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    options.tracesSampleRate = 0.2;
    options.beforeSend = (event, hint) async {
      reportError(
        event.throwable ?? event.message ?? 'evento sin excepción asociada',
        StackTrace.current,
      );
      return event;
    };
  }, appRunner: () => runApp(const ProviderScope(child: InspiratBootstrap())));
}

/// Punto único para reportar errores no capturados: siempre deja rastro en
/// los logs del dispositivo, además de mandarlo a Sentry cuando está activo.
void reportError(Object error, StackTrace stack) {
  debugPrint('UNCAUGHT ERROR: $error');
  debugPrint('$stack');
}
