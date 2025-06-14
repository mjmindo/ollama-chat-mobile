import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

part 'main.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(ChatMessageAdapter());
  await Hive.openBox<ChatMessage>('chatHistory');
  await Hive.openBox('appState');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ollama Flutter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const OllamaChatPage(),
    );
  }
}

@HiveType(typeId: 0)
class ChatMessage {
  @HiveField(0)
  final String text;
  @HiveField(1)
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class OllamaChatPage extends StatefulWidget {
  const OllamaChatPage({super.key});

  @override
  State<OllamaChatPage> createState() => _OllamaChatPageState();
}

class _OllamaChatPageState extends State<OllamaChatPage> {
  final _controller = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  
  // SYSTEM PROMPT: Add a controller for the new memory/system prompt text field.
  late TextEditingController _systemPromptController;

  http.Client? _client;
  bool _isManuallyStopped = false;
  late Box<ChatMessage> _chatBox;
  late Box _appStateBox;
  List<int>? _conversationContext;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: 'http://localhost:11434');
    _modelController = TextEditingController(text: 'llama3');
    
    // SYSTEM PROMPT: Initialize the controller.
    _systemPromptController = TextEditingController();

    _chatBox = Hive.box<ChatMessage>('chatHistory');
    _messages = _chatBox.values.toList();
    _appStateBox = Hive.box('appState');
    _conversationContext = _appStateBox.get('lastContext')?.cast<int>();
    
    // SYSTEM PROMPT: Load the saved system prompt from the box when the app starts.
    _systemPromptController.text = _appStateBox.get('systemPrompt') ?? '';

    // SYSTEM PROMPT: Add a listener to save the system prompt automatically as the user types.
    _systemPromptController.addListener(() {
      _appStateBox.put('systemPrompt', _systemPromptController.text);
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    
    _isManuallyStopped = false;
    final userMessage = ChatMessage(text: text, isUser: true);
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _chatBox.add(userMessage);

    _scrollToBottom();
    _controller.clear();

    final aiMessagePlaceholder = ChatMessage(text: '', isUser: false);
    setState(() {
      _messages.add(aiMessagePlaceholder);
    });
    final int aiMessageKey = await _chatBox.add(aiMessagePlaceholder);
    _scrollToBottom();

    try {
      _client = http.Client();
      
      // SYSTEM PROMPT: Get the system prompt text from its controller.
      final systemPrompt = _systemPromptController.text.trim();

      final body = {
        'model': _modelController.text,
        'prompt': text,
        'stream': true,
        if (_conversationContext != null) 'context': _conversationContext,
        // SYSTEM PROMPT: Add the system prompt to the request if it's not empty.
        if (systemPrompt.isNotEmpty) 'system': systemPrompt,
      };

      final request = http.Request(
        'POST',
        Uri.parse('${_baseUrlController.text}/api/generate'),
      )
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);

      final streamedResponse = await _client!.send(request);
      final lines = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());

      String streamedResponseText = '';
      await for (final line in lines) {
        if (mounted) {
          try {
            final chunk = jsonDecode(line);
            final part = chunk['response'] ?? '';
            streamedResponseText += part;
            final updatedAIMessage = ChatMessage(text: streamedResponseText, isUser: false);
            setState(() {
              _messages[_messages.length - 1] = updatedAIMessage;
            });
            await _chatBox.put(aiMessageKey, updatedAIMessage);
            _scrollToBottom();

            if (chunk['done'] == true) {
              if (chunk['context'] != null) {
                final newContext = List<int>.from(chunk['context']);
                setState(() {
                  _conversationContext = newContext;
                });
                await _appStateBox.put('lastContext', newContext);
              }
            }
          } catch (e) {
            debugPrint('Invalid JSON line: $line');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final partialText = _messages.last.text;
        final finalMessage = _isManuallyStopped
            ? ChatMessage(
                text: partialText.trim().isEmpty ? "[Generation stopped by user]" : partialText,
                isUser: false)
            : ChatMessage(text: "Error: ${e.toString()}", isUser: false);
        setState(() {
          _messages[_messages.length - 1] = finalMessage;
        });
        await _chatBox.put(aiMessageKey, finalMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _client?.close();
      _client = null;
      _scrollToBottom();
    }
  }

  void _stopGeneration() {
    _isManuallyStopped = true;
    _client?.close();
  }

  Future<void> _clearConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Conversation?'),
        content: const Text('This will delete all messages and reset the conversation context.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Clear')),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _chatBox.clear();
      await _appStateBox.delete('lastContext');
      setState(() {
        _messages.clear();
        _conversationContext = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    // SYSTEM PROMPT: Dispose the new controller and remove its listener to prevent memory leaks.
    _systemPromptController.removeListener(() {});
    _systemPromptController.dispose();
    _client?.close();
    super.dispose();
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ollama Flutter Client'),
        shape: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5)),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'Clear Conversation', onPressed: _clearConversation),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => _showSettingsDialog(context)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) => ChatBubble(message: _messages[index]),
            ),
          ),
          _buildInputArea(context),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _baseUrlController, decoration: const InputDecoration(labelText: 'Ollama Base URL', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 16.0),
                TextField(controller: _modelController, decoration: const InputDecoration(labelText: 'Model Name', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 16.0),
                // SYSTEM PROMPT: Add the new text field to the settings dialog.
                TextField(
                  controller: _systemPromptController,
                  decoration: const InputDecoration(
                    labelText: 'System Prompt (AI Memory)',
                    hintText: 'e.g., You are a helpful AI assistant. The user\'s name is John.',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: null, // Allows for multiple lines of text.
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
        );
      },
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      elevation: 4.0,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8.0, left: 16.0, right: 16.0, top: 8.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: _isLoading ? null : _sendMessage,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText: 'Message Ollama...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            if (_isLoading)
              IconButton.filled(
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: _stopGeneration,
                tooltip: 'Stop Generation',
                iconSize: 28,
                style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
              )
            else
              IconButton.filled(
                icon: const Icon(Icons.send_rounded),
                onPressed: () => _sendMessage(_controller.text),
                tooltip: 'Send Message',
                iconSize: 28,
              ),
          ],
        ),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isUser) const Padding(padding: EdgeInsets.only(right: 8.0, top: 4.0), child: CircleAvatar(child: Icon(Icons.auto_awesome))),
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
            decoration: BoxDecoration(color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16.0)),
            child: SelectionArea(
              child: MarkdownBody(
                data: message.text.isEmpty ? '...' : message.text,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(p: theme.textTheme.bodyLarge),
              ),
            ),
          ),
        ),
        if (isUser) const Padding(padding: EdgeInsets.only(left: 8.0, top: 4.0), child: CircleAvatar(child: Icon(Icons.person_outline))),
      ],
    );
  }
}