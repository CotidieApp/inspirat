int countWords(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

class WritingProject {
  const WritingProject({
    required this.clientId,
    required this.title,
    required this.updatedAt,
    this.serverId,
    this.synopsis = '',
    this.workType = 'free',
    this.color = '#1E5B57',
    this.revision = 1,
    this.syncState = 'pending',
  });

  final String clientId;
  final String? serverId;
  final String title;
  final String synopsis;
  final String workType;
  final String color;
  final int revision;
  final String syncState;
  final DateTime updatedAt;

  factory WritingProject.fromMap(Map<String, Object?> map) => WritingProject(
    clientId: map['client_id']! as String,
    serverId: map['server_id'] as String?,
    title: map['title']! as String,
    synopsis: (map['synopsis'] as String?) ?? '',
    workType: (map['work_type'] as String?) ?? 'free',
    color: (map['color'] as String?) ?? '#1E5B57',
    revision: (map['revision'] as int?) ?? 1,
    syncState: (map['sync_state'] as String?) ?? 'synced',
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'server_id': serverId,
    'title': title,
    'synopsis': synopsis,
    'work_type': workType,
    'color': color,
    'revision': revision,
    'sync_state': syncState,
    'updated_at': updatedAt.toIso8601String(),
  };
}

class WritingDocument {
  const WritingDocument({
    required this.clientId,
    required this.projectClientId,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.serverId,
    this.kind = 'chapter',
    this.position = 0,
    this.revision = 1,
    this.syncState = 'pending',
  });

  final String clientId;
  final String projectClientId;
  final String? serverId;
  final String title;
  final String content;
  final String kind;
  final int position;
  final int revision;
  final String syncState;
  final DateTime updatedAt;
  int get wordCount => countWords(content);

  factory WritingDocument.fromMap(Map<String, Object?> map) => WritingDocument(
    clientId: map['client_id']! as String,
    projectClientId: map['project_client_id']! as String,
    serverId: map['server_id'] as String?,
    title: map['title']! as String,
    content: (map['content'] as String?) ?? '',
    kind: (map['kind'] as String?) ?? 'chapter',
    position: (map['position'] as int?) ?? 0,
    revision: (map['revision'] as int?) ?? 1,
    syncState: (map['sync_state'] as String?) ?? 'synced',
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'project_client_id': projectClientId,
    'server_id': serverId,
    'title': title,
    'content': content,
    'kind': kind,
    'position': position,
    'revision': revision,
    'sync_state': syncState,
    'updated_at': updatedAt.toIso8601String(),
  };
}
