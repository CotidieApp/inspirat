import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_controller.dart';
import 'community.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'data/models.dart';

final appControllerProvider = Provider<AppController>((ref) => AppController());

class InspiratBootstrap extends ConsumerStatefulWidget {
  const InspiratBootstrap({super.key});

  @override
  ConsumerState<InspiratBootstrap> createState() => _InspiratBootstrapState();
}

class _InspiratBootstrapState extends ConsumerState<InspiratBootstrap> {
  late final AppController controller;
  late final GoRouter router;
  late final Future<void> initialization;

  @override
  void initState() {
    super.initState();
    controller = ref.read(appControllerProvider);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => controller.localMode
              ? WelcomeScreen(controller: controller)
              : HomeScreen(controller: controller),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) =>
              AuthScreen(controller: controller, register: false),
        ),
        GoRoute(
          path: '/register',
          builder: (_, _) => AuthScreen(controller: controller, register: true),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (_, _) => ForgotPasswordScreen(controller: controller),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => HomeScreen(controller: controller),
        ),
        GoRoute(
          path: '/search',
          builder: (_, _) => SearchScreen(controller: controller),
        ),
        GoRoute(
          path: '/community',
          builder: (_, _) => GeneralChatScreen(controller: controller),
        ),
        GoRoute(
          path: '/messages/:userId',
          builder: (_, state) => DirectChatScreen(
            controller: controller,
            userId: state.pathParameters['userId']!,
            user: state.extra is CommunityUser
                ? state.extra! as CommunityUser
                : null,
          ),
        ),
        GoRoute(
          path: '/project/:id',
          builder: (_, state) {
            final id = state.pathParameters['id']!;
            final exists = controller.projects.any(
              (project) => project.clientId == id,
            );
            return exists
                ? ProjectScreen(controller: controller, projectId: id)
                : const MissingContentScreen();
          },
        ),
        GoRoute(
          path: '/editor/:id',
          builder: (_, state) {
            final id = state.pathParameters['id']!;
            return controller.findDocument(id) == null
                ? const MissingContentScreen()
                : EditorScreen(controller: controller, documentId: id);
          },
        ),
      ],
    );
    initialization = controller.initialize();
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: InspiratTheme.light(),
          home: const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      if (snapshot.hasError) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: InspiratTheme.light(),
          home: const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No se pudo abrir el almacenamiento local. '
                  'Reinicia la aplicación.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      }
      return MaterialApp.router(
        title: AppConfig.displayName,
        debugShowCheckedModeBanner: false,
        theme: InspiratTheme.light(),
        darkTheme: InspiratTheme.dark(),
        routerConfig: router,
      );
    },
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/branding/icon-512x512.png',
                width: 88,
                height: 88,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              AppConfig.displayName,
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'Tu espacio privado para escribir, ordenar historias y compartir '
              'solo cuando tú lo decidas.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Una cuenta permite sincronizar y recibir comentarios. '
              'También puedes escribir sin registrarte.',
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => context.push('/register'),
              child: const Text('Crear una cuenta'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => context.push('/login'),
              child: const Text('Iniciar sesión'),
            ),
            TextButton(
              onPressed: () async {
                await controller.useLocally();
                if (context.mounted) context.go('/home');
              },
              child: const Text('Escribir sin crear cuenta'),
            ),
            if (AppConfig.isDevBuild)
              TextButton.icon(
                onPressed: () => showServerConfiguration(context, controller),
                icon: const Icon(Icons.lan_outlined),
                label: const Text('Configurar conexión al servidor'),
              ),
          ],
        ),
      ),
    ),
  );
}

