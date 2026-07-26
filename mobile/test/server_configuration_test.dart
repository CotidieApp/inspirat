import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspirat/app.dart';
import 'package:inspirat/app_controller.dart';

class FakeAppController extends AppController {
  @override
  Future<bool> configureServer(String rawValue) async {
    busy = true;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    serverBaseUrl = 'http://192.168.4.200:8000/api/v1';
    busy = false;
    notifyListeners();
    return true;
  }
}

void main() {
  testWidgets('el diálogo del servidor soporta notificaciones y se cierra', (
    tester,
  ) async {
    final controller = FakeAppController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showServerConfiguration(context, controller),
              child: const Text('Configurar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Configurar'));
    await tester.pumpAndSettle();
    expect(find.text('Conexión al servidor'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '192.168.4.200:8000');
    await tester.tap(find.text('Probar y guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Conexión al servidor'), findsNothing);
    expect(find.text('Servidor conectado correctamente.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
