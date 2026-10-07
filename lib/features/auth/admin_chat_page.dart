import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../models/chat_conversation.dart';
import '../../services/chat_service.dart';
import '../../services/supabase_service.dart';
import '../chat/chat_thread_page.dart';

/// Thin launcher for the member <-> admin support conversation.
///
/// Mirrors the member <-> trusted-partner flow used in `ChatListPage`:
/// resolve (or create) the conversation once, then render the standard
/// [ChatThreadPage] in-place. Previously this screen showed its own
/// loading spinner and then `pushReplacement`-ed into [ChatThreadPage],
/// which combined with the thread page rebuilding its message stream on
/// every `setState` produced a visible "continuously loading" flash.
class AdminChatPage extends StatefulWidget {
  const AdminChatPage({super.key});

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final Logger _logger = Logger();
  late final Future<ChatConversation?> _conversationFuture;

  @override
  void initState() {
    super.initState();
    _conversationFuture = _resolveConversation();
  }

  Future<ChatConversation?> _resolveConversation() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      _logger.e('No user authenticated for admin chat');
      return null;
    }
    try {
      return await ChatService.instance.getOrCreateAdminConversation(user.id);
    } catch (e) {
      _logger.e('Failed to initialize admin chat: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChatConversation?>(
      future: _conversationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: BrandedAppBar(
              title: const Text('Support Chat'),
              showChatButton: false,
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading support chat...'),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: BrandedAppBar(
              title: const Text('Support Chat'),
              showChatButton: false,
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to open support chat:\n${snapshot.error ?? "Not signed in"}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          );
        }

        // Render the standard chat thread page in-place, exactly like
        // the member <-> trusted-partner flow in ChatListPage.
        return ChatThreadPage(conversationId: snapshot.data!.id);
      },
    );
  }
}