class MissingContentScreen extends StatelessWidget {
  const MissingContentScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.find_in_page_outlined, size: 58),
            const SizedBox(height: 16),
            Text(
              'Este contenido ya no está disponible',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Pudo eliminarse o pertenecer a otra cuenta. Tus demás textos '
              'locales no se modificaron.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.go('/home'),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.controller,
    required this.register,
  });
  final AppController controller;
  final bool register;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final identity = TextEditingController();
  final email = TextEditingController();
  final username = TextEditingController();
  final displayName = TextEditingController();
  final password = TextEditingController();
  final passwordConfirmation = TextEditingController();
  bool obscure = true;
  bool acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(controllerChanged);
  }

  void controllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(controllerChanged);
    identity.dispose();
    email.dispose();
    username.dispose();
    displayName.dispose();
    password.dispose();
    passwordConfirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    if (widget.register && !acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes aceptar las condiciones y la política de privacidad.',
          ),
        ),
      );
      return;
    }
    final ok = widget.register
        ? await widget.controller.register(
            email.text.trim(),
            username.text.trim(),
            displayName.text.trim(),
            password.text,
          )
        : await widget.controller.login(identity.text.trim(), password.text);
    if (ok && mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.register ? 'Crear cuenta' : 'Iniciar sesión'),
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.register) ...[
            TextFormField(
              controller: displayName,
              decoration: const InputDecoration(labelText: 'Nombre visible'),
              validator: validateDisplayName,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: username,
              decoration: const InputDecoration(labelText: 'Usuario único'),
              validator: validateUsername,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo'),
              validator: validateEmail,
            ),
          ] else
            TextFormField(
              controller: identity,
              decoration: const InputDecoration(labelText: 'Correo o usuario'),
              validator: requiredField,
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: password,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            validator: validatePassword,
          ),
          if (widget.register) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: passwordConfirmation,
              obscureText: obscure,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
              ),
              validator: (value) => value != password.text
                  ? 'Las contraseñas no coinciden'
                  : null,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acceptedTerms,
              onChanged: (value) =>
                  setState(() => acceptedTerms = value ?? false),
              title: const Text(
                'Acepto las condiciones y la política de privacidad',
              ),
              subtitle: const Text(
                'Tus textos siguen siendo tuyos y nacen privados.',
              ),
            ),
          ],
          if (widget.controller.error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: widget.controller.error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.controller.busy ? null : submit,
            child: Text(
              widget.controller.busy
                  ? 'Conectando…'
                  : widget.register
                  ? 'Crear cuenta'
                  : 'Entrar',
            ),
          ),
          if (!widget.register) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push('/forgot-password'),
              child: const Text('¿Olvidaste tu contraseña?'),
            ),
          ],
        ],
      ),
    ),
  );
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final requestFormKey = GlobalKey<FormState>();
  final resetFormKey = GlobalKey<FormState>();
  final identity = TextEditingController();
  final code = TextEditingController();
  final password = TextEditingController();
  final passwordConfirmation = TextEditingController();
  bool codeSent = false;
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(controllerChanged);
  }

  void controllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(controllerChanged);
    identity.dispose();
    code.dispose();
    password.dispose();
    passwordConfirmation.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    if (!requestFormKey.currentState!.validate()) return;
    final ok = await widget.controller.requestPasswordReset(identity.text.trim());
    if (ok && mounted) {
      setState(() => codeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Si la cuenta existe, se envió un código a su correo.'),
        ),
      );
    }
  }

  Future<void> confirmReset() async {
    if (!resetFormKey.currentState!.validate()) return;
    final ok = await widget.controller.resetPassword(
      identity: identity.text.trim(),
      code: code.text.trim(),
      newPassword: password.text,
    );
    if (ok && mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Restablecer contraseña')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (!codeSent) ...[
          const Text(
            'Escribe el correo o usuario de tu cuenta y te enviaremos un '
            'código para restablecer la contraseña.',
          ),
          const SizedBox(height: 16),
          Form(
            key: requestFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: identity,
                  decoration: const InputDecoration(labelText: 'Correo o usuario'),
                  validator: requiredField,
                ),
                if (widget.controller.error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(message: widget.controller.error!),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.controller.busy ? null : sendCode,
                  child: Text(
                    widget.controller.busy ? 'Enviando…' : 'Enviar código',
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Text('Revisa el correo de ${identity.text} y escribe el código.'),
          const SizedBox(height: 16),
          Form(
            key: resetFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
                  validator: (value) => RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Escribe los 6 dígitos del código',
                ),
                TextFormField(
                  controller: password,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => obscure = !obscure),
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                  validator: validatePassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordConfirmation,
                  obscureText: obscure,
                  decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
                  validator: (value) => value != password.text
                      ? 'Las contraseñas no coinciden'
                      : null,
                ),
                if (widget.controller.error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(message: widget.controller.error!),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.controller.busy ? null : confirmReset,
                  child: Text(
                    widget.controller.busy
                        ? 'Restableciendo…'
                        : 'Restablecer contraseña',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.controller.busy
                      ? null
                      : () => setState(() => codeSent = false),
                  child: const Text('¿No te llegó? Enviar otro código'),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

String? requiredField(String? value) =>
    value == null || value.trim().isEmpty ? 'Este campo es obligatorio' : null;

String? validateDisplayName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Este campo es obligatorio';
  if (name.length > 100) return 'Usa como máximo 100 caracteres';
  return null;
}

String? validateUsername(String? value) {
  final user = value?.trim() ?? '';
  if (user.length < 3 || user.length > 40) {
    return 'Usa entre 3 y 40 caracteres';
  }
  if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(user)) {
    return 'Usa letras sin tilde, números, punto, guion o guion bajo';
  }
  return null;
}

String? validateEmail(String? value) {
  final address = value?.trim() ?? '';
  if (address.length > 320 ||
      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
    return 'Escribe un correo válido';
  }
  return null;
}

String? validatePassword(String? value) {
  final length = value?.length ?? 0;
  if (length < 10) return 'Usa al menos 10 caracteres';
  if (length > 128) return 'Usa como máximo 128 caracteres';
  return null;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(controllerChanged);
  }

  void controllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(controllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(controller: widget.controller),
      Library(controller: widget.controller),
      QuickWrite(controller: widget.controller),
      CommunityHub(controller: widget.controller),
      Profile(controller: widget.controller),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(index == 0 ? AppConfig.displayName : _titles[index]),
        actions: [
          IconButton(
            tooltip: 'Buscar en todo',
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.search),
          ),
          if (widget.controller.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text('${widget.controller.pendingCount} pendientes'),
              ),
            ),
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: widget.controller.localMode || widget.controller.busy
                ? null
                : widget.controller.sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            label: 'Biblioteca',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            label: 'Escribir',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            label: 'Mensajes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
      floatingActionButton: index < 2
          ? FloatingActionButton.extended(
              onPressed: () => showCreateProject(context, widget.controller),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo proyecto'),
            )
          : null,
    );
  }
}

