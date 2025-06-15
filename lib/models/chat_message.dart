import 'package:hive/hive.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 0)
class ChatMessage extends HiveObject {
  @HiveField(0)
  String text;
  @HiveField(1)
  final bool isUser;
  @HiveField(2)
  final String? imagePath;
  @HiveField(3)
  final String conversationId;

  ChatMessage(
      {required this.text,
      required this.isUser,
      this.imagePath,
      required this.conversationId});
}