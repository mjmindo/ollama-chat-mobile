import 'package:flutter/material.dart';

class VoiceModeFeedbackOverlay extends StatelessWidget {
  final bool isListening;
  final bool isSpeaking;
  final bool isLoading;
  final VoidCallback onExitVoiceMode;

  const VoiceModeFeedbackOverlay(
      {super.key,
      required this.isListening,
      required this.isSpeaking,
      required this.isLoading,
      required this.onExitVoiceMode});

  String get _statusText => isLoading
      ? "Processing..."
      : (isSpeaking
          ? "Speaking..."
          : (isListening ? "Listening..." : "Voice Mode Active"));
  IconData get _statusIcon => isLoading
      ? Icons.hourglass_empty
      : (isSpeaking
          ? Icons.volume_up
          : (isListening ? Icons.mic : Icons.record_voice_over));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      elevation: 2.0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            Icon(_statusIcon,
                color: theme.colorScheme.onPrimaryContainer, size: 24),
            const SizedBox(width: 12.0),
            Expanded(
                child: Text(_statusText,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis)),
            IconButton(
                icon: const Icon(Icons.close),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onPrimaryContainer,
                onPressed: onExitVoiceMode,
                tooltip: 'Exit Voice Mode'),
          ],
        ),
      ),
    );
  }
}