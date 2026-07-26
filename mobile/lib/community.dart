import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'app_controller.dart';
import 'core/theme.dart';
import 'data/models.dart';

class CommunityUser {
  const CommunityUser({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;

  factory CommunityUser.fromJson(Map<String, dynamic> json) => CommunityUser(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String,
  );
}

class CommunityDocument {
  const CommunityDocument({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;

  factory CommunityDocument.fromJson(Map<String, dynamic> json) =>
      CommunityDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String? ?? '',
      );
}

class CommunityMessage {
  const CommunityMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.createdAt,
    this.clientId,
    this.recipient,
    this.document,
    this.readAt,
  });

  final String id;
  final String? clientId;
  final CommunityUser sender;
  final CommunityUser? recipient;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final CommunityDocument? document;

  factory CommunityMessage.fromJson(Map<String, dynamic> json) {
    final document = json['document'];
    final recipient = json['recipient'];
    return CommunityMessage(
      id: json['id'] as String,
      clientId: json['client_id'] as String?,
      sender: CommunityUser.fromJson(
        (json['sender'] as Map).cast<String, dynamic>(),
      ),
      recipient: recipient is Map
          ? CommunityUser.fromJson(recipient.cast<String, dynamic>())
          : null,
      body: json['body'] as String? ?? '',
      document: document is Map
          ? CommunityDocument.fromJson(document.cast<String, dynamic>())
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
    );
  }
}

class ConversationPreview {
  const ConversationPreview({
    required this.user,
    required this.lastMessage,
    required this.unreadCount,
  });

  final CommunityUser user;
  final CommunityMessage lastMessage;
  final int unreadCount;

  factory ConversationPreview.fromJson(Map<String, dynamic> json) =>
      ConversationPreview(
        user: CommunityUser.fromJson(
          ((json['user'] ?? json['other_user']) as Map).cast<String, dynamic>(),
        ),
        lastMessage: CommunityMessage.fromJson(
          (json['last_message'] as Map).cast<String, dynamic>(),
        ),
        unreadCount: json['unread_count'] as int? ?? 0,
      );
}

Future<List<CommunityMessage>> _prependConfirmed(
  Future<List<CommunityMessage>> current,
  CommunityMessage confirmed,
) async {
  try {
    final items = await current;
    if (items.any(
      (message) =>
          message.id == confirmed.id ||
          (confirmed.clientId != null &&
              message.clientId == confirmed.clientId),
    )) {
      return items;
    }
    return [confirmed, ...items];
  } catch (_) {
    return [confirmed];
  }
}

class CommunityHub extends StatefulWidget {
  const CommunityHub({super.key, required this.controller});

  final AppController controller;

  @override
  State<CommunityHub> createState() => _CommunityHubState();
}

class _CommunityHubState extends State<CommunityHub>
    with WidgetsBindingObserver {
  late Future<_CommunityOverview> overview = load();
  Timer? polling;
  bool refreshing = false;
  bool appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    polling = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    polling?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (appActive) unawaited(refresh(silent: true));
  }

  Future<_CommunityOverview> load() async {
    final results = await Future.wait([
      widget.controller.api.generalMessages(limit: 1),
      widget.controller.api.conversations(),
    ]);
    return _CommunityOverview(
      general: results[0]
          .cast<Map<String, dynamic>>()
          .map(CommunityMessage.fromJson)
          .toList(),
      conversations: results[1]
          .cast<Map<String, dynamic>>()
          .map(ConversationPreview.fromJson)
          .toList(),
    );
  }

