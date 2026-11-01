import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import '../models/chat_message.dart';
import '../models/chat_conversation.dart';
import '../models/profile.dart';

class ChatService {
  static final ChatService instance = ChatService._internal();
  factory ChatService() => instance;
  ChatService._internal();

  final Logger _logger = Logger();

  SupabaseClient get _client => SupabaseService.instance.client;

  String _displayNameFromRow(Map<String, dynamic> row) {
    final profile = Profile.fromJson(row);
    final name = (profile.name ?? '').trim();
    final surname = (profile.surname ?? '').trim();

    // Dedupe: if `name` already contains the surname (e.g. user entered
    // "Keith Flanagan" in the name field and "Flanagan" as surname),
    // don't append it again.
    String fullName;
    if (name.isEmpty && surname.isEmpty) {
      fullName = '';
    } else if (name.isEmpty) {
      fullName = surname;
    } else if (surname.isEmpty) {
      fullName = name;
    } else {
      final nameTokens = name
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toSet();
      if (nameTokens.contains(surname.toLowerCase())) {
        fullName = name;
      } else {
        fullName = '$name $surname';
      }
    }

    if (fullName.isNotEmpty) return fullName;
    return profile.email ?? 'Unknown user';
  }

  Future<ChatConversation> getOrCreateAdminConversation(String userId) async {
    try {
      final existing = await _client
          .from('chat_conversations')
          .select('id,is_admin,created_at')
          .eq('is_admin', true)
          .contains('participant_ids', [userId])
          .maybeSingle();
      if (existing != null) {
        return ChatConversation(
          id: existing['id'] as String,
          isAdmin: true,
          createdAt: DateTime.parse(existing['created_at'] as String),
          participantIds: [userId],
        );
      }

      final inserted = await _client
          .from('chat_conversations')
          .insert({
            'is_admin': true,
            'participant_ids': [userId],
          })
          .select()
          .single();

      return ChatConversation(
        id: inserted['id'] as String,
        isAdmin: true,
        createdAt: DateTime.parse(inserted['created_at'] as String),
        participantIds: [userId],
      );
    } catch (e) {
      _logger.e('Failed to get/create admin conversation: $e');
      rethrow;
    }
  }

  Future<ChatConversation> getOrCreateConversationWithPartner(
    String userId,
    String partnerUserId,
  ) async {
    try {
      final participants = [userId, partnerUserId]..sort();
      final existing = await _client
          .from('chat_conversations')
          .select('id,is_admin,created_at,participant_ids')
          .eq('is_admin', false)
          .contains('participant_ids', participants)
          .maybeSingle();
      if (existing != null) {
        return ChatConversation.fromMap(existing);
      }
      final inserted = await _client
          .from('chat_conversations')
          .insert({'is_admin': false, 'participant_ids': participants})
          .select()
          .single();
      return ChatConversation.fromMap(inserted);
    } catch (e) {
      _logger.e('Failed to get/create partner conversation: $e');
      rethrow;
    }
  }

  Future<ChatConversation?> fetchConversationById(String id) async {
    try {
      final row = await _client
          .from('chat_conversations')
          .select('id,is_admin,created_at,participant_ids')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return ChatConversation.fromMap(row);
    } catch (e) {
      _logger.e('Failed to fetch conversation $id: $e');
      return null;
    }
  }

