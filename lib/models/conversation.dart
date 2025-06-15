import 'package:hive/hive.dart';

part 'conversation.g.dart';

@HiveType(typeId: 1)
class Conversation extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String title;
  @HiveField(2)
  List<int>? context;
  @HiveField(3)
  DateTime createdAt;

  Conversation(
      {required this.id,
      required this.title,
      this.context,
      required this.createdAt});
}