  Future<void> refresh({bool silent = false}) async {
    if (refreshing || !appActive) return;
    refreshing = true;
    try {
      final data = await load();
      if (mounted) {
        setState(() {
          overview = Future.value(data);
        });
      }
    } catch (_) {
      if (!silent) rethrow;
    } finally {
      refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.localMode ||
        widget.controller.api.accessToken == null) {
      return const _CommunityUnavailable();
    }
    return FutureBuilder<_CommunityOverview>(
      future: overview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CommunityError(onRetry: refresh);
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              Text(
                'Mensajes y comunidad',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Los mensajes directos son privados. Publicar en el chat '
                'grupal hace visible ese texto para todas las cuentas.',
              ),
              const SizedBox(height: 16),
              Card(
                color: InspiratTheme.petrol.withValues(alpha: .12),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: InspiratTheme.petrol,
                    child: Icon(Icons.groups_2_outlined, color: Colors.white),
                  ),
                  title: const Row(
                    children: [
                      Expanded(child: Text('Chat grupal · inspiraT')),
                      Icon(Icons.push_pin_outlined, size: 18),
                    ],
                  ),
                  subtitle: Text(_generalPreview(data.general)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/community'),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Conversaciones',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _chooseUser(context),
                    icon: const Icon(Icons.edit_square),
                    label: const Text('Nuevo'),
                  ),
                ],
              ),
              if (data.conversations.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      Icon(Icons.forum_outlined, size: 48),
                      SizedBox(height: 12),
                      Text('Todavía no hay conversaciones directas.'),
                    ],
                  ),
                )
              else
                ...data.conversations.map(
                  (conversation) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(_initials(conversation.user.displayName)),
                      ),
                      title: Text(conversation.user.displayName),
                      subtitle: Text(
                        _messagePreview(conversation.lastMessage),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: conversation.unreadCount > 0
                          ? Badge(label: Text('${conversation.unreadCount}'))
                          : const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                        '/messages/${conversation.user.id}',
                        extra: conversation.user,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _chooseUser(BuildContext context) async {
    final selected = await showModalBottomSheet<CommunityUser>(
      context: context,
      showDragHandle: true,
      builder: (context) => FutureBuilder<List<dynamic>>(
        future: widget.controller.api.communityUsers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return const SizedBox(
                height: 260,
                child: Center(
                  child: Text(
                    'No se pudo cargar la lista de usuarios.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final users = snapshot.data!
              .cast<Map<String, dynamic>>()
              .map(CommunityUser.fromJson)
              .where((user) => user.id != widget.controller.userId)
              .toList();
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  'Nueva conversación',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...users.map(
                  (user) => ListTile(
                    leading: CircleAvatar(
                      child: Text(_initials(user.displayName)),
                    ),
                    title: Text(user.displayName),
                    subtitle: Text('@${user.username}'),
                    onTap: () => context.pop(user),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (selected != null && mounted && context.mounted) {
      await context.push('/messages/${selected.id}', extra: selected);
      if (mounted) await refresh();
    }
  }
}

class GeneralChatScreen extends StatefulWidget {
  const GeneralChatScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<GeneralChatScreen> createState() => _GeneralChatScreenState();
}

class _GeneralChatScreenState extends State<GeneralChatScreen>
    with WidgetsBindingObserver {
  late Future<List<CommunityMessage>> messages = load();
  Timer? polling;
  bool refreshing = false;
  bool appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    polling = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    polling?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (appActive) unawaited(refresh(silent: true));
  }

  Future<List<CommunityMessage>> load() async =>
      (await widget.controller.api.generalMessages(
        limit: 100,
      )).cast<Map<String, dynamic>>().map(CommunityMessage.fromJson).toList();

  Future<void> refresh({bool silent = false}) async {
    if (refreshing || !appActive) return;
    refreshing = true;
    try {
      final data = await load();
      if (mounted) {
        setState(() {
          messages = Future.value(data);
        });
      }
    } catch (_) {
      if (!silent) rethrow;
    } finally {
      refreshing = false;
    }
  }

  Future<void> send(String body, String clientId) async {
    try {
      final raw = await widget.controller.api.postGeneral(
        body: body,
        clientId: clientId,
      );
      _showConfirmed(CommunityMessage.fromJson(raw));
    } catch (error, stackTrace) {
      if (!await _reconcile(clientId)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    unawaited(refresh(silent: true));
  }

  void _showConfirmed(CommunityMessage confirmed) {
    if (!mounted) return;
    setState(() {
      messages = _prependConfirmed(messages, confirmed);
    });
  }

  Future<bool> _reconcile(String clientId) async {
    try {
      final rawMessages = await widget.controller.api.generalMessages(
        limit: 100,
      );
      final parsed = rawMessages
          .cast<Map<String, dynamic>>()
          .map(CommunityMessage.fromJson)
          .toList();
      if (!parsed.any((message) => message.clientId == clientId)) return false;
      if (mounted) {
        setState(() {
          messages = Future.value(parsed);
        });
      }
      return true;
    } catch (error) {
      debugPrint('No se pudo reconciliar el mensaje general: $error');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chat grupal · inspiraT'),
          Text(
            'Visible para todas las cuentas',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    ),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          color: InspiratTheme.champagne.withValues(alpha: .18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: const Text(
            'Sólo publica textos que quieras compartir con toda la comunidad.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: _MessageList(
            messages: messages,
            currentUserId: widget.controller.userId,
            onRefresh: refresh,
            general: true,
          ),
        ),
        MessageComposer(hint: 'Mensaje para la comunidad', onSend: send),
      ],
    ),
  );
}

class DirectChatScreen extends StatefulWidget {
  const DirectChatScreen({
    super.key,
    required this.controller,
    required this.userId,
    this.user,
  });

  final AppController controller;
  final String userId;
  final CommunityUser? user;

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen>
    with WidgetsBindingObserver {
  late Future<List<CommunityMessage>> messages = load();
  Timer? polling;
  bool refreshing = false;
  bool appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    polling = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    polling?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (appActive) unawaited(refresh(silent: true));
  }

  Future<List<CommunityMessage>> load() async {
    final result = (await widget.controller.api.directMessages(
      widget.userId,
      limit: 100,
    )).cast<Map<String, dynamic>>().map(CommunityMessage.fromJson).toList();
    unawaited(
      widget.controller.api
          .markConversationRead(widget.userId)
          .catchError((Object _) {}),
    );
    return result;
  }

  Future<void> refresh({bool silent = false}) async {
    if (refreshing || !appActive) return;
    refreshing = true;
    try {
      final data = await load();
      if (mounted) {
        setState(() {
          messages = Future.value(data);
        });
      }
    } catch (_) {
      if (!silent) rethrow;
    } finally {
      refreshing = false;
    }
  }

  Future<void> send(String body, String clientId) async {
    try {
      final raw = await widget.controller.api.sendDirectMessage(
        widget.userId,
        body: body,
        clientId: clientId,
      );
      _showConfirmed(CommunityMessage.fromJson(raw));
    } catch (error, stackTrace) {
      if (!await _reconcile(clientId)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    unawaited(refresh(silent: true));
  }

  void _showConfirmed(CommunityMessage confirmed) {
    if (!mounted) return;
    setState(() {
      messages = _prependConfirmed(messages, confirmed);
    });
  }

  Future<bool> _reconcile(String clientId) async {
    try {
      final rawMessages = await widget.controller.api.directMessages(
        widget.userId,
        limit: 100,
      );
      final parsed = rawMessages
          .cast<Map<String, dynamic>>()
          .map(CommunityMessage.fromJson)
          .toList();
      if (!parsed.any((message) => message.clientId == clientId)) return false;
      if (mounted) {
        setState(() {
          messages = Future.value(parsed);
        });
      }
      return true;
    } catch (error) {
      debugPrint('No se pudo reconciliar el mensaje directo: $error');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.user?.displayName ?? 'Conversación')),
    body: Column(
      children: [
        Expanded(
          child: _MessageList(
            messages: messages,
            currentUserId: widget.controller.userId,
            onRefresh: refresh,
            general: false,
          ),
        ),
        MessageComposer(hint: 'Escribe un mensaje', onSend: send),
      ],
    ),
  );
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.currentUserId,
    required this.onRefresh,
    required this.general,
  });

  final Future<List<CommunityMessage>> messages;
  final String? currentUserId;
  final Future<void> Function() onRefresh;
  final bool general;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CommunityMessage>>(
    future: messages,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _CommunityError(onRetry: onRefresh);
      }
      final items = snapshot.data!;
      if (items.isEmpty) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            children: const [
              SizedBox(height: 120),
              Icon(Icons.chat_bubble_outline, size: 52),
              SizedBox(height: 14),
              Text('Aún no hay mensajes.', textAlign: TextAlign.center),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final message = items[index];
            final own = message.sender.id == currentUserId;
            return Align(
              alignment: own ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: own
                      ? InspiratTheme.petrol.withValues(alpha: .18)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (general || !own)
                      Text(
                        message.sender.displayName,
                        style: const TextStyle(
                          color: InspiratTheme.petrol,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (message.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(message.body),
                    ],
                    if (message.document != null) ...[
                      const SizedBox(height: 8),
                      _StoryAttachment(document: message.document!),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      _time(message.createdAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _StoryAttachment extends StatelessWidget {
  const _StoryAttachment({required this.document});

  final CommunityDocument document;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            children: [
              Text(
                document.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Divider(height: 32),
              SelectableText(
                document.content,
                style: const TextStyle(fontSize: 18, height: 1.6),
              ),
            ],
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.auto_stories_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    document.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MessageComposer extends StatefulWidget {
  const MessageComposer({super.key, required this.hint, required this.onSend});

  final String hint;
  final Future<void> Function(String body, String clientId) onSend;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final controller = TextEditingController();
  bool sending = false;
  String? pendingBody;
  String? pendingClientId;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final body = controller.text.trim();
    if (body.isEmpty || sending) return;
    if (pendingBody != body || pendingClientId == null) {
      pendingBody = body;
      pendingClientId = const Uuid().v4();
    }
    setState(() => sending = true);
    try {
      await widget.onSend(body, pendingClientId!);
      controller.clear();
      pendingBody = null;
      pendingClientId = null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo confirmar el envío. El mensaje sigue aquí para '
              'reintentarlo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: widget.hint),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Enviar',
            onPressed: sending ? null : send,
            icon: sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    ),
  );
}

Future<bool> showPublishComposer(
  BuildContext context,
  AppController controller,
  WritingDocument document,
) async {
  if (controller.localMode || controller.api.accessToken == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inicia sesión para enviar o publicar.')),
    );
    return false;
  }
  if (document.serverId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sincroniza el capítulo antes de compartirlo.'),
      ),
    );
    return false;
  }

  final usersFuture = controller.api.communityUsers();
  var publishGeneral = false;
  var message = '';
  final recipients = <String>{};
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Enviar o publicar'),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<List<dynamic>>(
            future: usersFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                if (snapshot.hasError) {
                  return const SizedBox(
                    height: 240,
                    child: Center(
                      child: Text(
                        'No se pudo cargar la lista de usuarios.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final users = snapshot.data!
                  .cast<Map<String, dynamic>>()
                  .map(CommunityUser.fromJson)
                  .where((user) => user.id != controller.userId)
                  .toList();
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: publishGeneral,
                      onChanged: (value) =>
                          setState(() => publishGeneral = value),
                      title: const Text('Publicar en el chat general'),
                      subtitle: const Text(
                        'Todas las cuentas podrán leer el capítulo completo.',
                      ),
                    ),
                    const Divider(),
                    const Text(
                      'Enviar de forma privada a:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (users.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No hay otras cuentas disponibles.'),
                      )
                    else
                      ...users.map(
                        (user) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: recipients.contains(user.id),
                          onChanged: (selected) => setState(() {
                            if (selected == true) {
                              recipients.add(user.id);
                            } else {
                              recipients.remove(user.id);
                            }
                          }),
                          title: Text(user.displayName),
                          subtitle: Text('@${user.username}'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextFormField(
                      onChanged: (value) => message = value,
                      maxLength: 2000,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje opcional',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!publishGeneral && recipients.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Elige el chat general o algún destinatario.',
                    ),
                  ),
                );
                return;
              }
              dialogContext.pop(true);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true || !context.mounted) return false;

  final operationClientId = const Uuid().v4();
  while (context.mounted) {
    try {
      await controller.api.publishCommunity(
        clientId: operationClientId,
        body: message.trim(),
        documentId: document.serverId,
        publishGeneral: publishGeneral,
        recipientIds: recipients.toList(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              publishGeneral
                  ? 'Capítulo publicado y envíos completados.'
                  : 'Capítulo enviado.',
            ),
          ),
        );
      }
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      final retry = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('No se pudo completar el envío'),
          content: const Text(
            'No se publicó nada parcialmente. Puedes reintentar con seguridad '
            'sin crear mensajes duplicados.',
          ),
          actions: [
            TextButton(
              onPressed: () => dialogContext.pop(false),
              child: const Text('Cerrar'),
            ),
            FilledButton(
              onPressed: () => dialogContext.pop(true),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
      if (retry != true) return false;
    }
  }
  return false;
}

class _CommunityOverview {
  const _CommunityOverview({
    required this.general,
    required this.conversations,
  });

  final List<CommunityMessage> general;
  final List<ConversationPreview> conversations;
}

class _CommunityUnavailable extends StatelessWidget {
  const _CommunityUnavailable();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 58),
          SizedBox(height: 18),
          Text(
            'Inicia sesión para conversar',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'La escritura local sigue disponible sin una cuenta.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _CommunityError extends StatelessWidget {
  const _CommunityError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_outlined, size: 50),
          const SizedBox(height: 12),
          const Text(
            'No se pudieron cargar los mensajes.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

String _generalPreview(List<CommunityMessage> messages) {
  if (messages.isEmpty) {
    return 'Sé la primera persona en compartir una historia.';
  }
  return _messagePreview(messages.first);
}

String _messagePreview(CommunityMessage message) {
  if (message.body.isNotEmpty) return message.body;
  if (message.document != null) return '📖 ${message.document!.title}';
  return 'Nuevo mensaje';
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  return parts.take(2).where((part) => part.isNotEmpty).map((part) {
    return part.characters.first.toUpperCase();
  }).join();
}

String _time(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