const _titles = ['Inicio', 'Biblioteca', 'Escribir', 'Mensajes', 'Perfil'];

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      await controller.sync();
    },
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        Text(
          controller.username == null
              ? 'Un lugar tranquilo para tus historias'
              : 'Hola, ${controller.username}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        SyncBanner(controller: controller),
        if (!controller.localMode && controller.localProjectsAvailable > 0) ...[
          const SizedBox(height: 12),
          Card(
            color: InspiratTheme.champagne.withValues(alpha: .16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${controller.localProjectsAvailable} proyectos locales',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Siguen separados de esta cuenta. Impórtalos sólo si '
                    'te pertenecen y quieres sincronizarlos aquí.',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: controller.busy
                        ? null
                        : () => confirmLocalImport(context, controller),
                    child: const Text('Revisar e importar'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Tu biblioteca', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _StatValue(
                  value: '${controller.totalWordCount}',
                  label: 'palabras',
                ),
                const SizedBox(width: 18),
                _StatValue(
                  value: '${controller.allDocuments.length}',
                  label: 'documentos',
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _StatValue(
                    value: controller.mostFrequentWord,
                    label: 'palabra recurrente',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Recientes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (controller.projects.isEmpty)
          const EmptyState(
            icon: Icons.auto_stories_outlined,
            title: 'Tu biblioteca está esperando',
            body: 'Crea una novela, cuento, poema o proyecto libre.',
          )
        else
          ...controller.projects
              .take(4)
              .map((project) => ProjectCard(project: project)),
      ],
    ),
  );
}

Future<void> confirmLocalImport(
  BuildContext context,
  AppController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Importar proyectos locales'),
      content: const Text(
        'Los proyectos del modo sin cuenta se asociarán a la sesión actual '
        'y se enviarán a este servidor. Esta acción no debe hacerse en una '
        'cuenta ajena.',
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: const Text('Ahora no'),
        ),
        FilledButton(
          onPressed: () => context.pop(true),
          child: const Text('Importar a mi cuenta'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final ok = await controller.importLocalProjects();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Proyectos locales importados.'
              : 'No se pudo importar; los proyectos siguen seguros.',
        ),
      ),
    );
  }
}