  Future<List<ChatConversation>> fetchConversationsForCurrentUser() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) throw Exception('Not authenticated');
    try {
      final rows = await _client
          .from('chat_conversations')
          .select('id,is_admin,created_at,participant_ids')
          .contains('participant_ids', [user.id]);
      return (rows as List<dynamic>)
          .map((e) => ChatConversation.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Failed to fetch conversations: $e');
      rethrow;
    }
  }

  Future<List<ChatConversation>> fetchAllAdminConversations() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) throw Exception('Not authenticated');
    try {
      final rows = await _client
          .from('chat_conversations')
          .select('id,is_admin,created_at,participant_ids')
          .eq('is_admin', true)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>)
          .map((e) => ChatConversation.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Failed to fetch admin conversations: $e');
      rethrow;
    }
  }

  /// Returns the number of conversations for the current user that contain
  /// at least one unread message (sent by someone else and not yet in the
  /// user's `read_by` array).
  ///
  /// A message is treated as read if EITHER the user is already in its
  /// `read_by` array OR the conversation's locally-stored "last read"
  /// timestamp is at/after the message. The local timestamp is written every
  /// time the user opens the thread, so simply opening (reading) a
  /// conversation reliably clears its unread state even if the RLS-gated
  /// `read_by` update on messages the user did not send is delayed or blocked.
  Future<int> fetchUnreadConversationCount() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return 0;
    try {
      final conversations = await fetchConversationsForCurrentUser();
      if (conversations.isEmpty) return 0;
      final ids = conversations.map((c) => c.id).toList(growable: false);

      final rows = await _client
          .from('chat_messages')
          .select('conversation_id,sender_id,read_by,created_at')
          .inFilter('conversation_id', ids)
          .neq('sender_id', user.id);

      final prefs = await SharedPreferences.getInstance();
      final lastReadCache = <String, DateTime?>{};

      final unreadConvos = <String>{};
      for (final row in rows as List<dynamic>) {
        final convId = row['conversation_id'] as String?;
        if (convId == null) continue;

        final readByRaw = row['read_by'];
        final readBy = readByRaw is List
            ? readByRaw.map((e) => e.toString()).toSet()
            : <String>{};
        if (readBy.contains(user.id)) continue;

        // Respect the locally-stored "last read" marker written when the user
        // opens the conversation thread.
        final lastRead = lastReadCache.putIfAbsent(convId, () {
          final millis = prefs.getInt('chat_last_read_$convId');
          return millis != null
              ? DateTime.fromMillisecondsSinceEpoch(millis)
              : null;
        });

        final createdRaw = row['created_at'];
        final createdAt = createdRaw is String
            ? DateTime.tryParse(createdRaw)
            : null;
        if (lastRead != null &&
            createdAt != null &&
            !createdAt.isAfter(lastRead)) {
          continue;
        }

        unreadConvos.add(convId);
      }
      return unreadConvos.length;
    } catch (e) {
      _logger.w('Failed to compute unread count: $e');
      return 0;
    }
  }

  Future<Map<String, ChatMessage>> fetchLatestMessagesForConversations(
    List<String> conversationIds,
  ) async {
    if (conversationIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('chat_messages')
          .select('id,conversation_id,sender_id,content,created_at')
          .inFilter('conversation_id', conversationIds)
          .order('created_at', ascending: false);

      final latest = <String, ChatMessage>{};
      for (final map in rows as List<dynamic>) {
        final conversationId = map['conversation_id'] as String?;
        if (conversationId == null) continue;
        if (latest.containsKey(conversationId)) continue;
        latest[conversationId] = ChatMessage.fromMap(map);
      }
      return latest;
    } catch (e) {
      _logger.e('Failed to fetch latest messages: $e');
      return {};
    }
  }

  /// Returns the number of admin support conversations that have at least
  /// one unread message (sent by someone other than the current admin and
  /// newer than the locally-stored "last read" timestamp for that
  /// conversation). Mirrors the logic used by `AdminSupportInboxScreen`.
  Future<int> fetchAdminUnreadConversationCount() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return 0;
    try {
      final conversations = await fetchAllAdminConversations();
      if (conversations.isEmpty) return 0;
      final ids = conversations.map((c) => c.id).toList(growable: false);
      final latest = await fetchLatestMessagesForConversations(ids);
      if (latest.isEmpty) return 0;

      final prefs = await SharedPreferences.getInstance();
      var count = 0;
      latest.forEach((conversationId, msg) {
        if (msg.senderId == user.id) return;
        final lastReadMillis = prefs.getInt('chat_last_read_$conversationId');
        final lastRead = lastReadMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis)
            : null;
        if (lastRead == null || msg.createdAt.isAfter(lastRead)) {
          count++;
        }
      });
      return count;
    } catch (e) {
      _logger.w('Failed to compute admin unread count: $e');
      return 0;
    }
  }

  Future<Map<String, String>> fetchDisplayNames(List<String> userIds) async {
    final ids = userIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('profiles')
          .select('id,name,surname,email')
          .inFilter('id', ids);

      final names = <String, String>{};
      for (final map in rows as List<dynamic>) {
        final id = map['id'] as String?;
        if (id == null) continue;
        names[id] = _displayNameFromRow(map);
      }
      return names;
    } catch (e) {
      _logger.e('Failed to fetch display names: $e');
      return {};
    }
  }

  Future<Map<String, String>> fetchProfilePhotoUrls(List<String> userIds) async {
    final ids = userIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('profiles')
          .select('id,profile_photo_url')
          .inFilter('id', ids);

      final photos = <String, String>{};
      for (final map in rows as List<dynamic>) {
        final id = map['id'] as String?;
        final url = map['profile_photo_url'] as String?;
        if (id != null && url != null && url.trim().isNotEmpty) {
          photos[id] = url.trim();
        }
      }
      return photos;
    } catch (e) {
      _logger.w('Failed to fetch profile photos: $e');
      return {};
    }
  }

  Stream<List<ChatMessage>> streamMessages(String conversationId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows.map((e) => ChatMessage.fromMap(e)).toList());
  }

  Future<void> markMessagesAsRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      _logger.i('Marking messages as read for user: $userId');
      // Get all messages in this conversation not sent by the user
      final messages = await _client
          .from('chat_messages')
          .select('id,read_by,sender_id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId);

      for (final msg in messages) {
        final messageId = msg['id'] as String;
        final readByRaw = msg['read_by'];
        List<String> readBy = [];

        // Handle both List and null cases
        if (readByRaw is List) {
          readBy = readByRaw.map((e) => e.toString()).toList();
        }

        // Only update if user hasn't read it yet
        if (!readBy.contains(userId)) {
          readBy.add(userId);
          _logger.i('Updating message $messageId with readBy: $readBy');

          await _client
              .from('chat_messages')
              .update({'read_by': readBy})
              .eq('id', messageId);

          _logger.i('Message $messageId marked as read');
        }
      }
    } catch (e) {
      _logger.e('Failed to mark messages as read: $e');
    }
  }

  Future<void> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) throw Exception('Not authenticated');
    try {
      await _client.from('chat_messages').insert({
        'conversation_id': conversationId,
        'sender_id': user.id,
        'content': content,
      });

      // Send email notification to recipient (non-blocking)
      _sendChatEmailNotification(
        conversationId: conversationId,
        senderId: user.id,
        messageContent: content,
      );
    } catch (e) {
      if (e.toString().contains('over_email_send_rate_limit')) {
        throw Exception('Too many attempts. Please wait...');
      }
      if (kDebugMode) {
        _logger.e('sendMessage failed: $e');
      }
      rethrow;
    }
  }

  Future<void> _sendChatEmailNotification({
    required String conversationId,
    required String senderId,
    required String messageContent,
  }) async {
    try {
      // Get conversation to find recipient
      final conversation = await fetchConversationById(conversationId);
      if (conversation == null) return;

      // Get sender display name (prefer business name, fallback to profile name)
      String senderName;
      final businessName = await fetchBusinessNameForUser(senderId);
      if (businessName != null && businessName.isNotEmpty) {
        senderName = businessName;
      } else {
        final names = await fetchDisplayNames([senderId]);
        senderName = names[senderId] ?? 'A Local Lekker user';
      }

      if (conversation.isAdmin) {
        // Support conversation: participant_ids contains only the member/TP.
        // - If sender IS a participant → member/TP sent the message → notify admin(s).
        // - If sender is NOT a participant → admin replied → notify the member/TP.
        final senderIsParticipant =
            conversation.participantIds.contains(senderId);

        if (senderIsParticipant) {
          // Member/TP → admin notification (edge function looks up admin profiles)
          await _client.functions.invoke(
            'send-chat-message-email',
            body: {
              'notify_admin': true,
              'sender_name': senderName,
              'message_preview': messageContent,
            },
          );
          _logger.i('Support email dispatched to admin(s) from $senderName');
        } else {
          // Admin → member/TP notification
          final recipientId = conversation.participantIds.isNotEmpty
              ? conversation.participantIds.first
              : '';
          if (recipientId.isEmpty) return;
          await _client.functions.invoke(
            'send-chat-message-email',
            body: {
              'recipient_id': recipientId,
              'sender_name': senderName,
              'message_preview': messageContent,
            },
          );
          _logger.i('Support reply email sent to member $recipientId');
        }
        return;
      }

      // Regular P2P conversation: find the other participant
      final recipientId = conversation.participantIds.firstWhere(
        (id) => id != senderId,
        orElse: () => '',
      );
      if (recipientId.isEmpty) return;

      await _client.functions.invoke(
        'send-chat-message-email',
        body: {
          'recipient_id': recipientId,
          'sender_name': senderName,
          'message_preview': messageContent,
        },
      );
      _logger.i('Chat message email sent to recipient $recipientId');
    } catch (e) {
      _logger.w('Could not send chat message email: $e');
    }
  }

  Future<List<Map<String, dynamic>>> searchTrustedPartnersByBusiness(
    String query,
  ) async {
    try {
      final rows = await _client
          .from('businesses')
          .select('id,name,owner_member_id')
          .ilike('name', '%$query%')
          .limit(10);
      return (rows as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _logger.e('searchTrustedPartnersByBusiness failed: $e');
      return [];
    }
  }

  Future<String?> fetchBusinessNameForUser(String userId) async {
    try {
      final rows = await _client
          .from('businesses')
          .select('name')
          .eq('owner_member_id', userId)
          .maybeSingle();
      if (rows != null) {
        return rows['name'] as String?;
      }
      return null;
    } catch (e) {
      _logger.w('Failed to fetch business name for user $userId: $e');
      return null;
    }
  }

  /// Returns the business `logo_url` for a trusted partner user, or null if
  /// the user does not own a business or no logo is set.
  Future<String?> fetchBusinessLogoForUser(String userId) async {
    try {
      final row = await _client
          .from('businesses')
          .select('logo_url')
          .eq('owner_member_id', userId)
          .maybeSingle();
      if (row != null) {
        final url = row['logo_url'];
        if (url is String && url.trim().isNotEmpty) return url;
      }
      return null;
    } catch (e) {
      _logger.w('Failed to fetch business logo for user $userId: $e');
      return null;
    }
  }

  /// Subscribes to realtime changes on `chat_messages` so consumers (e.g. the
  /// AppBar unread badge) can refresh instantly when any message is inserted
  /// or updated. The caller is responsible for unsubscribing the returned
  /// channel during dispose. The [onChange] callback is invoked on every
  /// insert/update event in the table.
  RealtimeChannel subscribeToChatMessageChanges({
    required void Function() onChange,
    String? channelTag,
  }) {
    final user = SupabaseService.instance.getCurrentUser();
    final tag = channelTag ?? user?.id ?? 'anon';
    final channel = _client
        .channel('chat_messages_realtime_$tag')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            if (kDebugMode) {
              debugPrint('[REALTIME chat_messages INSERT] ${payload.newRecord}');
            }
            onChange();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            if (kDebugMode) {
              debugPrint('[REALTIME chat_messages UPDATE] ${payload.newRecord}');
            }
            onChange();
          },
        )
        .subscribe();
    return channel;
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      // First delete all messages in the conversation
      await _client
          .from('chat_messages')
          .delete()
          .eq('conversation_id', conversationId);

      // Then delete the conversation itself
      await _client
          .from('chat_conversations')
          .delete()
          .eq('id', conversationId);

      _logger.i('Deleted conversation: $conversationId');
    } catch (e) {
      _logger.e('Failed to delete conversation: $e');
      rethrow;
    }
  }

  Future<void> recordLastRead(String conversationId, DateTime readAt) async {
    try {
      // Optional persistence of last read in DB if column/policy exists
      await _client
          .from('chat_conversations')
          .update({'last_read_at': readAt.toIso8601String()})
          .eq('id', conversationId);
    } catch (e) {
      // Best-effort only; keep local tracking regardless
      _logger.w('Failed to persist last_read_at for $conversationId: $e');
    }
  }

  Future<Map<String, String>> fetchBusinessNamesForUsers(
    List<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('businesses')
          .select('owner_member_id,name')
          .inFilter('owner_member_id', ids);
      final result = <String, String>{};
      for (final row in rows as List<dynamic>) {
        final ownerId = row['owner_member_id'] as String?;
        final name = row['name'] as String?;
        if (ownerId != null && name != null && name.trim().isNotEmpty) {
          result[ownerId] = name;
        }
      }
      return result;
    } catch (e) {
      _logger.w('Failed to fetch business names: $e');
      return {};
    }
  }

  Future<Map<String, String>> fetchBusinessLogosForUsers(
    List<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('businesses')
          .select('owner_member_id,logo_url')
          .inFilter('owner_member_id', ids);
      final result = <String, String>{};
      for (final row in rows as List<dynamic>) {
        final ownerId = row['owner_member_id'] as String?;
        final logo = row['logo_url'] as String?;
        if (ownerId != null && logo != null && logo.trim().isNotEmpty) {
          result[ownerId] = logo.trim();
        }
      }
      return result;
    } catch (e) {
      _logger.w('Failed to fetch business logos: $e');
      return {};
    }
  }
}
