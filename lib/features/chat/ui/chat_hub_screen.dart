import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/notification_dot.dart';
import '../../../features/auth/logic/auth_cubit.dart';
import '../../../features/auth/logic/auth_state.dart';
import '../../../features/notifications/data/notifications_repository.dart';
import '../../../features/notifications/logic/notifications_badge_cubit.dart';
import '../../../shared/models/chat_thread.dart';
import '../../../shared/models/profile.dart';
import '../data/chat_repository.dart';
import '../logic/chat_directory_cubit.dart';
import '../logic/chat_threads_cubit.dart';
import 'chat_thread_screen.dart';
import 'create_thread_screen.dart';

part 'chat_hub/chat_hub_body.dart';
part 'chat_hub/chat_hub_helpers.dart';
part 'chat_hub/chat_hub_scaffold.dart';
part 'chat_hub/chat_hub_tabs.dart';
part 'chat_hub/chat_hub_tiles.dart';

class ChatHubScreen extends StatelessWidget {
  const ChatHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChatThreadsCubit>()..loadThreads(),
      child: const ChatHubSection(),
    );
  }
}
