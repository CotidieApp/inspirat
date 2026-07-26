import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'core/config.dart';
import 'data/api_client.dart';
import 'data/local_store.dart';
import 'data/models.dart';

class AppController extends ChangeNotifier {
  AppController({
    LocalStore? store,
    ApiClient? api,
    FlutterSecureStorage? secureStorage,
    Uuid? uuid,
  }) : store = store ?? LocalStore(),
       api = api ?? ApiClient(),
       _secure = secureStorage ?? const FlutterSecureStorage(),
       _uuid = uuid ?? const Uuid() {
    this.api.refreshAccessToken = _refreshAccessToken;
  }

  final LocalStore store;
  final ApiClient api;
  final FlutterSecureStorage _secure;
  final Uuid _uuid;
  int _sessionEpoch = 0;

  bool ready = false;
  bool busy = false;
  bool localMode = true;
  String? userId;
  String? accountUsername;
  String? username;
  String? error;
  String serverBaseUrl = AppConfig.apiBaseUrl;
  String syncState = 'Solo en este dispositivo';
  int pendingCount = 0;
  int conflictCount = 0;
  int localProjectsAvailable = 0;
  List<WritingProject> projects = [];
  final Map<String, List<WritingDocument>> documentsByProject = {};

  Future<void> initialize() async {
    await store.open();
    await reload();
    final savedServer = await _secure.read(key: 'server_url');
    if (savedServer != null && savedServer.isNotEmpty) {
      serverBaseUrl = savedServer;
      api.setBaseUrl(savedServer);
    }
    final refreshToken = await _secure.read(key: 'refresh_token');
    if (refreshToken != null) {
      username = await _secure.read(key: 'session_display_name') ?? 'Tu cuenta';
      userId = await _secure.read(key: 'session_user_id');
      accountUsername = await _secure.read(key: 'session_username');
      if (userId != null) {
        await store.switchScope(_accountScope(userId!));
        await reload();
        localProjectsAvailable = await store.projectCount(
          scope: LocalStore.localScope,
        );
      }
      localMode = false;
      syncState = 'Restaurando sesión…';
      try {
        await _applyTokens(await api.refresh(refreshToken));
      } on DioException catch (exception) {
        final status = exception.response?.statusCode;
        if (status == 401 || status == 403) {
          await _clearStoredSession();
          userId = null;
          accountUsername = null;
          username = null;
          localMode = true;
          syncState = 'Solo en este dispositivo';
          await store.switchScope(LocalStore.localScope);
          await reload();
        } else {
          error = _friendly(exception);
          syncState = 'Sesión guardada · sin conexión';
        }
      } catch (exception) {
        error = _friendly(exception);
        syncState = 'Sesión guardada · sin conexión';
      }
    }
    ready = true;
    notifyListeners();
    if (!localMode) unawaited(sync());
  }

  Future<void> reload() async {
    projects = await store.projects();
    pendingCount = await store.pendingCount();
    conflictCount = await store.conflictCount();
    documentsByProject.clear();
    for (final project in projects) {
      documentsByProject[project.clientId] = await store.documents(
        project.clientId,
      );
    }
    notifyListeners();
  }

  Future<void> _applyTokens(Map<String, dynamic> data) async {
    api.accessToken = data['access_token'] as String;
    await _secure.write(
      key: 'refresh_token',
      value: data['refresh_token'] as String,
    );
    final user = data['user'] as Map<String, dynamic>;
    userId = user['id'] as String;
    accountUsername = user['username'] as String;
    username = user['display_name'] as String;
    await _secure.write(key: 'session_user_id', value: userId);
    await _secure.write(key: 'session_username', value: accountUsername);
    await _secure.write(key: 'session_display_name', value: username);
    await store.switchScope(_accountScope(userId!));
    await reload();
    localProjectsAvailable = await store.projectCount(
      scope: LocalStore.localScope,
    );
    localMode = false;
    syncState = 'Pendiente de sincronizar';
  }

  Future<void> _clearStoredSession() async {
    await _secure.delete(key: 'refresh_token');
    await _secure.delete(key: 'session_user_id');
    await _secure.delete(key: 'session_username');
    await _secure.delete(key: 'session_display_name');
  }

  Future<String?> _refreshAccessToken() async {
    final epoch = _sessionEpoch;
    final refreshToken = await _secure.read(key: 'refresh_token');
    if (refreshToken == null) return null;
    try {
      final data = await api.refresh(refreshToken);
      if (epoch != _sessionEpoch) return null;
      final storedToken = await _secure.read(key: 'refresh_token');
      if (storedToken != refreshToken) return null;
      await _applyTokens(data);
      notifyListeners();
      return api.accessToken;
    } on DioException catch (exception) {
      final status = exception.response?.statusCode;
      if (status == 401 || status == 403) {
        if (epoch != _sessionEpoch) return null;
        final storedToken = await _secure.read(key: 'refresh_token');
        if (storedToken != refreshToken) return null;
        await _clearStoredSession();
        api.accessToken = null;
        userId = null;
        accountUsername = null;
        username = null;
        localMode = true;
        await store.switchScope(LocalStore.localScope);
        await reload();
        notifyListeners();
        return null;
      }
      rethrow;
    }
  }