class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final conflict = controller.syncStatus == SyncStatus.conflict;
    final offline = controller.syncStatus == SyncStatus.offline;
    final pending =
        controller.syncStatus == SyncStatus.pending ||
        controller.syncStatus == SyncStatus.syncing;
    final color = conflict || offline
        ? InspiratTheme.terracotta
        : pending
        ? InspiratTheme.champagne
        : InspiratTheme.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            offline
                ? Icons.cloud_off_outlined
                : conflict
                ? Icons.warning_amber
                : controller.localMode
                ? Icons.phone_android
                : pending
                ? Icons.cloud_upload_outlined
                : Icons.cloud_done_outlined,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(controller.syncState)),
          if (conflict)
            TextButton(
              onPressed: controller.busy
                  ? null
                  : () => confirmKeepLocalConflicts(context, controller),
              child: const Text('Resolver'),
            ),
        ],
      ),
    );
  }
}

Future<void> confirmKeepLocalConflicts(
  BuildContext context,
  AppController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Resolver conflicto'),
      content: const Text(
        'Se conservará la versión de este teléfono y se enviará nuevamente. '
        'En los capítulos, la versión anterior del servidor quedará guardada '
        'en el historial.',
      ),
      actions: [
        TextButton(
          onPressed: () => dialogContext.pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => dialogContext.pop(true),
          child: const Text('Conservar mi versión'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final resolved = await controller.resolveConflictsKeepingLocal();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resolved
              ? 'Conflicto resuelto y sincronizado.'
              : 'No se pudo sincronizar todavía; tu versión sigue segura.',
        ),
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: InspiratTheme.petrol,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();

  @override
  void initState() {
    super.initState();
    query.addListener(changed);
  }

  void changed() => setState(() {});

  @override
  void dispose() {
    query.removeListener(changed);
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.controller.searchProjects(query.text);
    final documents = widget.controller.searchDocuments(query.text);
    final waiting = query.text.trim().length < 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Búsqueda global')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: query,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar títulos, sinopsis o texto…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: query.clear,
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 22),
          if (waiting)
            const EmptyState(
              icon: Icons.manage_search,
              title: 'Busca en toda tu escritura',
              body: 'La búsqueda funciona también sin conexión.',
            )
          else if (projects.isEmpty && documents.isEmpty)
            EmptyState(
              icon: Icons.search_off,
              title: 'Sin resultados',
              body: 'No encontramos coincidencias para «${query.text.trim()}».',
            )
          else ...[
            if (projects.isNotEmpty) ...[
              Text('Proyectos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...projects.map(
                (project) => ListTile(
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    project.synopsis.isEmpty
                        ? 'Sinopsis pendiente'
                        : project.synopsis,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.push('/project/${project.clientId}'),
                ),
              ),
            ],
            if (documents.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Documentos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...documents.map(
                (document) => ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    document.content.replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.push('/editor/${document.clientId}'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class Library extends StatelessWidget {
  const Library({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => controller.projects.isEmpty
      ? const EmptyState(
          icon: Icons.library_add_outlined,
          title: 'Aún no hay proyectos',
          body:
              'El primer proyecto se guarda inmediatamente en este dispositivo.',
        )
      : ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: controller.projects
              .map((p) => ProjectCard(project: p))
              .toList(),
        );
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project});
  final WritingProject project;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Container(
        width: 48,
        height: 60,
        decoration: BoxDecoration(
          color: InspiratTheme.petrol.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.auto_stories, color: InspiratTheme.petrol),
      ),
      title: Text(
        project.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        project.synopsis.isEmpty ? 'Sinopsis pendiente' : project.synopsis,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: project.syncState == 'conflict'
          ? const Icon(Icons.warning_amber, color: InspiratTheme.terracotta)
          : const Icon(Icons.chevron_right),
      onTap: () => context.push('/project/${project.clientId}'),
    ),
  );
}

class QuickWrite extends StatelessWidget {
  const QuickWrite({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final docs = controller.recentDocuments;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Continúa donde lo dejaste. Cada cambio se guarda localmente.',
        ),
        const SizedBox(height: 16),
        if (docs.isEmpty)
          const EmptyState(
            icon: Icons.edit_note,
            title: 'Nada que continuar',
            body: 'Crea un proyecto y su primer capítulo.',
          )
        else
          ...docs
              .take(8)
              .map(
                (document) => ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${document.wordCount} palabras · ${document.syncState}',
                  ),
                  onTap: () => context.push('/editor/${document.clientId}'),
                ),
              ),
      ],
    );
  }
}

class ProjectScreen extends StatelessWidget {
  const ProjectScreen({
    super.key,
    required this.controller,
    required this.projectId,
  });
  final AppController controller;
  final String projectId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      WritingProject? project;
      for (final candidate in controller.projects) {
        if (candidate.clientId == projectId) {
          project = candidate;
          break;
        }
      }
      if (project == null) return const MissingContentScreen();
      final documents = controller.documentsByProject[projectId] ?? [];
      return Scaffold(
        appBar: AppBar(
          title: Text(
            project.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (project.synopsis.isNotEmpty) Text(project.synopsis),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Capítulos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      showCreateDocument(context, controller, projectId),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (documents.isEmpty)
              const EmptyState(
                icon: Icons.note_add_outlined,
                title: 'Escribe el primer capítulo',
                body: 'Quedará disponible incluso sin internet.',
              )
            else
              ...documents.map(
                (document) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.drag_indicator),
                    title: Text(
                      document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${document.wordCount} palabras · ${document.syncState}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/editor/${document.clientId}'),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.controller,
    required this.documentId,
  });
  final AppController controller;
  final String documentId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late WritingDocument document;
  late TextEditingController text;
  late final DateTime sessionStarted;
  late DateTime lastEdit;
  late final int initialWordCount;
  late int previousLength;
  Timer? debounce;
  Timer? sessionTicker;
  int deletedCharacters = 0;
  int longPauses = 0;
  bool hasEdited = false;
  bool focusMode = false;
  bool saving = false;
  bool leaving = false;
  bool allowPop = false;
  late String savedContent;
  Future<void>? activeSave;
  String saveLabel = 'Guardado';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    document = widget.controller.findDocument(widget.documentId)!;
    text = TextEditingController(text: document.content);
    savedContent = document.content;
    sessionStarted = DateTime.now();
    lastEdit = sessionStarted;
    initialWordCount = document.wordCount;
    previousLength = document.content.length;
    text.addListener(changed);
    sessionTicker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void changed() {
    final now = DateTime.now();
    if (hasEdited && now.difference(lastEdit).inSeconds >= 5) {
      longPauses += 1;
    }
    if (text.text.length < previousLength) {
      deletedCharacters += previousLength - text.text.length;
    }
    previousLength = text.text.length;
    lastEdit = now;
    hasEdited = true;
    debounce?.cancel();
    if (saveLabel != 'Cambios sin guardar') {
      setState(() => saveLabel = 'Cambios sin guardar');
    }
    debounce = Timer(const Duration(milliseconds: 650), save);
  }

  Future<bool> save({bool confirm = false}) async {
    debounce?.cancel();
    if (saving) {
      try {
        await activeSave;
      } catch (_) {}
    }
    final content = text.text;
    if (content == savedContent) {
      if (confirm && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El texto ya está guardado.')),
        );
      }
      return true;
    }
    if (mounted) {
      setState(() {
        saving = true;
        saveLabel = 'Guardando…';
      });
    }
    final operation = widget.controller.saveDocument(document, content);
    activeSave = operation;
    try {
      document = await operation;
      savedContent = content;
      if (!mounted) return true;
      setState(() {
        saving = false;
        saveLabel = text.text == savedContent
            ? 'Guardado en el dispositivo'
            : 'Cambios sin guardar';
      });
      if (text.text != savedContent) {
        debounce = Timer(const Duration(milliseconds: 650), save);
      }
      if (confirm) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guardado en este dispositivo.')),
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          saveLabel = 'Error al guardar · inténtalo de nuevo';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el texto.')),
        );
      }
      return false;
    } finally {
      activeSave = null;
    }
  }

  Future<void> saveAndLeave() async {
    if (leaving) return;
    leaving = true;
    final saved = await save();
    if (!mounted) return;
    if (!saved) {
      leaving = false;
      return;
    }
    setState(() => allowPop = true);
    context.pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(save());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debounce?.cancel();
    sessionTicker?.cancel();
    text.removeListener(changed);
    if (text.text != savedContent) {
      unawaited(widget.controller.saveDocument(document, text.text));
    }
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = countWords(text.text);
    final sessionWords = words > initialWordCount
        ? words - initialWordCount
        : 0;
    final elapsedSeconds = DateTime.now().difference(sessionStarted).inSeconds;
    final wordsPerMinute = elapsedSeconds == 0
        ? 0
        : (sessionWords * 60 / elapsedSeconds).round();
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(saveAndLeave());
      },
      child: Scaffold(
        appBar: focusMode
            ? null
            : AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.title),
                    Text(
                      saveLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Guardar ahora',
                    onPressed: saving ? null : () => save(confirm: true),
                    icon: const Icon(Icons.save_outlined),
                  ),
                  IconButton(
                    tooltip: 'Modo concentración',
                    onPressed: () => setState(() => focusMode = true),
                    icon: const Icon(Icons.fullscreen),
                  ),
                  PopupMenuButton<String>(
                    onSelected: action,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'session',
                        child: Text('Estadísticas de esta sesión'),
                      ),
                      PopupMenuItem(
                        value: 'version',
                        child: Text('Crear hito de versión'),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text('Enviar o publicar'),
                      ),
                      PopupMenuItem(
                        value: 'sync',
                        child: Text('Sincronizar ahora'),
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  focusMode ? 28 : 20,
                  focusMode ? 42 : 12,
                  focusMode ? 28 : 20,
                  56,
                ),
                child: TextField(
                  controller: text,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  autocorrect: true,
                  enableSuggestions: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 19, height: 1.65),
                  decoration: const InputDecoration(
                    hintText: 'Empieza a escribir…',
                    filled: false,
                    border: InputBorder.none,
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 10,
                child: Row(
                  children: [
                    Text('$words palabras'),
                    const SizedBox(width: 14),
                    Text('+$sessionWords sesión'),
                    const SizedBox(width: 14),
                    Text('$wordsPerMinute ppm'),
                    const Spacer(),
                    if (focusMode)
                      IconButton(
                        tooltip: 'Salir del modo concentración',
                        onPressed: () => setState(() => focusMode = false),
                        icon: const Icon(Icons.fullscreen_exit),
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

  Future<void> action(String value) async {
    if (value == 'sync') {
      if (!await save()) return;
      await widget.controller.sync();
      document = widget.controller.findDocument(widget.documentId) ?? document;
      return;
    }
    if (value == 'session') {
      final elapsed = DateTime.now().difference(sessionStarted);
      final currentWords = countWords(text.text);
      final sessionWords = currentWords > initialWordCount
          ? currentWords - initialWordCount
          : 0;
      final seconds = elapsed.inSeconds;
      final wpm = seconds == 0 ? 0 : (sessionWords * 60 / seconds).round();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Esta sesión'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(
                  '${elapsed.inMinutes} min ${elapsed.inSeconds % 60} s',
                ),
                subtitle: const Text('Tiempo escribiendo'),
              ),
              ListTile(
                leading: const Icon(Icons.add_chart),
                title: Text('+$sessionWords palabras · $wpm ppm'),
                subtitle: const Text('Avance y ritmo aproximado'),
              ),
              ListTile(
                leading: const Icon(Icons.backspace_outlined),
                title: Text('$deletedCharacters caracteres borrados'),
                subtitle: Text('$longPauses pausas de 5 segundos o más'),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => context.pop(),
              child: const Text('Continuar escribiendo'),
            ),
          ],
        ),
      );
      return;
    }
    if (value == 'share') {
      if (!await save()) return;
      final synced = await widget.controller.sync();
      document = widget.controller.findDocument(widget.documentId) ?? document;
      if (!synced || document.syncState != 'synced') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se publicó: la copia local está segura, pero falta '
                'sincronizarla con el servidor.',
              ),
            ),
          );
        }
        return;
      }
      if (mounted) {
        await showPublishComposer(context, widget.controller, document);
      }
      return;
    }
    if (value == 'version') {
      if (!await save()) return;
      final synced = await widget.controller.sync();
      document = widget.controller.findDocument(widget.documentId) ?? document;
      if (!synced ||
          document.syncState != 'synced' ||
          document.serverId == null ||
          widget.controller.localMode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sincroniza primero para crear una versión.'),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      final name = await textPrompt(
        context,
        'Nombre del hito',
        'Primer borrador',
      );
      if (name != null) {
        await widget.controller.api.createVersion(document.serverId!, name);
      }
      return;
    }
    if (document.serverId == null || widget.controller.localMode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sincroniza primero para usar esta acción.'),
          ),
        );
      }
      return;
    }
  }
}

