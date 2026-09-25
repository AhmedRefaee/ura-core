import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/profile.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../logic/projects_cubit.dart';
import 'letterhead_picker.dart';
import 'project_detail_screen.dart';

void openProjectsScreen(BuildContext context, Entity entity) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => sl<ProjectsCubit>()..loadProjects(entity.id),
        child: ProjectsScreen(entity: entity),
      ),
    ),
  );
}

class ProjectsScreen extends StatelessWidget {
  final Entity entity;
  const ProjectsScreen({super.key, required this.entity});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    final role = auth is AuthAuthenticated ? auth.profile.role : null;
    // Mirrors the projects table's INSERT policy.
    final canCreate = role == UserRole.verifier || role == UserRole.manager || role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(title: Text('مشاريع ${entity.name}')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('مشروع جديد'),
            )
          : null,
      body: BlocBuilder<ProjectsCubit, ProjectsState>(
        builder: (context, state) {
          return switch (state) {
            ProjectsLoaded(:final projects) when projects.isEmpty => const Center(
                child: Text('لا توجد مشاريع لهذه الجهة بعد'),
              ),
            ProjectsLoaded(:final projects) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: projects.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) {
                  final p = projects[i];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.work_outline),
                      title: Text(p.name),
                      subtitle: Text(p.letterheadImageUrl == null ? 'بدون ترويسة' : 'بترويسة'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => openProjectDetail(context, p, entity),
                    ),
                  );
                },
              ),
            ProjectsError(:final message) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.read<ProjectsCubit>().loadProjects(entity.id),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          };
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final cubit = context.read<ProjectsCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final name = TextEditingController();
    LetterheadImage? letterhead;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('مشروع جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم المشروع', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (letterhead != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(letterhead!.bytes, height: 80, fit: BoxFit.contain),
                ),
              OutlinedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final picked = await pickLetterhead();
                        if (picked != null) setLocal(() => letterhead = picked);
                      },
                icon: const Icon(Icons.image_outlined),
                label: Text(letterhead == null ? 'إضافة ترويسة (اختياري)' : 'تغيير الترويسة'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) return;
                      setLocal(() => saving = true);
                      final message = await cubit.createProject(
                        entityId: entity.id,
                        name: name.text,
                        letterhead: letterhead,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
  }
}
