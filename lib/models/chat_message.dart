class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final List<String> readBy;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.readBy = const [],
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final readByRaw = map['read_by'];
    List<String> readBy = [];
    if (readByRaw is List) {
      readBy = readByRaw.map((e) => e.toString()).toList();
    }

    return ChatMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      content: map['content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      readBy: readBy,
    );
  }

  bool isReadBy(String userId) => readBy.contains(userId);
}
