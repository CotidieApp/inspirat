import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspirat/app_controller.dart';
import 'package:inspirat/community.dart';
import 'package:inspirat/data/api_client.dart';

Map<String, dynamic> messageJson(String clientId, String body) => {
  'id': 'server-$clientId',
  'client_id': clientId,
  'sender': {
    'id': 'current-user',
    'username': 'autora',
    'display_name': 'Autora',
  },
  'recipient': null,
  'body': body,
  'document': null,
  'created_at': '2026-07-26T17:21:00Z',
  'read_at': null,
};

AppController communityController(ApiClient api) {
  api.accessToken = 'test-token';
  final controller = AppController(api: api);
  controller
    ..localMode = false
    ..userId = 'current-user'
    ..username = 'Autora';
  return controller;
}

Future<void> enterAndSend(
  WidgetTester tester,
  AppController controller,
  String body,
) async {
  await tester.pumpWidget(
    MaterialApp(home: GeneralChatScreen(controller: controller)),
  );
  await tester.pump();
  await tester.enterText(find.byType(TextField), body);
  await tester.tap(find.byTooltip('Enviar'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> enterDirectAndSend(
  WidgetTester tester,
  AppController controller,
  String body,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DirectChatScreen(
        controller: controller,
        userId: 'peer-user',
        user: const CommunityUser(
          id: 'peer-user',
          username: 'lectora',
          displayName: 'Lectora',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.enterText(find.byType(TextField), body);
  await tester.tap(find.byTooltip('Enviar'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class PostSucceedsRefreshFailsApi extends ApiClient {
  int posts = 0;

  @override
  Future<List<dynamic>> generalMessages({
    int limit = 50,
    int offset = 0,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/community/general/messages'),
      type: DioExceptionType.connectionError,
    );
  }

  @override
  Future<Map<String, dynamic>> postGeneral({
    required String body,
    String? documentId,
    String? clientId,
  }) async {
    posts += 1;
    return messageJson(clientId!, body);
  }
}

class AmbiguousPostApi extends ApiClient {
  int posts = 0;
  int reads = 0;
  Map<String, dynamic>? stored;

  @override
  Future<List<dynamic>> generalMessages({
    int limit = 50,
    int offset = 0,
  }) async {
    reads += 1;
    return stored == null ? [] : [stored!];
  }

  @override
  Future<Map<String, dynamic>> postGeneral({
    required String body,
    String? documentId,
    String? clientId,
  }) async {
    posts += 1;
    stored = messageJson(clientId!, body);
    throw DioException(
      requestOptions: RequestOptions(path: '/community/general/messages'),
      type: DioExceptionType.receiveTimeout,
    );
  }
}

class DirectPostSucceedsRefreshFailsApi extends ApiClient {
  int posts = 0;
  int reads = 0;

  @override
  Future<List<dynamic>> directMessages(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    reads += 1;
    if (reads == 1) return [];
    throw DioException(
      requestOptions: RequestOptions(
        path: '/community/direct/$userId/messages',
      ),
      type: DioExceptionType.connectionError,
    );
  }

  @override
  Future<Map<String, dynamic>> sendDirectMessage(
    String userId, {
    required String body,
    String? documentId,
    String? clientId,
  }) async {
    posts += 1;
    return messageJson(clientId!, body);
  }

  @override
  Future<void> markConversationRead(String userId) async {}
}

class FailedPostApi extends ApiClient {
  @override
  Future<List<dynamic>> generalMessages({
    int limit = 50,
    int offset = 0,
  }) async => [];

  @override
  Future<Map<String, dynamic>> postGeneral({
    required String body,
    String? documentId,
    String? clientId,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/community/general/messages'),
      type: DioExceptionType.connectionError,
    );
  }
}

void main() {
  testWidgets(
    'un fallo al recargar no convierte un POST confirmado en error de envío',
    (tester) async {
      final api = PostSucceedsRefreshFailsApi();
      await enterAndSend(tester, communityController(api), 'Hola!!');

      expect(api.posts, 1);
      expect(find.text('Hola!!'), findsOneWidget);
      expect(
        find.textContaining('No se pudo confirmar el envío'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('un timeout posterior al guardado se reconcilia por client_id', (
    tester,
  ) async {
    final api = AmbiguousPostApi();
    await enterAndSend(tester, communityController(api), 'Bj');

    expect(api.posts, 1);
    expect(api.reads, greaterThanOrEqualTo(2));
    expect(find.text('Bj'), findsOneWidget);
    expect(find.textContaining('No se pudo confirmar el envío'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'si servidor y reconciliación fallan conserva el texto para reintentar',
    (tester) async {
      const body = 'Mensaje todavía no confirmado';
      await enterAndSend(tester, communityController(FailedPostApi()), body);

      expect(find.textContaining('No se pudo confirmar el envío'), findsOne);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        body,
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'el chat directo tampoco convierte una recarga fallida en error de envío',
    (tester) async {
      final api = DirectPostSucceedsRefreshFailsApi();
      await enterDirectAndSend(
        tester,
        communityController(api),
        'Mensaje privado',
      );

      expect(api.posts, 1);
      expect(find.text('Mensaje privado'), findsOneWidget);
      expect(
        find.textContaining('No se pudo confirmar el envío'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox());
    },
  );
}
