part of '../chat_hub_screen.dart';

// ── All Chats tab ─────────────────────────────────────────────────────────────

class _AllChatsTab extends StatelessWidget {
  const _AllChatsTab();

  static const _roleOrder = [
    UserRole.manager,
    UserRole.verifier,
    UserRole.storageActor,
    UserRole.rep,
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatDirectoryCubit, ChatDirectoryState>(
      builder: (context, state) {
        if (state is ChatDirectoryLoading || state is ChatDirectoryInitial) {
          return const AppLoadingState(message: 'جاري تحميل جهات الاتصال...');
        }
        if (state is ChatDirectoryError) {
          return AppErrorView(
            title: 'تعذر تحميل جهات الاتصال',
            message: state.message,
            retryText: 'إعادة المحاولة',
            onRetry: () => context.read<ChatDirectoryCubit>().load(),
          );
        }
        if (state is ChatDirectoryLoaded) {
          final sections = <UserRole, List<Profile>>{};
          for (final role in _roleOrder) {
            final users = state.usersByRole[role] ?? [];
            if (users.isNotEmpty) sections[role] = users;
          }

          if (sections.isEmpty) {
            return const AppEmptyState(
              icon: Icons.people_outline,
              title: 'لا يوجد مستخدمون متاحون',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => context.read<ChatDirectoryCubit>().load(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.verticalLarge),
              children: [
                for (final entry in sections.entries)
                  _RoleSection(role: entry.key, profiles: entry.value),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ── Recent Chats tab ──────────────────────────────────────────────────────────

class _RecentChatsTab extends StatefulWidget {
  const _RecentChatsTab();

  @override
  State<_RecentChatsTab> createState() => _RecentChatsTabState();
}

class _RecentChatsTabState extends State<_RecentChatsTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<UserRole> _roleFilters = {};
  bool _showGroups = false;
  bool _filtersVisible = false;

  bool get _hasActiveFilters => _roleFilters.isNotEmpty || _showGroups;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleRole(UserRole role) {
    setState(() {
      if (_roleFilters.contains(role)) {
        _roleFilters.remove(role);
      } else {
        _roleFilters.add(role);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Search + filter bar ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        textDirection: TextDirection.rtl,
                        textInputAction: TextInputAction.search,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: 'ابحث في المحادثات...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: 'مسح البحث',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    dimension: 42,
                    child: Badge(
                      isLabelVisible: _hasActiveFilters && !_filtersVisible,
                      child: IconButton.outlined(
                        icon: Icon(
                          _filtersVisible
                              ? Icons.filter_alt_off_outlined
                              : Icons.filter_alt_outlined,
                        ),
                        tooltip:
                            _filtersVisible ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
                        onPressed: () =>
                            setState(() => _filtersVisible = !_filtersVisible),
                      ),
                    ),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _filtersVisible
                    ? Padding(
                        key: const ValueKey('filters'),
                        padding: const EdgeInsets.only(top: 8),
                        child: _buildFilterCard(theme),
                      )
                    : const SizedBox.shrink(key: ValueKey('filters-hidden')),
              ),
            ],
          ),
        ),
        // ── Thread list ───────────────────────────────────────────────
        Expanded(
          child: BlocBuilder<ChatThreadsCubit, ChatThreadsState>(
            builder: (context, state) {
              if (state is ChatThreadsLoading || state is ChatThreadsInitial) {
                return const AppLoadingState(message: 'جاري تحميل المحادثات...');
              }
              if (state is ChatThreadsError) {
                return AppErrorView(
                  title: 'تعذر تحميل المحادثات',
                  message: state.message,
                  retryText: 'إعادة المحاولة',
                  onRetry: () => context.read<ChatThreadsCubit>().loadThreads(),
                );
              }
              if (state is ChatThreadsLoaded) {
                final roleById = <String, UserRole>{};
                final directoryState = context.read<ChatDirectoryCubit>().state;
                if (directoryState is ChatDirectoryLoaded) {
                  for (final entry in directoryState.usersByRole.entries) {
                    for (final profile in entry.value) {
                      roleById[profile.id] = entry.key;
                    }
                  }
                }

                var threads = state.threads;

                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  threads = threads.where((thread) {
                    final title = thread.isDirect
                        ? (thread.otherParticipantName ?? thread.title)
                        : thread.title;
                    return title.toLowerCase().contains(query) ||
                        (thread.lastMessageContent
                                ?.toLowerCase()
                                .contains(query) ??
                            false);
                  }).toList();
                }

                final hasRoleFilter = _roleFilters.isNotEmpty;
                if (hasRoleFilter || _showGroups) {
                  threads = threads.where((thread) {
                    if (!thread.isDirect) return _showGroups;
                    if (!hasRoleFilter) return true;
                    final role = thread.otherParticipantId != null
                        ? roleById[thread.otherParticipantId!]
                        : null;
                    return role != null && _roleFilters.contains(role);
                  }).toList();
                }

                if (threads.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: _searchQuery.isNotEmpty || hasRoleFilter || _showGroups
                        ? 'لا توجد نتائج'
                        : 'لا توجد محادثات بعد',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => context.read<ChatThreadsCubit>().loadThreads(),
                  child: ListView.separated(
                    padding:
                        const EdgeInsets.only(bottom: AppSpacing.verticalLarge),
                    itemCount: threads.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (_, index) =>
                        _ThreadTile(thread: threads[index]),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterCard(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.people_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'الفئات',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in [
                  UserRole.manager,
                  UserRole.verifier,
                  UserRole.storageActor,
                  UserRole.rep,
                ])
                  FilterChip(
                    label: Text(_roleSectionLabel(role)),
                    selected: _roleFilters.contains(role),
                    onSelected: (_) => _toggleRole(role),
                    showCheckmark: false,
                  ),
                FilterChip(
                  label: const Text('مجموعات'),
                  avatar: const Icon(Icons.groups_outlined, size: 16),
                  selected: _showGroups,
                  onSelected: (_) =>
                      setState(() => _showGroups = !_showGroups),
                  showCheckmark: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
