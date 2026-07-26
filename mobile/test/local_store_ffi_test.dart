import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspirat/data/local_store.dart';
import 'package:inspirat/data/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  final openStores = <LocalStore>[];
  Database? legacyDatabase;

  Future<LocalStore> openStore() async {
    final store = LocalStore(databasePath: databasePath);
    await store.open();
    openStores.add(store);
    return store;
  }

  Future<void> closeStore(LocalStore store) async {
    await store.close();
    openStores.remove(store);
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'inspirat_local_store_',
    );
    databasePath = p.join(temporaryDirectory.path, 'inspirat.db');
  });

  tearDown(() async {
    await legacyDatabase?.close();
    legacyDatabase = null;
    for (final store in openStores.reversed.toList()) {
      await store.close();
    }
    openStores.clear();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'persists projects, documents and pending work after reopening',
    () async {
      var store = await openStore();
      final project = sampleProject(
        clientId: 'persisted-project',
        title: 'A persistent story',
      );
      final document = sampleDocument(
        clientId: 'persisted-document',
        projectClientId: project.clientId,
        content: 'This paragraph must survive a complete database reopening.',
      );

      await store.saveProject(project);
      await store.saveDocument(document);

      expect(await store.pendingCount(), 2);
      await closeStore(store);

      store = await openStore();
      final reopenedProjects = await store.projects();
      final reopenedDocuments = await store.documents(project.clientId);
      final reopenedPending = await store.pending();

      expect(reopenedProjects, hasLength(1));
      expect(reopenedProjects.single.clientId, project.clientId);
      expect(reopenedProjects.single.title, project.title);
      expect(reopenedDocuments, hasLength(1));
      expect(reopenedDocuments.single.clientId, document.clientId);
      expect(reopenedDocuments.single.content, document.content);
      expect(reopenedPending, hasLength(2));
      expect(
        reopenedPending.map((row) => row['client_id']),
        containsAll(<String>[project.clientId, document.clientId]),
      );
    },
  );

  test(
    'keeps projects, documents and queues isolated by owner scope',
    () async {
      final store = await openStore();
      final localProject = sampleProject(clientId: 'local-project');
      final localDocument = sampleDocument(
        clientId: 'local-document',
        projectClientId: localProject.clientId,
        content: 'Local-only draft.',
      );
      await store.saveProject(localProject);
      await store.saveDocument(localDocument);

      await store.switchScope('account:alice');
      expect(await store.projects(), isEmpty);
      expect(await store.pending(), isEmpty);

      final aliceProject = sampleProject(clientId: 'alice-project');
      final aliceDocument = sampleDocument(
        clientId: 'alice-document',
        projectClientId: aliceProject.clientId,
        content: 'Alice-only draft.',
      );
      await store.saveProject(aliceProject);
      await store.saveDocument(aliceDocument);

      expect(
        (await store.projects()).map((project) => project.clientId),
        <String>[aliceProject.clientId],
      );
      expect(await store.pendingCount(), 2);

      await store.switchScope(LocalStore.localScope);
      expect(
        (await store.projects()).map((project) => project.clientId),
        <String>[localProject.clientId],
      );
      expect(
        (await store.documents(
          localProject.clientId,
        )).map((document) => document.clientId),
        <String>[localDocument.clientId],
      );
      expect(await store.documents(aliceProject.clientId), isEmpty);
      expect(await store.pendingCount(), 2);

      await store.switchScope('account:bob');
      expect(await store.projects(), isEmpty);
      expect(await store.pendingCount(), 0);
    },
  );

  test('imports local data only when explicitly requested', () async {
    final store = await openStore();
    final project = sampleProject(clientId: 'import-project');
    final document = sampleDocument(
      clientId: 'import-document',
      projectClientId: project.clientId,
      content: 'Draft waiting for an explicit account import.',
    );
    await store.saveProject(project);
    await store.saveDocument(document);

    await store.switchScope('account:writer');
    expect(await store.projects(), isEmpty);
    expect(await store.pendingCount(), 0);
    expect(
      await store.projectCount(scope: LocalStore.localScope),
      1,
      reason: 'Switching accounts must not claim local work implicitly.',
    );

    await store.switchScope('account:writer', claimLocalData: true);

    expect((await store.projects()).map((item) => item.clientId), <String>[
      project.clientId,
    ]);
    expect(
      (await store.documents(project.clientId)).single.content,
      document.content,
    );
    expect(await store.pendingCount(), 2);
    expect(await store.projectCount(scope: LocalStore.localScope), 0);

    final importedQueue = await store.db.query(
      'pending',
      columns: <String>['key', 'owner_scope'],
      orderBy: 'key',
    );
    expect(importedQueue.map((row) => row['key']), <String>[
      'account:writer:document:${document.clientId}',
      'account:writer:project:${project.clientId}',
    ]);
    expect(importedQueue.map((row) => row['owner_scope']).toSet(), <Object?>{
      'account:writer',
    });

    await store.switchScope(LocalStore.localScope);
    expect(await store.projects(), isEmpty);
    expect(await store.pendingCount(), 0);
  });

  test('blocks conflicted work without deleting its pending record', () async {
    var store = await openStore();
    final project = sampleProject(clientId: 'conflict-project');
    final document = sampleDocument(
      clientId: 'conflict-document',
      projectClientId: project.clientId,
      content: 'A locally edited version.',
    );
    await store.saveProject(project, enqueue: false);
    await store.saveDocument(document);

    expect(await store.pendingCount(), 1);
    expect(await store.conflictCount(), 0);

    await store.markConflict('document', document.clientId, serverRevision: 7);

    expect((await store.document(document.clientId))?.syncState, 'conflict');
    expect((await store.document(document.clientId))?.revision, 7);
    expect(await store.pending(), isEmpty);
    expect(await store.pendingCount(), 0);
    expect(await store.conflictCount(), 1);
    expect(
      await store.pendingKeys(),
      <String>{'document:${document.clientId}'},
      reason: 'A blocked item must remain recoverable and inspectable.',
    );

    final blockedRows = await store.db.query(
      'pending',
      columns: <String>['blocked', 'base_revision'],
      where: 'client_id = ?',
      whereArgs: <Object?>[document.clientId],
    );
    expect(blockedRows.single['blocked'], 1);
    expect(blockedRows.single['base_revision'], 7);

    await closeStore(store);
    store = await openStore();
    expect((await store.document(document.clientId))?.syncState, 'conflict');
    expect(await store.pendingCount(), 0);
    expect(await store.conflictCount(), 1);

    await store.unblockConflicts();
    expect(await store.pendingCount(), 1);
    expect(await store.conflictCount(), 0);
    expect((await store.pending()).single['base_revision'], 7);
  });

  test('migrates a real SQLite database from version 1 to version 3', () async {
    legacyDatabase = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE projects(
            client_id TEXT PRIMARY KEY, server_id TEXT, title TEXT NOT NULL,
            synopsis TEXT NOT NULL DEFAULT '', work_type TEXT NOT NULL,
            color TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 1,
            sync_state TEXT NOT NULL, updated_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE documents(
            client_id TEXT PRIMARY KEY, project_client_id TEXT NOT NULL,
            server_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL,
            kind TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0,
            revision INTEGER NOT NULL DEFAULT 1, sync_state TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(project_client_id) REFERENCES projects(client_id)
          )
        ''');
        await database.execute('''
          CREATE TABLE pending(
            key TEXT PRIMARY KEY, entity TEXT NOT NULL, client_id TEXT NOT NULL,
            operation TEXT NOT NULL, payload TEXT NOT NULL,
            base_revision INTEGER, created_at TEXT NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX document_project_idx '
          'ON documents(project_client_id, position)',
        );
      },
    );

    final timestamp = DateTime.utc(2026, 7, 26).toIso8601String();
    await legacyDatabase!.insert('projects', <String, Object?>{
      'client_id': 'legacy-project',
      'server_id': null,
      'title': 'Legacy project',
      'synopsis': '',
      'work_type': 'free',
      'color': '#1E5B57',
      'revision': 1,
      'sync_state': 'pending',
      'updated_at': timestamp,
    });
    await legacyDatabase!.insert('documents', <String, Object?>{
      'client_id': 'legacy-document',
      'project_client_id': 'legacy-project',
      'server_id': null,
      'title': 'Legacy chapter',
      'content': 'Text written before scoped storage existed.',
      'kind': 'chapter',
      'position': 0,
      'revision': 1,
      'sync_state': 'pending',
      'updated_at': timestamp,
    });
    await legacyDatabase!.insert('pending', <String, Object?>{
      'key': 'document:legacy-document',
      'entity': 'document',
      'client_id': 'legacy-document',
      'operation': 'upsert',
      'payload': '{"content":"Text written before scoped storage existed."}',
      'base_revision': null,
      'created_at': timestamp,
    });
    await legacyDatabase!.close();
    legacyDatabase = null;

    final store = await openStore();

    expect(
      Sqflite.firstIntValue(await store.db.rawQuery('PRAGMA user_version')),
      3,
    );
    expect((await store.projects()).single.clientId, 'legacy-project');
    expect(
      (await store.documents('legacy-project')).single.clientId,
      'legacy-document',
    );
    expect(await store.pendingCount(), 1);

    final projectColumns = await store.db.rawQuery(
      'PRAGMA table_info(projects)',
    );
    final documentColumns = await store.db.rawQuery(
      'PRAGMA table_info(documents)',
    );
    final pendingColumns = await store.db.rawQuery(
      'PRAGMA table_info(pending)',
    );
    expect(
      projectColumns.map((column) => column['name']),
      contains('owner_scope'),
    );
    expect(
      documentColumns.map((column) => column['name']),
      contains('owner_scope'),
    );
    expect(
      pendingColumns.map((column) => column['name']),
      containsAll(<String>['owner_scope', 'blocked']),
    );

    final migratedPending = await store.db.query('pending');
    expect(migratedPending.single['key'], 'local:document:legacy-document');
    expect(migratedPending.single['owner_scope'], LocalStore.localScope);
    expect(migratedPending.single['blocked'], 0);

    final indexes = await store.db.query(
      'sqlite_master',
      columns: <String>['name'],
      where: "type = 'index'",
    );
    expect(
      indexes.map((row) => row['name']),
      containsAll(<String>[
        'document_project_idx',
        'project_owner_idx',
        'pending_owner_idx',
      ]),
    );

    await store.markConflict('document', 'legacy-document');
    expect(await store.pendingCount(), 0);
    expect(await store.conflictCount(), 1);
  });
}

WritingProject sampleProject({
  required String clientId,
  String title = 'Test project',
}) => WritingProject(
  clientId: clientId,
  title: title,
  updatedAt: DateTime.utc(2026, 7, 26),
);

WritingDocument sampleDocument({
  required String clientId,
  required String projectClientId,
  required String content,
}) => WritingDocument(
  clientId: clientId,
  projectClientId: projectClientId,
  title: 'Test chapter',
  content: content,
  updatedAt: DateTime.utc(2026, 7, 26),
);
