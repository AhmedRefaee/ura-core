import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/chat_thread.dart';
import '../../../shared/models/profile.dart';

class ChatRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Threads ─────────────────────────────────────────────────────────────────

  Future<AppResult<List<ChatThread>>> getThreads() async {
    try {
      logger.d('ChatRepository → getThreads');
      final uid = _supabase.auth.currentUser?.id;

      final threadsData = await _supabase.rpc('get_threads_with_preview');

      final unreadByThread = <String, int>{};
      if (uid != null) {
        final notifData = await _supabase
            .from('notifications')
            .select('action_route')
            .eq('user_id', uid)
            .eq('is_read', false)
            .ilike('action_route', '/chat/%');

        for (final row in notifData as List) {
          final route = (row as Map<String, dynamic>)['action_route'] as String?;
          if (route != null && route.startsWith('/chat/')) {
            final threadId = route.replaceFirst('/chat/', '');
            unreadByThread[threadId] = (unreadByThread[threadId] ?? 0) + 1;
          }
        }
      }

      final threads = (threadsData as List).map((e) {
        final thread = ChatThread.fromMap(e as Map<String, dynamic>);
        return thread.copyWith(unreadCount: unreadByThread[thread.id] ?? 0);
      }).toList();

      logger.i('ChatRepository → ${threads.length} threads');
      return AppSuccess(threads);
    } catch (e, st) {
      logger.e('ChatRepository → getThreads failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<Map<String, dynamic>>> getThread(String threadId) async {
    try {
      logger.d('ChatRepository → getThread: $threadId');
      final result = await _supabase
          .from('chat_threads')
          .select('id, title, created_by, created_at, is_direct, last_message_content, last_message_sender_name, last_message_at, system_messages_enabled')
          .eq('id', threadId)
          .single();
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('ChatRepository → getThread failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> toggleSystemMessages(
      String threadId, bool enabled) async {
    try {
      logger.d('ChatRepository → toggleSystemMessages: $threadId → $enabled');
      await _supabase
          .from('chat_threads')
          .update({'system_messages_enabled': enabled})
          .eq('id', threadId);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → toggleSystemMessages failed',
          error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<String>> createThread(String title) async {
    try {
      logger.d('ChatRepository → createThread: $title');
      final result = await _supabase.rpc(
        'create_chat_thread',
        params: {'p_title': title},
      );
      final id = result as String;
      logger.i('ChatRepository → thread created: $id');
      return AppSuccess(id);
    } catch (e, st) {
      logger.e('ChatRepository → createThread failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ─── Messages ─────────────────────────────────────────────────────────────────

  // Streams remain as-is — errors propagate via the stream's error channel
  Stream<List<ChatMessage>> subscribeToThread(String threadId) {
    logger.d('ChatRepository → subscribeToThread: $threadId');
    return _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at', ascending: true)
        .map((data) => data.map(ChatMessage.fromMap).toList());
  }

  Future<AppResult<void>> sendMessage({
    required String threadId,
    required String content,
    String? orderMentionId,
    String? orderMentionText,
    String? userMentionId,
    String? userMentionText,
    bool isUrgent = false,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
    String? attachmentUrl,
    String? attachmentType,
    String? attachmentName,
    int? attachmentSizeBytes,
  }) async {
    try {
      logger.d('ChatRepository → sendMessage in $threadId, urgent=$isUrgent');
      await _supabase.rpc(
        'send_chat_message',
        params: {
          'p_thread_id': threadId,
          'p_content': content,
          'p_order_mention_id': orderMentionId,
          'p_order_mention_text': orderMentionText,
          'p_user_mention_id': userMentionId,
          'p_user_mention_text': userMentionText,
          'p_is_urgent': isUrgent,
          'p_reply_to_id': replyToId,
          'p_reply_to_content': replyToContent,
          'p_reply_to_sender': replyToSender,
          'p_attachment_url': attachmentUrl,
          'p_attachment_type': attachmentType,
          'p_attachment_name': attachmentName,
          'p_attachment_size_bytes': attachmentSizeBytes,
        },
      );
      logger.i('ChatRepository → message sent');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → sendMessage failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // ─── Reactions ────────────────────────────────────────────────────────────────

  Future<AppResult<Map<String, List<ChatMessageReaction>>>> getReactionsForThread(
      String threadId) async {
    try {
      logger.d('ChatRepository → getReactionsForThread: $threadId');
      final data = await _supabase.rpc(
        'get_thread_reactions',
        params: {'p_thread_id': threadId},
      );
      final byMessage = <String, List<ChatMessageReaction>>{};
      for (final row in data as List) {
        final map = row as Map<String, dynamic>;
        final msgId = map['message_id'] as String;
        (byMessage[msgId] ??= []).add(ChatMessageReaction.fromMap(map));
      }
      logger.i('ChatRepository → reactions for ${byMessage.length} messages');
      return AppSuccess(byMessage);
    } catch (e, st) {
      logger.e('ChatRepository → getReactionsForThread failed',
          error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> addReaction(String messageId, String emoji) async {
    try {
      logger.d('ChatRepository → addReaction: $messageId $emoji');
      final uid = _supabase.auth.currentUser?.id;
      await _supabase.from('chat_message_reactions').upsert({
        'message_id': messageId,
        'user_id': uid,
        'emoji': emoji,
      });
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → addReaction failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> removeReaction(String messageId, String emoji) async {
    try {
      logger.d('ChatRepository → removeReaction: $messageId $emoji');
      final uid = _supabase.auth.currentUser?.id;
      await _supabase
          .from('chat_message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', uid ?? '')
          .eq('emoji', emoji);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → removeReaction failed',
          error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<({String id, String displayName})>>> getActiveOrders() async {
    try {
      logger.d('ChatRepository → getActiveOrders');
      final data = await _supabase
          .from('orders')
          .select('id, entity:entities(name)')
          .neq('status', 'delivered')
          .order('created_at', ascending: false)
          .limit(30);
      final orders = (data as List).map((e) {
        final entityMap = e['entity'] as Map<String, dynamic>?;
        return (
          id: e['id'] as String,
          displayName: entityMap?['name'] as String? ?? 'طلب',
        );
      }).toList();
      logger.i('ChatRepository → ${orders.length} active orders');
      return AppSuccess(orders);
    } catch (e, st) {
      logger.e('ChatRepository → getActiveOrders failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> acknowledgeMessage(String messageId) async {
    try {
      logger.d('ChatRepository → acknowledgeMessage: $messageId');
      await _supabase.rpc(
        'acknowledge_chat_message',
        params: {'p_message_id': messageId},
      );
      logger.i('ChatRepository → message acknowledged');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → acknowledgeMessage failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  // Stream — errors propagate via the stream's error channel
  Stream<Map<String, int>> subscribeToUrgentCountsByOrder() {
    logger.d('ChatRepository → subscribeToUrgentCountsByOrder');
    return _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('is_urgent', true)
        .map((data) {
          final Map<String, int> counts = {};
          for (final row in data) {
            final orderId = row['order_mention_id'] as String?;
            final isAcknowledged = row['is_acknowledged'] as bool? ?? false;
            if (orderId != null && !isAcknowledged) {
              counts[orderId] = (counts[orderId] ?? 0) + 1;
            }
          }
          return counts;
        });
  }

  // ─── Participants ─────────────────────────────────────────────────────────────

  Future<AppResult<List<Profile>>> getUsers() async {
    try {
      logger.d('ChatRepository → getUsers');
      final currentId = _supabase.auth.currentUser?.id;
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, is_approved, created_at')
          .eq('is_approved', true)
          .neq('id', currentId ?? '');
      final users = (data as List)
          .map((e) => Profile.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('ChatRepository → ${users.length} users');
      return AppSuccess(users);
    } catch (e, st) {
      logger.e('ChatRepository → getUsers failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<Profile>>> getThreadParticipants(String threadId) async {
    try {
      logger.d('ChatRepository → getThreadParticipants: $threadId');
      final data = await _supabase.rpc(
        'get_thread_participants',
        params: {'p_thread_id': threadId},
      );
      final participants = (data as List)
          .map((e) => Profile.fromMap(e as Map<String, dynamic>))
          .toList();
      logger.i('ChatRepository → ${participants.length} participants');
      return AppSuccess(participants);
    } catch (e, st) {
      logger.e('ChatRepository → getThreadParticipants failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> addParticipant(String threadId, String userId) async {
    try {
      logger.d('ChatRepository → addParticipant: thread=$threadId user=$userId');
      await _supabase.rpc(
        'add_thread_participant',
        params: {'p_thread_id': threadId, 'p_user_id': userId},
      );
      logger.i('ChatRepository → participant added');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → addParticipant failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> removeParticipant(String threadId, String userId) async {
    try {
      logger.d('ChatRepository → removeParticipant: thread=$threadId user=$userId');
      await _supabase.rpc(
        'remove_thread_participant',
        params: {'p_thread_id': threadId, 'p_user_id': userId},
      );
      logger.i('ChatRepository → participant removed');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → removeParticipant failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteThread(String threadId) async {
    try {
      logger.d('ChatRepository → deleteThread: $threadId');
      await _supabase.rpc(
        'delete_chat_thread',
        params: {'p_thread_id': threadId},
      );
      logger.i('ChatRepository → thread deleted');
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatRepository → deleteThread failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<String>> getOrCreateDirectThread(String verifierId) async {
    try {
      logger.d('ChatRepository → getOrCreateDirectThread: verifierId=$verifierId');
      final result = await _supabase.rpc(
        'get_or_create_direct_thread',
        params: {'p_verifier_id': verifierId},
      );
      final threadId = result as String;
      logger.i('ChatRepository → direct thread: $threadId');
      return AppSuccess(threadId);
    } catch (e, st) {
      logger.e('ChatRepository → getOrCreateDirectThread failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<ChatMessage>>> getOrderCommunicationHistory(String orderId) async {
    try {
      logger.d('ChatRepository → getOrderCommunicationHistory: $orderId');
      final data = await _supabase
          .from('chat_messages')
          .select('id, thread_id, sender_id, sender_name, content, order_mention_id, order_mention_text, user_mention_id, user_mention_text, is_urgent, is_acknowledged, acknowledged_by, acknowledged_at, created_at, message_type, reply_to_id, reply_to_content, reply_to_sender, attachment_url, attachment_type, attachment_name, attachment_size_bytes, thread:chat_threads(title)')
          .eq('order_mention_id', orderId)
          .order('created_at', ascending: false);
      final messages = data.map(ChatMessage.fromMap).toList();
      logger.i('ChatRepository → ${messages.length} history messages for order $orderId');
      return AppSuccess(messages);
    } catch (e, st) {
      logger.e('ChatRepository → getOrderCommunicationHistory failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