class Inbox extends StatefulWidget {
  const Inbox({super.key, required this.controller});
  final AppController controller;

  @override
  State<Inbox> createState() => _InboxState();
}

class _InboxState extends State<Inbox> {
  late Future<List<dynamic>> items = widget.controller.loadInbox();

  @override
  Widget build(BuildContext context) {
    if (widget.controller.localMode) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Inicia sesión para recibir escritos',
        body: 'Tus proyectos locales no se enviarán hasta que tú lo decidas.',
      );
    }
    return FutureBuilder<List<dynamic>>(
      future: items,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.mark_email_unread_outlined,
            title: 'Bandeja vacía',
            body: 'Los capítulos enviados por otras personas aparecerán aquí.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              items = widget.controller.loadInbox();
            });
            await items;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: snapshot.data!.map((raw) {
              final item = raw as Map<String, dynamic>;
              final document = item['document'] as Map<String, dynamic>? ?? {};
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(
                    document['title'] as String? ?? 'Sin título',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item['sender_name']} · permiso: ${item['permission']}\n'
                    '${item['message'] as String? ?? ''}',
                  ),
                  isThreeLine: true,
                  onTap: () => showReceived(context, widget.controller, item),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class Profile extends StatelessWidget {
  const Profile({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const CircleAvatar(
        radius: 38,
        backgroundColor: InspiratTheme.petrol,
        child: Icon(Icons.person, color: Colors.white, size: 40),
      ),
      const SizedBox(height: 14),
      Center(
        child: Text(
          controller.username ?? 'Modo local',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: 24),
      const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Privacidad por defecto'),
        subtitle: Text('Nada se publica sin una acción explícita.'),
      ),
      ListTile(
        leading: Icon(
          controller.localMode
              ? Icons.phone_android_outlined
              : Icons.cloud_done_outlined,
        ),
        title: Text(
          controller.localMode
              ? 'Datos guardados en este teléfono'
              : 'Cuenta conectada y sincronizable',
        ),
        subtitle: Text(
          controller.localMode
              ? 'No desinstales la aplicación sin migrar tus proyectos a una '
                    'cuenta.'
              : 'Los cambios se guardan primero en el teléfono y luego se '
                    'sincronizan.',
        ),
      ),
      if (AppConfig.isDevBuild)
        ListTile(
          leading: const Icon(Icons.lan_outlined),
          title: const Text('Servidor de sincronización'),
          subtitle: Text(controller.serverBaseUrl),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => showServerConfiguration(context, controller),
        ),
      const SizedBox(height: 16),
      if (!controller.localMode)
        OutlinedButton(
          onPressed: () async {
            await controller.logout();
            if (context.mounted) context.go('/');
          },
          child: const Text('Cerrar sesión en este dispositivo'),
        )
      else
        FilledButton.tonal(
          onPressed: () => context.push('/register'),
          child: const Text('Crear cuenta y sincronizar'),
        ),
    ],
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(36),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 58, color: InspiratTheme.petrol),
        const SizedBox(height: 18),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
      ],
    ),
  );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(message),
  );
}

