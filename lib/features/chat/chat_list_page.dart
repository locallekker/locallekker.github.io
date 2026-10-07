import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:local_lekker/widgets/profile_photo.dart';
import '../../services/chat_service.dart';
import '../../services/supabase_service.dart';
import '../../models/chat_conversation.dart';
import '../../models/chat_message.dart';
import 'chat_thread_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final Logger _logger = Logger();
  final TextEditingController _searchController = TextEditingController();
  List<ChatConversation> _conversations = [];
  final Map<String, ChatMessage> _latestMessages = {};
  final Map<String, String> _displayNames = {};
  final Map<String, String> _businessNames = {};
  final Map<String, bool> _hasUnread = {};
  final Map<String, String> _profilePhotos = {};
  String? _currentUserId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _loading = true);
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('Not authenticated');

      _logger.i('Loading conversations for user: ${user.id} (${user.email})');
      _currentUserId = user.id;
      _conversations = await ChatService.instance
          .fetchConversationsForCurrentUser();

      _logger.i('Fetched ${_conversations.length} conversations');
      for (final conv in _conversations) {
        _logger.i(
          '  Conversation ${conv.id}: participants=${conv.participantIds}',
        );
      }

      final conversationIds = _conversations
          .map((c) => c.id)
          .toList(growable: false);
      final latestMessages = await ChatService.instance
          .fetchLatestMessagesForConversations(conversationIds);

      _logger.i(
        'Fetched latest messages for ${latestMessages.length} conversations',
      );

      final otherUserIds = <String>{};
      for (final conversation in _conversations) {
        otherUserIds.addAll(
          conversation.participantIds.where((id) => id != user.id),
        );
        final latest = latestMessages[conversation.id];
        if (latest != null) {
          otherUserIds.add(latest.senderId);
        }
      }

      _logger.i(
        'Fetching display names for ${otherUserIds.length} users: $otherUserIds',
      );
      final names = await ChatService.instance.fetchDisplayNames(
        otherUserIds.toList(),
      );

      final businessNames = await ChatService.instance
          .fetchBusinessNamesForUsers(otherUserIds.toList());
      final profilePhotos = await ChatService.instance.fetchProfilePhotoUrls(
        otherUserIds.toList(),
      );

      _logger.i('Fetched names: $names');

      final prefs = await SharedPreferences.getInstance();
      final unreadMap = <String, bool>{};
      latestMessages.forEach((conversationId, msg) {
        final lastReadMillis = prefs.getInt(_prefKey(conversationId));
        final lastRead = lastReadMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis)
            : null;
        final isUnread =
            (lastRead == null || msg.createdAt.isAfter(lastRead)) &&
            msg.senderId != user.id;
        unreadMap[conversationId] = isUnread;
      });

      _latestMessages
        ..clear()
        ..addAll(latestMessages);
      _displayNames
        ..clear()
        ..addAll(names);
      _businessNames
        ..clear()
        ..addAll(businessNames);
      _profilePhotos
        ..clear()
        ..addAll(profilePhotos);
      _hasUnread
        ..clear()
        ..addAll(unreadMap);
    } catch (e) {
      _logger.e('Failed to load conversations: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Messages'),
        showChatButton: false,
        actions: [
          IconButton(
            tooltip: 'Chat with Admin',
            icon: const Icon(Icons.support_agent),
            onPressed: _startAdminChat,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search businesses to chat',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: _searchAndStartWithPartner,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () =>
                      _searchAndStartWithPartner(_searchController.text),
                  child: const Text('Start'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_conversations.isEmpty)
              const Center(child: Text('No conversations yet'))
            else
              ..._conversations.map((c) => _conversationTile(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingAvatar(
    ChatConversation c,
    String? otherId,
    bool showUnread,
    bool isAdmin,
  ) {
    return ProfilePhoto(
      size: 40,
      imageUrl: otherId != null ? _profilePhotos[otherId] : null,
      displayName: isAdmin ? null : _conversationTitle(c, isAdmin),
      backgroundColor: showUnread ? Colors.red : Colors.grey.shade300,
      foregroundColor: showUnread ? Colors.white : Colors.black87,
      fallbackIcon: isAdmin ? Icons.support_agent : Icons.store,
      fit: BoxFit.cover,
    );
  }

  Widget _conversationTile(ChatConversation c) {
    final isAdmin = c.isAdmin;
    final latest = _latestMessages[c.id];

    final title = _conversationTitle(c, isAdmin);

    final others = c.participantIds
        .where((id) => id != _currentUserId)
        .toList();
    final otherId = others.isNotEmpty
      ? others.first
      : (latest != null && latest.senderId != _currentUserId
          ? latest.senderId
          : null);

    final subtitle = latest != null ? latest.content : 'No messages yet';
    final showUnread = _hasUnread[c.id] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: showUnread
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            )
          : null,
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: _buildLeadingAvatar(c, otherId, showUnread, isAdmin),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: showUnread ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showUnread)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete conversation',
                onPressed: () => _confirmDeleteConversation(c),
              ),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatThreadPage(conversationId: c.id),
              ),
            ).then((_) => _loadConversations());
          },
        ),
      ),
    );
  }

  String _conversationTitle(ChatConversation c, bool isAdmin) {
    if (isAdmin) return 'Local Lekker Club';
    final others = c.participantIds
        .where((id) => id != _currentUserId)
        .toList();
    if (others.isEmpty) return 'Conversation';

    final otherId = others.first;

    // If the other user has a business, prefer business name
    final otherBusiness = _businessNames[otherId];
    if (otherBusiness != null && otherBusiness.trim().isNotEmpty) {
      return otherBusiness;
    }

    // Fallback to member name
    final otherName = _displayNames[otherId];
    if (otherName != null && otherName.trim().isNotEmpty) {
      return otherName;
    }

    return 'Conversation';
  }

  String _prefKey(String conversationId) => 'chat_last_read_$conversationId';

  Future<void> _startAdminChat() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;
    try {
      final conv = await ChatService.instance.getOrCreateAdminConversation(
        user.id,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatThreadPage(conversationId: conv.id),
        ),
      );
    } catch (e) {
      _logger.e('Failed to start admin chat: $e');
    }
  }

  Future<void> _searchAndStartWithPartner(String query) async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final results = await ChatService.instance.searchTrustedPartnersByBusiness(
      trimmed,
    );
    if (results.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching businesses found')),
      );
      return;
    }
    final business = results.first;
    final partnerUserId = business['owner_member_id'] as String;
    final conv = await ChatService.instance.getOrCreateConversationWithPartner(
      user.id,
      partnerUserId,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatThreadPage(conversationId: conv.id),
      ),
    );
  }

  Future<void> _confirmDeleteConversation(ChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text(
          'Are you sure you want to delete this conversation? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteConversation(conversation.id);
    }
  }

  Future<void> _deleteConversation(String conversationId) async {
    try {
      await ChatService.instance.deleteConversation(conversationId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Conversation deleted')));
      await _loadConversations();
    } catch (e) {
      _logger.e('Failed to delete conversation: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete conversation')),
      );
    }
  }
}