  Future<bool> login(String identity, String password) async {
    return _auth(() => api.login(identity, password));
  }

  Future<bool> register(
    String email,
    String user,
    String display,
    String password,
  ) async {
    return _auth(
      () => api.register(
        email: email,
        username: user,
        displayName: display,
        password: password,
      ),
    );
  }

  Future<bool> requestPasswordReset(String identity) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await api.requestPasswordReset(identity);
      return true;
    } catch (exception) {
      error = _friendly(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> resetPassword({
    required String identity,
    required String code,
    required String newPassword,
  }) async {
    return _auth(
      () => api.confirmPasswordReset(
        identity: identity,
        code: code,
        newPassword: newPassword,
      ),
    );
  }

  Future<bool> _auth(Future<Map<String, dynamic>> Function() request) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _applyTokens(await request());
      busy = false;
      notifyListeners();
      await sync();
      return true;
    } catch (exception) {
      error = _friendly(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> useLocally() async {
    localMode = true;
    error = null;
    syncState = 'Solo en este dispositivo';
    await store.switchScope(LocalStore.localScope);
    await reload();
    notifyListeners();
  }

  Future<bool> importLocalProjects() async {
    if (userId == null || localMode) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await store.switchScope(_accountScope(userId!), claimLocalData: true);
      localProjectsAvailable = 0;
      await reload();
      busy = false;
      notifyListeners();
      await sync();
      return true;
    } catch (exception) {
      error = _friendly(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _sessionEpoch += 1;
    api.accessToken = null;
    userId = null;
    accountUsername = null;
    username = null;
    localMode = true;
    syncState = 'Solo en este dispositivo';
    await _clearStoredSession();
    await store.switchScope(LocalStore.localScope);
    await reload();
    notifyListeners();
  }

  Future<bool> configureServer(String rawValue) async {
    var value = rawValue.trim();
    if (value.isEmpty) {
      error = 'Escribe la dirección del servidor.';
      notifyListeners();
      return false;
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    value = value.replaceAll(RegExp(r'/+$'), '');
    if (!value.endsWith('/api/v1')) {
      value = '$value/api/v1';
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!await api.checkServer(value)) {
        throw Exception('health check failed');
      }
      final serverChanged = value != serverBaseUrl;
      if (serverChanged && !localMode) {
        _sessionEpoch += 1;
        api.accessToken = null;
        userId = null;
        accountUsername = null;
        username = null;
        localMode = true;
        await _clearStoredSession();
        await store.switchScope(LocalStore.localScope);
        await reload();
      }
      serverBaseUrl = value;
      api.setBaseUrl(value);
      await _secure.write(key: 'server_url', value: value);
      syncState = localMode
          ? 'Servidor disponible'
          : 'Pendiente de sincronizar';
      return true;
    } catch (_) {
      error =
          'No se pudo conectar. Confirma la IP, el puerto 8000 y la misma red.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _accountScope(String id) => '$serverBaseUrl|$id';

  Future<WritingProject> createProject(
    String title,
    String synopsis,
    String type,
  ) async {
    final project = WritingProject(
      clientId: _uuid.v4(),
      title: title,
      synopsis: synopsis,
      workType: type,
      updatedAt: DateTime.now().toUtc(),
    );
    await store.saveProject(project);
    await reload();
    if (!localMode) await sync();
    return projects.firstWhere(
      (item) => item.clientId == project.clientId,
      orElse: () => project,
    );
  }

  Future<WritingDocument> createDocument(
    String projectClientId,
    String title,
  ) async {
    final document = WritingDocument(
      clientId: _uuid.v4(),
      projectClientId: projectClientId,
      title: title,
      content: '',
      position: documentsByProject[projectClientId]?.length ?? 0,
      updatedAt: DateTime.now().toUtc(),
    );
    await store.saveDocument(document);
    await reload();
    if (!localMode) await sync();
    return findDocument(document.clientId) ?? document;
  }

  Future<WritingDocument> saveDocument(
    WritingDocument current,
    String content,
  ) async {
    final updated = WritingDocument(
      clientId: current.clientId,
      projectClientId: current.projectClientId,
      serverId: current.serverId,
      title: current.title,
      content: content,
      kind: current.kind,
      position: current.position,
      revision: current.revision,
      syncState: 'pending',
      updatedAt: DateTime.now().toUtc(),
    );
    await store.saveDocument(updated);
    final documents = documentsByProject.putIfAbsent(
      updated.projectClientId,
      () => [],
    );
    final index = documents.indexWhere(
      (document) => document.clientId == updated.clientId,
    );
    if (index == -1) {
      documents.add(updated);
    } else {
      documents[index] = updated;
    }
    pendingCount = await store.pendingCount();
    syncState = localMode
        ? 'Guardado en este dispositivo'
        : 'Cambios pendientes';
    notifyListeners();
    return updated;
  }

  Future<bool> sync() async {
    if (localMode || busy) return false;
    if (api.accessToken == null) {
      try {
        if (await _refreshAccessToken() == null) return false;
      } catch (exception) {
        error = _friendly(exception);
        syncState = 'Sesión guardada · sin conexión';
        notifyListeners();
        return false;
      }
    }
    busy = true;
    syncState = 'Sincronizando…';
    error = null;
    notifyListeners();
    var completed = false;
    try {
      var conflicts = false;
      var batches = 0;
      while (batches < 25) {
        final changes = await store.pending(limit: 200);
        final response = await api.sync(changes, null);
        final result = await _applySyncResponse(changes, response);
        conflicts = conflicts || result.conflicts;
        batches += 1;
        if (changes.isEmpty || await store.pendingCount() == 0) {
          break;
        }
      }
      final remaining = await store.pendingCount();
      final blocked = await store.conflictCount();
      syncState = conflicts || blocked > 0
          ? 'Conflicto: tu versión local sigue conservada'
          : remaining == 0
          ? 'Todo sincronizado'
          : '$remaining cambios pendientes de otra sincronización';
      completed = !conflicts && blocked == 0 && remaining == 0;
      await reload();
    } catch (exception) {
      error = _friendly(exception);
      syncState = 'Sin conexión · los cambios están seguros';
    } finally {
      busy = false;
      pendingCount = await store.pendingCount();
      notifyListeners();
    }
    return completed;
  }

  Future<({bool conflicts, bool accepted})> _applySyncResponse(
    List<Map<String, Object?>> changes,
    Map<String, dynamic> response,
  ) async {
    final sentPayloads = <String, Map<String, Object?>>{
      for (final change in changes)
        '${change['entity']}:${change['client_id']}': (change['payload'] as Map)
            .cast<String, Object?>(),
    };
    final rawConflicts = (response['conflicts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final conflictKeys = <String>{
      for (final raw in rawConflicts) '${raw['entity']}:${raw['client_id']}',
    };
    var acceptedAny = false;
    for (final raw
        in (response['accepted'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      final entity = raw['entity'] as String;
      final clientId = raw['client_id'] as String;
      final payload = sentPayloads['$entity:$clientId'];
      if (payload != null) {
        acceptedAny =
            await store.acceptIfUnchanged(entity, clientId, payload) ||
            acceptedAny;
      }
    }
    for (final raw in rawConflicts) {
      await store.markConflict(
        raw['entity'] as String,
        raw['client_id'] as String,
        serverRevision: raw['server_revision'] as int?,
      );
    }
    final stillPending = await store.pendingKeys();
    final remoteProjects = response['projects'] as List<dynamic>;
    for (final raw in remoteProjects.cast<Map<String, dynamic>>()) {
      final key = 'project:${raw['client_id']}';
      if (stillPending.contains(key) || conflictKeys.contains(key)) continue;
      await store.saveProject(
        WritingProject(
          clientId: raw['client_id'] as String,
          serverId: raw['id'] as String,
          title: raw['title'] as String,
          synopsis: raw['synopsis'] as String? ?? '',
          workType: raw['work_type'] as String? ?? 'free',
          color: raw['color'] as String? ?? '#1E5B57',
          revision: raw['revision'] as int,
          syncState: 'synced',
          updatedAt: DateTime.parse(raw['updated_at'] as String),
        ),
        enqueue: false,
      );
    }
    final knownProjects = await store.projects();
    final projectByServer = {
      for (final project in knownProjects)
        if (project.serverId != null) project.serverId!: project.clientId,
    };
    final remoteDocuments = response['documents'] as List<dynamic>;
    for (final raw in remoteDocuments.cast<Map<String, dynamic>>()) {
      final key = 'document:${raw['client_id']}';
      if (stillPending.contains(key) || conflictKeys.contains(key)) continue;
      final projectClientId = projectByServer[raw['project_id'] as String];
      if (projectClientId == null) continue;
      await store.saveDocument(
        WritingDocument(
          clientId: raw['client_id'] as String,
          projectClientId: projectClientId,
          serverId: raw['id'] as String,
          title: raw['title'] as String,
          content: raw['content'] as String? ?? '',
          kind: raw['kind'] as String? ?? 'chapter',
          position: raw['position'] as int? ?? 0,
          revision: raw['revision'] as int,
          syncState: 'synced',
          updatedAt: DateTime.parse(raw['updated_at'] as String),
        ),
        enqueue: false,
      );
    }
    return (conflicts: rawConflicts.isNotEmpty, accepted: acceptedAny);
  }

  Future<bool> resolveConflictsKeepingLocal() async {
    if (localMode || conflictCount == 0) return false;
    await store.unblockConflicts();
    await reload();
    syncState = 'Preparando tu copia local para sincronizar…';
    notifyListeners();
    return sync();
  }

  WritingDocument? findDocument(String clientId) {
    for (final documents in documentsByProject.values) {
      for (final document in documents) {
        if (document.clientId == clientId) return document;
      }
    }
    return null;
  }

  List<WritingDocument> get allDocuments =>
      documentsByProject.values.expand((items) => items).toList();

  int get totalWordCount =>
      allDocuments.fold(0, (total, document) => total + document.wordCount);

  String get mostFrequentWord {
    const ignored = {
      'para',
      'como',
      'pero',
      'porque',
      'desde',
      'hasta',
      'sobre',
      'entre',
      'cuando',
      'donde',
      'este',
      'esta',
      'estos',
      'estas',
      'ella',
      'ellos',
      'todo',
      'todos',
      'toda',
      'todas',
      'unas',
      'unos',
      'del',
      'las',
      'los',
      'una',
      'uno',
      'que',
      'con',
      'por',
      'sin',
      'sus',
      'más',
    };
    final counts = <String, int>{};
    for (final document in allDocuments) {
      final words = document.content
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-záéíóúüñ0-9\s]'), ' ')
          .split(RegExp(r'\s+'));
      for (final word in words) {
        if (word.length < 4 || ignored.contains(word)) continue;
        counts[word] = (counts[word] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return '—';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<WritingProject> searchProjects(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return [];
    return projects
        .where(
          (project) =>
              project.title.toLowerCase().contains(normalized) ||
              project.synopsis.toLowerCase().contains(normalized),
        )
        .toList();
  }

  List<WritingDocument> searchDocuments(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return [];
    return allDocuments
        .where(
          (document) =>
              document.title.toLowerCase().contains(normalized) ||
              document.content.toLowerCase().contains(normalized),
        )
        .toList();
  }

  Future<List<dynamic>> loadInbox() async {
    if (localMode || api.accessToken == null) return [];
    try {
      return await api.inbox();
    } catch (exception) {
      error = _friendly(exception);
      notifyListeners();
      return [];
    }
  }

  String _friendly(Object exception) {
    if (exception is DioException) {
      final status = exception.response?.statusCode;
      if (status == 401) {
        return 'El correo, usuario o contraseña no son correctos.';
      }
      if (status == 409) {
        return 'El correo o el nombre de usuario ya están registrados.';
      }
      if (status == 403) {
        return 'No tienes permiso para realizar esta acción.';
      }
      if (status == 404) {
        return 'El contenido ya no está disponible.';
      }
      if (status == 413) {
        return 'El texto o archivo supera el tamaño permitido.';
      }
      if (status == 429) {
        return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
      }
      if (status == 400) {
        final detail = exception.response?.data is Map
            ? (exception.response!.data as Map)['detail']
            : null;
        if (detail is String && detail.trim().isNotEmpty) return detail;
      }
      if (status == 422) {
        final detail = exception.response?.data is Map
            ? (exception.response!.data as Map)['detail']
            : null;
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          final validation = detail.first as Map;
          final location = validation['loc'];
          final field = location is List && location.isNotEmpty
              ? location.last.toString()
              : '';
          return switch (field) {
            'email' => 'El correo no tiene un formato válido.',
            'username' =>
              'El usuario debe tener entre 3 y 40 caracteres: letras sin '
                  'tilde, números, punto, guion o guion bajo.',
            'display_name' =>
              'El nombre visible debe tener entre 1 y 100 caracteres.',
            'password' => 'La contraseña debe tener entre 10 y 128 caracteres.',
            'accepted_terms' =>
              'Debes aceptar las condiciones para crear la cuenta.',
            _ => 'Revisa los datos marcados e intenta nuevamente.',
          };
        }
        if (detail is String && detail.trim().isNotEmpty) {
          return detail;
        }
        return 'Revisa los datos marcados e intenta nuevamente.';
      }
      if (status != null && status >= 500) {
        return 'El servidor tuvo un problema. Inténtalo nuevamente.';
      }
      if (exception.type == DioExceptionType.connectionError ||
          exception.type == DioExceptionType.connectionTimeout ||
          exception.type == DioExceptionType.receiveTimeout ||
          exception.type == DioExceptionType.sendTimeout) {
        return 'No se pudo conectar con $serverBaseUrl. '
            'Revisa la red o configura otra dirección.';
      }
    }
    return 'No se pudo completar la acción. Tus cambios locales siguen seguros.';
  }
}
