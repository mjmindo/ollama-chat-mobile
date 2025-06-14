import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

part 'main.g.dart';

// We no longer need a complex default prompt.

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
      title: 'Ollama Flutter Client',
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
  
  // Re-introducing the controller for the user-editable system prompt.
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
    _modelController = TextEditingController(text: 'gemma3:1B');
    
    // Initialize the controller for the editable system prompt.
    _systemPromptController = TextEditingController();

    _chatBox = Hive.box<ChatMessage>('chatHistory');
    _appStateBox = Hive.box('appState');
    
    _messages = _chatBox.values.toList();
    _conversationContext = _appStateBox.get('lastContext')?.cast<int>();
    
    // Load the user's saved system prompt, defaulting to an empty string.
    final storedSystemPrompt = _appStateBox.get('systemPrompt');
    _systemPromptController.text = storedSystemPrompt ?? '';

    // Add the listener to auto-save any changes the user makes.
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
      
      // Read the user's manual prompt from the controller.
      final systemPrompt = _systemPromptController.text.trim();

      final body = {
        'model': _modelController.text,
        'prompt': text,
        'stream': true,
        // Use the user's system prompt if it's not empty.
        if (systemPrompt.isNotEmpty) 'system': systemPrompt,
        if (_conversationContext != null) 'context': _conversationContext,
      };

      final request = http.Request('POST', Uri.parse('${_baseUrlController.text}/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);

      final streamedResponse = await _client!.send(request);
      final lines = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());

      String streamedResponseText = '';
      
      // Restore real-time streaming to the UI.
      await for (final line in lines) {
        if (mounted) {
          try {
            final chunk = jsonDecode(line);
            final part = chunk['response'] ?? '';
            streamedResponseText += part;

            setState(() {
              _messages[_messages.length - 1] = ChatMessage(text: streamedResponseText, isUser: false);
            });
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

      final finalMessage = ChatMessage(text: streamedResponseText.trim(), isUser: false);
      await _chatBox.put(aiMessageKey, finalMessage);

    } catch (e) {
      if (mounted) {
        final finalMessage = _isManuallyStopped
            ? ChatMessage(text: "[Generation stopped by user]", isUser: false)
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
        content: const Text('This will delete all messages and reset the conversation context. It will not clear the System Prompt memory.'),
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
    // Dispose the system prompt controller.
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

  // The settings dialog now includes the editable System Prompt again.
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
                // The editable memory box is back.
                TextField(
                  controller: _systemPromptController,
                  decoration: const InputDecoration(
                    labelText: 'System Prompt (AI Memory)',
                    hintText: 'e.g., You are a helpful assistant who always answers in rhymes.',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 8,
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
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.all(Theme.of(context).colorScheme.error),
                  foregroundColor: MaterialStateProperty.all(Theme.of(context).colorScheme.onError),
                ),
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