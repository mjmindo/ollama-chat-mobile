import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final dynamic messageKey;
  final bool isCurrentlySpeaking;
  final bool isAnyMessageSpeaking;
  final void Function(String text, dynamic messageKey)? onSpeak;
  final VoidCallback? onStop;
  final void Function(String text)? onCopy;

  const ChatBubble(
      {required this.message,
      this.messageKey,
      this.isCurrentlySpeaking = false,
      this.isAnyMessageSpeaking = false,
      this.onSpeak,
      this.onStop,
      this.onCopy,
      super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final bool canControlSpeech = !isUser &&
        message.text.isNotEmpty &&
        (onSpeak != null || onStop != null);

    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge,
      code: theme.textTheme.bodyMedium!.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1)),
      codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: theme.dividerColor)),
    );

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser)
              const Padding(
                  padding: EdgeInsets.only(right: 8.0, top: 4.0),
                  child: CircleAvatar(
                      backgroundImage: AssetImage('assets/icon.png'),
                      backgroundColor: Colors.transparent)),
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                padding: const EdgeInsets.symmetric(
                    vertical: 10.0, horizontal: 14.0),
                decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16.0)),
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.imagePath != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: Image.file(File(message.imagePath!),
                                  height: 150, fit: BoxFit.cover)),
                        ),
                      MarkdownBody(
                          data: message.text,
                          styleSheet: markdownStyle,
                          selectable: true),
                      if (!isUser && message.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canControlSpeech)
                                if (isCurrentlySpeaking)
                                  IconButton(
                                    icon:
                                        const Icon(Icons.stop_circle_outlined),
                                    color: theme.colorScheme.primary,
                                    iconSize: 20,
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Stop reading',
                                    onPressed: onStop,
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.volume_up_outlined),
                                    iconSize: 20,
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Read aloud',
                                    onPressed: (isAnyMessageSpeaking || onSpeak == null)
                                        ? null
                                        : () => onSpeak!(message.text, messageKey),
                                  ),
                              if (onCopy != null)
                                IconButton(
                                  icon: const Icon(Icons.copy_outlined),
                                  iconSize: 20,
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Copy text',
                                  onPressed: () => onCopy!(message.text),
                                ),
                            ],
                          ),
                        )
                    ],
                  ),
                ),
              ),
            ),
            if (isUser)
              const Padding(
                  padding: EdgeInsets.only(left: 8.0, top: 4.0),
                  child: CircleAvatar(child: Icon(Icons.person_outline))),
          ],
        ),
      ],
    );
  }
}