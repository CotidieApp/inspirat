import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class LocalStore {
  LocalStore({this.databasePath});

  static const localScope = 'local';

  final String? databasePath;
  Database? _db;
  String _activeScope = localScope;
  Database get db => _db!;
  String get activeScope => _activeScope;

  Future<void> open() async {
    final path =
        databasePath ?? p.join(await getDatabasesPath(), 'inspirat.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE projects(
            client_id TEXT PRIMARY KEY, server_id TEXT, title TEXT NOT NULL,
            synopsis TEXT NOT NULL DEFAULT '', work_type TEXT NOT NULL,
            color TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 1,
            sync_state TEXT NOT NULL, updated_at TEXT NOT NULL,
            owner_scope TEXT NOT NULL DEFAULT 'local'
          )
        ''');
        await database.execute('''
          CREATE TABLE documents(
            client_id TEXT PRIMARY KEY, project_client_id TEXT NOT NULL,
            server_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL,
            kind TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0,
            revision INTEGER NOT NULL DEFAULT 1, sync_state TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            owner_scope TEXT NOT NULL DEFAULT 'local',
            FOREIGN KEY(project_client_id) REFERENCES projects(client_id)
          )
        ''');
        await database.execute('''
          CREATE TABLE pending(
            key TEXT PRIMARY KEY, entity TEXT NOT NULL, client_id TEXT NOT NULL,
            operation TEXT NOT NULL, payload TEXT NOT NULL,
            base_revision INTEGER, created_at TEXT NOT NULL,
            owner_scope TEXT NOT NULL DEFAULT 'local',
            blocked INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await database.execute(
          'CREATE INDEX document_project_idx ON documents(project_client_id, position)',
        );
        await database.execute(
          'CREATE INDEX project_owner_idx ON projects(owner_scope, updated_at)',
        );
        await database.execute(
          'CREATE INDEX pending_owner_idx ON pending(owner_scope, created_at)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE projects ADD COLUMN owner_scope TEXT NOT NULL DEFAULT 'local'",
          );
          await database.execute(
            "ALTER TABLE documents ADD COLUMN owner_scope TEXT NOT NULL DEFAULT 'local'",
          );
          await database.execute(
            "ALTER TABLE pending ADD COLUMN owner_scope TEXT NOT NULL DEFAULT 'local'",
          );
          await database.execute("UPDATE pending SET key = 'local:' || key");
          await database.execute(
            'CREATE INDEX project_owner_idx ON projects(owner_scope, updated_at)',
          );
          await database.execute(
            'CREATE INDEX pending_owner_idx ON pending(owner_scope, created_at)',
          );
        }
        if (oldVersion < 3) {
          await database.execute(
            'ALTER TABLE pending ADD COLUMN blocked INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> switchScope(String scope, {bool claimLocalData = false}) async {
    if (claimLocalData && scope != localScope) {
      await db.transaction((transaction) async {
        await transaction.update(
          'projects',
          {'owner_scope': scope},
          where: 'owner_scope = ?',
          whereArgs: [localScope],
        );
        await transaction.update(
          'documents',
          {'owner_scope': scope},
          where: 'owner_scope = ?',
          whereArgs: [localScope],
        );
        final localPending = await transaction.query(
          'pending',
          columns: ['entity', 'client_id'],
          where: 'owner_scope = ?',
          whereArgs: [localScope],
        );
        for (final row in localPending) {
          await transaction.update(
            'pending',
            {
              'key': '$scope:${row['entity']}:${row['client_id']}',
              'owner_scope': scope,
            },
            where: 'owner_scope = ? AND entity = ? AND client_id = ?',
            whereArgs: [localScope, row['entity'], row['client_id']],
          );
        }
      });
    }
    _activeScope = scope;
  }

  Future<int> projectCount({String? scope}) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM projects WHERE owner_scope = ?',
      [scope ?? _activeScope],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<WritingProject>> projects() async => (await db.query(
    'projects',
    where: 'owner_scope = ?',
    whereArgs: [_activeScope],
    orderBy: 'updated_at DESC',
  )).map(WritingProject.fromMap).toList();

  Future<List<WritingDocument>> documents(String projectClientId) async =>
      (await db.query(
        'documents',
        where: 'project_client_id = ? AND owner_scope = ?',
        whereArgs: [projectClientId, _activeScope],
        orderBy: 'position, updated_at',
      )).map(WritingDocument.fromMap).toList();

  Future<WritingDocument?> document(String clientId) async {
    final rows = await db.query(
      'documents',
      where: 'client_id = ? AND owner_scope = ?',
      whereArgs: [clientId, _activeScope],
      limit: 1,
    );
    return rows.isEmpty ? null : WritingDocument.fromMap(rows.first);
  }

  Future<void> saveProject(
    WritingProject project, {
    bool enqueue = true,
  }) async {
    await db.transaction((transaction) async {
      await _upsert(transaction, 'projects', 'client_id', project.clientId, {
        ...project.toMap(),
        'owner_scope': _activeScope,
      });
      if (enqueue) {
        await _enqueue(
          'project',
          project.clientId,
          {
            'title': project.title,
            'synopsis': project.synopsis,
            'work_type': project.workType,
            'status': 'draft',
            'color': project.color,
          },
          project.serverId == null ? null : project.revision,
          executor: transaction,
        );
      }
    });
  }

  Future<void> saveDocument(
    WritingDocument document, {
    bool enqueue = true,
  }) async {
    await db.transaction((transaction) async {
      await _upsert(transaction, 'documents', 'client_id', document.clientId, {
        ...document.toMap(),
        'owner_scope': _activeScope,
      });
      if (enqueue) {
        await _enqueue(
          'document',
          document.clientId,
          {
            'project_client_id': document.projectClientId,
            'title': document.title,
            'content': document.content,
            'kind': document.kind,
            'position': document.position,
          },
          document.serverId == null ? null : document.revision,
          executor: transaction,
        );
      }
    });
  }

  Future<void> _upsert(
    DatabaseExecutor executor,
    String table,
    String keyColumn,
    String key,
    Map<String, Object?> values,
  ) async {
    final updated = await executor.update(
      table,
      values,
      where: '$keyColumn = ? AND owner_scope = ?',
      whereArgs: [key, _activeScope],
    );
    if (updated == 0) {
      await executor.insert(table, values);
    }
  }

  Future<void> _enqueue(
    String entity,
    String clientId,
    Map<String, Object?> payload,
    int? baseRevision, {
    DatabaseExecutor? executor,
  }) => (executor ?? db).insert('pending', {
    'key': '$_activeScope:$entity:$clientId',
    'entity': entity,
    'client_id': clientId,
    'operation': 'upsert',
    'payload': jsonEncode(payload),
    'base_revision': baseRevision,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'owner_scope': _activeScope,
    'blocked': 0,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, Object?>>> pending({int limit = 200}) async {
    final rows = await db.query(
      'pending',
      where: 'owner_scope = ? AND blocked = 0',
      whereArgs: [_activeScope],
      orderBy: 'created_at',
      limit: limit,
    );
    return rows
        .map(
          (row) => {
            'entity': row['entity'],
            'operation': row['operation'],
            'client_id': row['client_id'],
            'payload': jsonDecode(row['payload']! as String),
            'base_revision': row['base_revision'],
          },
        )
        .toList();
  }

  Future<int> pendingCount() async {
    final scopedResult = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM pending '
      'WHERE owner_scope = ? AND blocked = 0',
      [_activeScope],
    );
    return Sqflite.firstIntValue(scopedResult) ?? 0;
  }

  Future<int> conflictCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM pending '
      'WHERE owner_scope = ? AND blocked = 1',
      [_activeScope],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Set<String>> pendingKeys() async {
    final rows = await db.query(
      'pending',
      columns: ['entity', 'client_id'],
      where: 'owner_scope = ?',
      whereArgs: [_activeScope],
    );
    return {for (final row in rows) '${row['entity']}:${row['client_id']}'};
  }

  Future<bool> acceptIfUnchanged(
    String entity,
    String clientId,
    Map<String, Object?> sentPayload,
  ) async {
    final key = '$_activeScope:$entity:$clientId';
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'pending',
        columns: ['payload'],
        where: 'key = ? AND owner_scope = ?',
        whereArgs: [key, _activeScope],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final currentPayload = jsonDecode(rows.first['payload']! as String);
      if (jsonEncode(currentPayload) != jsonEncode(sentPayload)) return false;
      return await transaction.delete(
            'pending',
            where: 'key = ? AND owner_scope = ?',
            whereArgs: [key, _activeScope],
          ) >
          0;
    });
  }

  Future<void> markConflict(
    String entity,
    String clientId, {
    int? serverRevision,
  }) async {
    final table = entity == 'project' ? 'projects' : 'documents';
    await db.transaction((transaction) async {
      await transaction.update(
        table,
        {'sync_state': 'conflict', 'revision': ?serverRevision},
        where: 'client_id = ? AND owner_scope = ?',
        whereArgs: [clientId, _activeScope],
      );
      await transaction.update(
        'pending',
        {'blocked': 1, 'base_revision': ?serverRevision},
        where: 'entity = ? AND client_id = ? AND owner_scope = ?',
        whereArgs: [entity, clientId, _activeScope],
      );
    });
  }

  Future<void> unblockConflicts() async {
    await db.update(
      'pending',
      {'blocked': 0},
      where: 'owner_scope = ? AND blocked = 1',
      whereArgs: [_activeScope],
    );
  }
}
