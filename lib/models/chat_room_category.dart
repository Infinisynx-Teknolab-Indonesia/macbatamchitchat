class ChatRoomCategory {
  final String name;
  final List<ChatRoomCategory> subcategories;
  final List<ChatRoomInfo> rooms;

  const ChatRoomCategory({
    required this.name,
    this.subcategories = const [],
    this.rooms = const [],
  });
}

class ChatRoomInfo {
  final String name;
  final int userCount;

  const ChatRoomInfo({required this.name, required this.userCount});
}
