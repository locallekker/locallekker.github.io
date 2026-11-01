import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/chat_conversation.dart';
import '../../models/chat_message.dart';
import '../../services/chat_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/profile_photo.dart';
import '../../widgets/branded_app_bar.dart';
import '../chat/chat_thread_page.dart';
import 'admin_chat_page.dart';

/// Inbox for a Trusted Partner showing all member conversations.
/// Excludes the partner's own admin-support thread (still reachable via the
/// Support button in the app bar).
class TrustedPartnerInboxPage extends StatefulWidget {
  const TrustedPartnerInboxPage({super.key});

  @override
  State<TrustedPartnerInboxPage> createState() =>
      _TrustedPartnerInboxPageState();
}

class _TrustedPartnerInboxPageState extends State<TrustedPartnerInboxPage> {
  final Logger _logger = Logger();

  bool _loading = true;
  String? _partnerId;
  List<ChatConversation> _conversations = [];
  final Map<String, ChatMessage> _latestMessages = {};
  final Map<String, String> _memberNames = {};
  final Map<String, String> _businessNames = {};
  final Map<String, String> _memberProfilePhotos = {};
  final Map<String, String> _businessLogos = {};
  final Map<String, bool> _hasUnread = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _prefKey(String conversationId) => 'chat_last_read_$conversationId';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('Not authenticated');
      _partnerId = user.id;

      final all = await ChatService.instance.fetchConversationsForCurrentUser();

      // Only show member ↔ partner conversations (exclude admin-support thread).
      final memberConvos = all.where((c) => !c.isAdmin).toList();

      final ids = memberConvos.map((c) => c.id).toList();
      final latest =
          await ChatService.instance.fetchLatestMessagesForConversations(ids);

      memberConvos.sort((a, b) {
        final am = latest[a.id]?.createdAt ?? a.createdAt;
        final bm = latest[b.id]?.createdAt ?? b.createdAt;
        return bm.compareTo(am);
      });

      final memberIds = <String>{};
      for (final c in memberConvos) {
        final others = c.participantIds.where((id) => id != _partnerId);
        if (others.isEmpty && c.participantIds.isNotEmpty) {
          // Fall back to first participant (e.g. self-chat or malformed convo)
          memberIds.add(c.participantIds.first);
        } else {
          memberIds.addAll(others);
        }
      }
      final names =
          await ChatService.instance.fetchDisplayNames(memberIds.toList());
      final businessNames = await ChatService.instance
          .fetchBusinessNamesForUsers(memberIds.toList());
      final profilePhotos = await ChatService.instance.fetchProfilePhotoUrls(
        memberIds.toList(),
      );
      final businessLogos = await ChatService.instance
          .fetchBusinessLogosForUsers(memberIds.toList());

      final prefs = await SharedPreferences.getInstance();
      final unread = <String, bool>{};
      latest.forEach((conversationId, msg) {
        final lastReadMillis = prefs.getInt(_prefKey(conversationId));
        final lastRead = lastReadMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis)
            : null;
        final isUnread =
            (lastRead == null || msg.createdAt.isAfter(lastRead)) &&
            msg.senderId != _partnerId;
        unread[conversationId] = isUnread;
      });

      if (!mounted) return;
      setState(() {
        _conversations = memberConvos;
        _latestMessages
          ..clear()
          ..addAll(latest);
        _memberNames
          ..clear()
          ..addAll(names);
        _businessNames
          ..clear()
          ..addAll(businessNames);
        _memberProfilePhotos
          ..clear()
          ..addAll(profilePhotos);
        _businessLogos
          ..clear()
          ..addAll(businessLogos);
        _hasUnread
          ..clear()
          ..addAll(unread);
      });
    } catch (e) {
      _logger.e('Failed to load partner inbox: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load messages: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _memberLabel(ChatConversation c) {
    final memberId = _memberId(c);
    if (memberId.isEmpty) return 'Member';
    // Trusted partners are identified by their business name, not their
    // personal profile name.
    final businessName = _businessNames[memberId];
    if (businessName != null && businessName.trim().isNotEmpty) {
      return businessName;
    }
    return _memberNames[memberId] ?? 'Member';
  }

  String _memberId(ChatConversation c) => c.participantIds.firstWhere(
    (id) => id != _partnerId,
    orElse: () => c.participantIds.isNotEmpty ? c.participantIds.first : '',
  );

  String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Member Messages'),
        actions: [
          IconButton(
            tooltip: 'Support Chat',
            icon: const Icon(Icons.support_agent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminChatPage()),
              ).then((_) => _load());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _conversations.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No member messages yet.\n\nWhen members message your business, their chats will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final c = _conversations[index];
                      final latest = _latestMessages[c.id];
                      final unread = _hasUnread[c.id] ?? false;
                      final memberId = _memberId(c);
                      final logo = _businessLogos[memberId];
                      final profilePhoto = (logo != null && logo.isNotEmpty)
                          ? logo
                          : _memberProfilePhotos[memberId];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: ProfilePhoto(
                            size: 40,
                            imageUrl: profilePhoto,
                            displayName: _memberLabel(c),
                            backgroundColor:
                                unread ? Colors.red : Colors.grey.shade300,
                            foregroundColor:
                                unread ? Colors.white : Colors.black54,
                            fit: BoxFit.cover,
                          ),
                          title: Text(
                            _memberLabel(c),
                            style: TextStyle(
                              fontWeight:
                                  unread ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            latest?.content ?? 'No messages yet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatWhen(
                                  latest?.createdAt ?? c.createdAt,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (unread)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatThreadPage(
                                  conversationId: c.id,
                                ),
                              ),
                            ).then((_) => _load());
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
