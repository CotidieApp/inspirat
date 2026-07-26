import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspirat/app.dart';
import 'package:inspirat/app_controller.dart';
import 'package:inspirat/data/local_store.dart';
import 'package:inspirat/data/models.dart';

WritingDocument sampleDocument({String content = ''}) => WritingDocument(
  clientId: 'document-local',
  projectClientId: 'project-local',
  title: 'Capítulo',
  content: content,
  updatedAt: DateTime.utc(2026),
);

class MemoryStore extends LocalStore {
  WritingDocument? savedDocument;

  @override
  Future<void> saveDocument(
    WritingDocument document, {
    bool enqueue = true,
  }) async {
    savedDocument = document;
  }

  @override
  Future<int> pendingCount() async => savedDocument == null ? 0 : 1;
}

class EditorController extends AppController {
  EditorController() : document = sampleDocument();

  WritingDocument document;
  int saves = 0;

  @override
  WritingDocument? findDocument(String clientId) => document;

  @override
  Future<WritingDocument> saveDocument(
    WritingDocument current,
    String content,
  ) async {
    saves += 1;
    document = sampleDocument(content: content);
    return document;
  }
}

class RestoredSessionController extends AppController {
  @override
  Future<void> initialize() async {
    username = 'Autora';
    localMode = false;
    ready = true;
  }
}

void main() {
  test(
    'guardar actualiza el almacenamiento y también la copia en memoria',
    () async {
      final store = MemoryStore();
      final controller = AppController(store: store);
      final original = sampleDocument();
      controller.documentsByProject[original.projectClientId] = [original];

      final updated = await controller.saveDocument(
        original,
        'Este párrafo debe sobrevivir.',
      );

      expect(store.savedDocument?.content, 'Este párrafo debe sobrevivir.');
      expect(updated.content, 'Este párrafo debe sobrevivir.');
      expect(
        controller.findDocument(original.clientId)?.content,
        'Este párrafo debe sobrevivir.',
      );
    },
  );

  testWidgets('el botón Guardar conserva el texto al reabrir el editor', (
    tester,
  ) async {
    final controller = EditorController();
    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(
          key: const ValueKey('first-editor'),
          controller: controller,
          documentId: controller.document.clientId,
        ),
      ),
    );

    final editor = tester.widget<TextField>(find.byType(TextField));
    expect(editor.textCapitalization, TextCapitalization.sentences);
    expect(editor.autocorrect, isTrue);
    expect(editor.enableSuggestions, isTrue);

    await tester.enterText(
      find.byType(TextField),
      'Un párrafo guardado de forma explícita.',
    );
    await tester.tap(find.byTooltip('Guardar ahora'));
    await tester.pump();

    expect(controller.saves, 1);
    expect(find.text('Guardado en el dispositivo'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(
          key: const ValueKey('reopened-editor'),
          controller: controller,
          documentId: controller.document.clientId,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Un párrafo guardado de forma explícita.'),
      findsOneWidget,
    );
  });

  testWidgets('una sesión restaurada abre directamente el inicio', (
    tester,
  ) async {
    final controller = RestoredSessionController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWithValue(controller)],
        child: const InspiratBootstrap(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hola, Autora'), findsOneWidget);
    expect(find.text('Crear una cuenta'), findsNothing);
  });
}