Future<void> showCreateProject(
  BuildContext context,
  AppController controller,
) async {
  final title = await textPrompt(
    context,
    'Nuevo proyecto',
    'Título de la obra',
  );
  if (title == null || title.trim().isEmpty) return;
  final project = await controller.createProject(title.trim(), '', 'free');
  if (context.mounted) context.push('/project/${project.clientId}');
}

Future<void> showCreateDocument(
  BuildContext context,
  AppController controller,
  String projectId,
) async {
  final title = await textPrompt(
    context,
    'Nuevo capítulo',
    'Título del capítulo',
  );
  if (title == null || title.trim().isEmpty) return;
  final document = await controller.createDocument(projectId, title.trim());
  if (context.mounted) context.push('/editor/${document.clientId}');
}

Future<String?> textPrompt(BuildContext context, String title, String hint) {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        autofocus: true,
        onChanged: (newValue) => value = newValue,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => context.pop(value),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

Future<void> showServerConfiguration(
  BuildContext context,
  AppController controller,
) async {
  controller.error = null;
  var serverValue = controller.serverBaseUrl;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AlertDialog(
        title: const Text('Conexión al servidor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usa la IP local del computador. Por ejemplo: '
              '192.168.4.200:8000',
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: serverValue,
              onChanged: (value) => serverValue = value,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                prefixIcon: Icon(Icons.computer),
              ),
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(message: controller.error!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: controller.busy
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: controller.busy
                ? null
                : () async {
                    final ok = await controller.configureServer(serverValue);
                    if (ok && dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
            child: Text(controller.busy ? 'Comprobando…' : 'Probar y guardar'),
          ),
        ],
      ),
    ),
  );
  if (accepted == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Servidor conectado correctamente.')),
    );
  }
}

