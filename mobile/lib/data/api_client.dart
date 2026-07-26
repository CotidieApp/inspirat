import 'package:dio/dio.dart';

import '../core/config.dart';

class ApiClient {
  ApiClient()
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (exception, handler) async {
          final request = exception.requestOptions;
          final shouldRefresh =
              exception.response?.statusCode == 401 &&
              request.headers['Authorization'] != null &&
              request.extra['skip_auth_refresh'] != true &&
              request.extra['auth_retried'] != true &&
              refreshAccessToken != null;
          if (!shouldRefresh) {
            handler.next(exception);
            return;
          }
          try {
            final token = await _refreshOnce();
            if (token == null) {
              handler.next(exception);
              return;
            }
            request.extra['auth_retried'] = true;
            request.headers['Authorization'] = 'Bearer $token';
            handler.resolve(await dio.fetch<dynamic>(request));
          } catch (_) {
            handler.next(exception);
          }
        },
      ),
    );
  }
  final Dio dio;
  String? accessToken;
  Future<String?> Function()? refreshAccessToken;
  Future<String?>? _activeRefresh;

  Future<String?> _refreshOnce() {
    final running = _activeRefresh;
    if (running != null) return running;
    final callback = refreshAccessToken;
    if (callback == null) return Future<String?>.value();
    final future = callback();
    _activeRefresh = future;
    return future.whenComplete(() {
      if (identical(_activeRefresh, future)) _activeRefresh = null;
    });
  }

  void setBaseUrl(String value) {
    dio.options.baseUrl = value;
  }

  Future<bool> checkServer(String apiUrl) async {
    final root = apiUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
    final response = await Dio(
      BaseOptions(
        baseUrl: root,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    ).get<Map<String, dynamic>>('/health');
    return response.statusCode == 200 && response.data?['status'] == 'ok';
  }

  Options get authorized => Options(
    headers: accessToken == null
        ? null
        : {'Authorization': 'Bearer $accessToken'},
  );

  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async => (await dio.post<Map<String, dynamic>>(
    '/auth/register',
    data: {
      'email': email,
      'username': username,
      'display_name': displayName,
      'password': password,
      'accepted_terms': true,
    },
    options: Options(extra: {'skip_auth_refresh': true}),
  )).data!;

  Future<Map<String, dynamic>> login(String identity, String password) async =>
      (await dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'identity': identity,
          'password': password,
          'device_name': 'Android',
        },
        options: Options(extra: {'skip_auth_refresh': true}),
      )).data!;

  Future<Map<String, dynamic>> refresh(String refreshToken) async =>
      (await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken, 'device_name': 'Android'},
        options: Options(extra: {'skip_auth_refresh': true}),
      )).data!;

  Future<void> requestPasswordReset(String identity) async {
    await dio.post<Map<String, dynamic>>(
      '/auth/password/forgot',
      data: {'identity': identity},
      options: Options(extra: {'skip_auth_refresh': true}),
    );
  }

  Future<Map<String, dynamic>> confirmPasswordReset({
    required String identity,
    required String code,
    required String newPassword,
  }) async => (await dio.post<Map<String, dynamic>>(
    '/auth/password/reset',
    data: {
      'identity': identity,
      'code': code,
      'new_password': newPassword,
      'device_name': 'Android',
    },
    options: Options(extra: {'skip_auth_refresh': true}),
  )).data!;

  Future<Map<String, dynamic>> sync(
    List<Map<String, Object?>> changes,
    String? since,
  ) async => (await dio.post<Map<String, dynamic>>(
    '/sync',
    data: {'changes': changes, 'since': since},
    options: authorized,
  )).data!;

  Future<List<dynamic>> inbox() async => (await dio.get<List<dynamic>>(
    '/shares/inbox',
    options: authorized,
  )).data!;

  Future<List<dynamic>> communityUsers({
    String? query,
    int limit = 100,
    int offset = 0,
  }) async => (await dio.get<List<dynamic>>(
    '/community/users',
    queryParameters: {
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'limit': limit,
      'offset': offset,
    },
    options: authorized,
  )).data!;

  Future<List<dynamic>> generalMessages({
    int limit = 50,
    int offset = 0,
  }) async => (await dio.get<List<dynamic>>(
    '/community/general/messages',
    queryParameters: {'limit': limit, 'offset': offset},
    options: authorized,
  )).data!;

  Future<Map<String, dynamic>> postGeneral({
    required String body,
    String? documentId,
    String? clientId,
  }) async => (await dio.post<Map<String, dynamic>>(
    '/community/general/messages',
    data: {'body': body, 'document_id': ?documentId, 'client_id': ?clientId},
    options: authorized,
  )).data!;

  Future<Map<String, dynamic>> publishCommunity({
    required String clientId,
    required String body,
    required bool publishGeneral,
    required List<String> recipientIds,
    String? documentId,
  }) async => (await dio.post<Map<String, dynamic>>(
    '/community/publish',
    data: {
      'client_id': clientId,
      'body': body,
      'document_id': ?documentId,
      'publish_general': publishGeneral,
      'recipient_ids': recipientIds,
    },
    options: authorized,
  )).data!;

  Future<List<dynamic>> conversations() async => (await dio.get<List<dynamic>>(
    '/community/conversations',
    options: authorized,
  )).data!;

  Future<List<dynamic>> directMessages(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async => (await dio.get<List<dynamic>>(
    '/community/direct/$userId/messages',
    queryParameters: {'limit': limit, 'offset': offset},
    options: authorized,
  )).data!;

  Future<Map<String, dynamic>> sendDirectMessage(
    String userId, {
    required String body,
    String? documentId,
    String? clientId,
  }) async => (await dio.post<Map<String, dynamic>>(
    '/community/direct/$userId/messages',
    data: {'body': body, 'document_id': ?documentId, 'client_id': ?clientId},
    options: authorized,
  )).data!;

  Future<void> markConversationRead(String userId) =>
      dio.post<void>('/community/direct/$userId/read', options: authorized);

  Future<void> comment(String documentId, String body) => dio.post<void>(
    '/documents/$documentId/comments',
    data: {'body': body},
    options: authorized,
  );

  Future<void> share(
    String documentId,
    String recipient,
    String permission,
    String message,
  ) => dio.post<void>(
    '/documents/$documentId/shares',
    data: {
      'recipient': recipient,
      'permission': permission,
      'message': message,
    },
    options: authorized,
  );

  Future<void> createVersion(String documentId, String name) => dio.post<void>(
    '/documents/$documentId/versions',
    data: {'name': name},
    options: authorized,
  );
}
