import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inspirat/app.dart';
import 'package:inspirat/app_controller.dart';
import 'package:inspirat/data/api_client.dart';
import 'package:inspirat/data/local_store.dart';
import 'package:inspirat/data/models.dart';

class MemoryStore extends LocalStore {
  @override
  Future<void> switchScope(String scope, {bool claimLocalData = false}) async {}

  @override
  Future<List<WritingProject>> projects() async => [];

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<int> conflictCount() async => 0;

  @override
  Future<int> projectCount({String? scope}) async => 0;
}

class FakeApiClient extends ApiClient {
  int forgotCalls = 0;
  String? lastIdentity;
  int resetCalls = 0;
  String? lastCode;
  String? lastNewPassword;
  bool failReset = false;

  @override
  Future<void> requestPasswordReset(String identity) async {
    forgotCalls += 1;
    lastIdentity = identity;
  }

  @override
  Future<Map<String, dynamic>> confirmPasswordReset({
    required String identity,
    required String code,
    required String newPassword,
  }) async {
    resetCalls += 1;
    lastCode = code;
    lastNewPassword = newPassword;
    if (failReset) {
      const path = '/auth/password/reset';
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 400,
          data: {'detail': 'Código inválido o vencido'},
        ),
      );
    }
    return {
      'access_token': 'access-token',
      'refresh_token': 'refresh-token',
      'token_type': 'bearer',
      'expires_in': 900,
      'user': {
        'id': 'user-1',
        'email': identity,
        'username': 'autora',
        'display_name': 'Autora',
      },
    };
  }
}

Future<void> pumpScreen(WidgetTester tester, AppController controller) async {
  final router = GoRouter(
    initialLocation: '/forgot-password',
    routes: [
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => ForgotPasswordScreen(controller: controller),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const SizedBox(key: Key('home-screen')),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  testWidgets('solicita el codigo y luego restablece la contrasena', (
    tester,
  ) async {
    final api = FakeApiClient();
    final controller = AppController(store: MemoryStore(), api: api);
    await pumpScreen(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo o usuario'),
      'autora@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar código'));
    await tester.pump();
    await tester.pump();

    expect(api.forgotCalls, 1);
    expect(api.lastIdentity, 'autora@example.com');
    expect(find.text('Código de 6 dígitos'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código de 6 dígitos'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'Otra-clave-2026-segura',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'Otra-clave-2026-segura',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Restablecer contraseña'));
    await tester.pump();
    await tester.pump();

    expect(api.resetCalls, 1);
    expect(api.lastCode, '123456');
    expect(api.lastNewPassword, 'Otra-clave-2026-segura');
    expect(find.byKey(const Key('home-screen')), findsOneWidget);
  });

  testWidgets('un codigo invalido muestra el error y no navega', (
    tester,
  ) async {
    final api = FakeApiClient()..failReset = true;
    final controller = AppController(store: MemoryStore(), api: api);
    await pumpScreen(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo o usuario'),
      'autora@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar código'));
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código de 6 dígitos'),
      '000000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'Otra-clave-2026-segura',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'Otra-clave-2026-segura',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Restablecer contraseña'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Código inválido o vencido'), findsOneWidget);
    expect(find.byKey(const Key('home-screen')), findsNothing);
  });

  testWidgets('la confirmacion de contrasena debe coincidir', (tester) async {
    final api = FakeApiClient();
    final controller = AppController(store: MemoryStore(), api: api);
    await pumpScreen(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo o usuario'),
      'autora@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar código'));
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código de 6 dígitos'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'Otra-clave-2026-segura',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'no-coincide',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Restablecer contraseña'));
    await tester.pump();

    expect(api.resetCalls, 0);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });
}
