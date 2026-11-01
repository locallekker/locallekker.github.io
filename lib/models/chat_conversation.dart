class ChatConversation {
  final String id;
  final bool isAdmin;
  final DateTime createdAt;
  final List<String> participantIds;

  ChatConversation({
    required this.id,
    required this.isAdmin,
    required this.createdAt,
    required this.participantIds,
  });

  factory ChatConversation.fromMap(Map<String, dynamic> map) {
    final rawParticipants =
        map['participant_ids'] ?? map['participants']; // support legacy key
    return ChatConversation(
      id: map['id'] as String,
      isAdmin: (map['is_admin'] as bool?) ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      participantIds:
          (rawParticipants as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}
