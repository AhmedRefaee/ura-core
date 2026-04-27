import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/chat_thread.dart';
import '../../../shared/models/profile.dart';

class ChatRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Threads ─────────────────────────────────────────────────────────────────

  Future<List<ChatThread>> getThreads() async {
    logger.d('ChatRepository → getThreads');
    final data = await _supabase
        .from('chat_threads')
        .select()
        .order('created_at', ascending: false);

    final threads = (data as List)
        .map((e) => ChatThread.fromMap(e as Map<String, dynamic>))
        .toList(); // ignore: unnecessary_cast — supabase returns dynamic list
    logger.i('ChatRepository → ${threads.length} threads');
    return threads;
  }

  Future<String> createThread(String title) async {
    logger.d('ChatRepository → createThread: $title');
    final result = await _supabase.rpc(
      'create_chat_thread',
      params: {'p_title': title},
    );
    final id = result as String;
    logger.i('ChatRepository → thread created: $id');
    return id;
  }

  // ─── Messages ─────────────────────────────────────────────────────────────────

  Stream<List<ChatMessage>> subscribeToThread(String threadId) {
    logger.d('ChatRepository → subscribeToThread: $threadId');
    return _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at', ascending: true)
        .map((data) => data.map(ChatMessage.fromMap).toList());
  }

  Future<void> sendMessage({
    required String threadId,
    required String content,
    String? orderMentionId,
    String? orderMentionText,
    String? userMentionId,
    String? userMentionText,
    bool isUrgent = false,
  }) async {
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
      },
    );
    logger.i('ChatRepository → message sent');
  }

  Future<List<({String id, String displayName})>> getActiveOrders() async {
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
    return orders;
  }

  Future<void> acknowledgeMessage(String messageId) async {
    logger.d('ChatRepository → acknowledgeMessage: $messageId');
    await _supabase.rpc(
      'acknowledge_chat_message',
      params: {'p_message_id': messageId},
    );
    logger.i('ChatRepository → message acknowledged');
  }

  /// Real-time stream: maps order IDs to pending urgent message counts.
  /// Subscribes to all urgent unacknowledged messages and groups by order.
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

  Future<List<Profile>> getUsers() async {
    logger.d('ChatRepository → getUsers');
    final currentId = _supabase.auth.currentUser?.id;
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('is_approved', true)
        .neq('id', currentId ?? '');
    final users = (data as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('ChatRepository → ${users.length} users');
    return users;
  }

  Future<List<Profile>> getThreadParticipants(String threadId) async {
    logger.d('ChatRepository → getThreadParticipants: $threadId');
    final data = await _supabase.rpc(
      'get_thread_participants',
      params: {'p_thread_id': threadId},
    );
    final participants = (data as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
    logger.i('ChatRepository → ${participants.length} participants');
    return participants;
  }

  Future<void> addParticipant(String threadId, String userId) async {
    logger.d('ChatRepository → addParticipant: thread=$threadId user=$userId');
    await _supabase.rpc(
      'add_thread_participant',
      params: {'p_thread_id': threadId, 'p_user_id': userId},
    );
    logger.i('ChatRepository → participant added');
  }

  Future<void> removeParticipant(String threadId, String userId) async {
    logger.d('ChatRepository → removeParticipant: thread=$threadId user=$userId');
    await _supabase.rpc(
      'remove_thread_participant',
      params: {'p_thread_id': threadId, 'p_user_id': userId},
    );
    logger.i('ChatRepository → participant removed');
  }

  Future<void> deleteThread(String threadId) async {
    logger.d('ChatRepository → deleteThread: $threadId');
    await _supabase.rpc(
      'delete_chat_thread',
      params: {'p_thread_id': threadId},
    );
    logger.i('ChatRepository → thread deleted');
  }

  // ─── Direct Threads ───────────────────────────────────────────────────────────

  /// Finds an existing 1-on-1 direct thread with [verifierId], or creates one.
  Future<String> getOrCreateDirectThread(String verifierId) async {
    logger.d('ChatRepository → getOrCreateDirectThread: verifierId=$verifierId');
    final result = await _supabase.rpc(
      'get_or_create_direct_thread',
      params: {'p_verifier_id': verifierId},
    );
    final threadId = result as String;
    logger.i('ChatRepository → direct thread: $threadId');
    return threadId;
  }

  /// Returns all messages that mention a specific order (for communication history).
  Future<List<ChatMessage>> getOrderCommunicationHistory(String orderId) async {
    logger.d('ChatRepository → getOrderCommunicationHistory: $orderId');
    final data = await _supabase
        .from('chat_messages')
        .select('*, thread:chat_threads(title)')
        .eq('order_mention_id', orderId)
        .order('created_at', ascending: false);

    final messages = data.map(ChatMessage.fromMap).toList();
    logger.i('ChatRepository → ${messages.length} history messages for order $orderId');
    return messages;
  }
}