Future<void> showShare(
  BuildContext context,
  AppController controller,
  String serverId,
) async {
  var recipient = '';
  var message = '';
  var permission = 'comment';
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Compartir capítulo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              onChanged: (value) => recipient = value,
              decoration: const InputDecoration(labelText: 'Usuario o correo'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: permission,
              items: const [
                DropdownMenuItem(value: 'read', child: Text('Solo lectura')),
                DropdownMenuItem(
                  value: 'comment',
                  child: Text('Lectura y comentarios'),
                ),
                DropdownMenuItem(value: 'edit', child: Text('Edición')),
              ],
              onChanged: (value) => setState(() => permission = value!),
            ),
            const SizedBox(height: 10),
            TextFormField(
              onChanged: (value) => message = value,
              decoration: const InputDecoration(labelText: 'Mensaje opcional'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    ),
  );
  if (accepted == true) {
    await controller.api.share(serverId, recipient, permission, message);
  }
}

Future<void> showReceived(
  BuildContext context,
  AppController controller,
  Map<String, dynamic> item,
) async {
  final document = item['document'] as Map<String, dynamic>;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.all(22),
        child: ListView(
          controller: scroll,
          children: [
            Text(
              document['title'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('De ${item['sender_name']} · ${item['permission']}'),
            const Divider(height: 32),
            SelectableText(
              document['content'] as String? ?? '',
              style: const TextStyle(fontSize: 18, height: 1.6),
            ),
            if (item['permission'] != 'read') ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  final body = await textPrompt(
                    context,
                    'Añadir comentario',
                    'Tu comentario',
                  );
                  if (body != null && body.trim().isNotEmpty) {
                    await controller.api.comment(
                      document['id'] as String,
                      body.trim(),
                    );
                    if (context.mounted) context.pop();
                  }
                },
                icon: const Icon(Icons.comment_outlined),
                label: const Text('Comentar'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
