import 'package:hive_flutter/hive_flutter.dart';
import 'models/chat_message.dart';
import 'models/conversation.dart';

Future<void> initializeHive() async {
  await Hive.initFlutter();

  Hive.registerAdapter(ConversationAdapter());
  Hive.registerAdapter(ChatMessageAdapter());

  await Hive.openBox<Conversation>('conversations');
  await Hive.openBox<ChatMessage>('messages');
  await Hive.openBox('appState');
}