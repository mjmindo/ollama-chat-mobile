import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

part 'main.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(ChatMessageAdapter());
  await Hive.openBox<ChatMessage>('chatHistory');
  await Hive.openBox('appState');

  runApp(const MyApp());
}

// THEME TOGGLE: Convert MyApp to a StatefulWidget to manage theme state.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // THEME TOGGLE: Create a static method for child widgets to access the state.
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // THEME TOGGLE: Add state variable for the theme mode.
  ThemeMode _themeMode = ThemeMode.system;

  // THEME TOGGLE: Method for child widgets to call to change the theme.
  void changeTheme(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ollama Flutter',
      // THEME TOGGLE: Use the state variable to set the theme mode.
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          // Change the seed color to blue for the light theme.
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          // Change the seed color to blue for the dark theme.
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
  late TextEditingController _systemPromptController;
  late TextEditingController _suffixController;
  bool _shouldThink = false;
  File? _selectedImage;


  http.Client? _client;
  bool _isManuallyStopped = false;
  late Box<ChatMessage> _chatBox;
  late Box _appStateBox;
  List<int>? _conversationContext;
  
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  bool _speechEnabled = false;

  double _speechRate = 1.0;
  double _speechPitch = 1.0;


  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: 'http://localhost:11434');
    _modelController = TextEditingController(text: 'gemma3:1B');
    _systemPromptController = TextEditingController();
    _suffixController = TextEditingController();


    _chatBox = Hive.box<ChatMessage>('chatHistory');
    _appStateBox = Hive.box('appState');
    
    _messages = _chatBox.values.toList();
    _conversationContext = _appStateBox.get('lastContext')?.cast<int>();
    
    final storedSystemPrompt = _appStateBox.get('systemPrompt');
    _systemPromptController.text = storedSystemPrompt ?? '';

    _systemPromptController.addListener(() {
      _appStateBox.put('systemPrompt', _systemPromptController.text);
    });

    _speechRate = _appStateBox.get('speechRate') ?? 1.0;
    _speechPitch = _appStateBox.get('speechPitch') ?? 1.0;
    
    _initSpeech();
  }
  
  void _initSpeech() async {
    try {
       _speechEnabled = await _speechToText.initialize();
    } catch (e) {
      print('Speech recognition failed to initialize: $e');
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startListening() async {
    await _stopSpeaking();
    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
        });
      },
    );
    setState(() {
      _isListening = true;
    });
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(_speechPitch);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImage = null;
    });
  }


  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty && _selectedImage == null) return;
    
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

      String? base64Image;
      if (_selectedImage != null) {
        final imageBytes = await _selectedImage!.readAsBytes();
        base64Image = base64Encode(imageBytes);
      }
      
      final systemPrompt = _systemPromptController.text.trim();
      final body = {
        'model': _modelController.text,
        'prompt': text,
        'suffix': _suffixController.text.trim().isNotEmpty ? _suffixController.text.trim() : null,
        'system': systemPrompt.isNotEmpty ? systemPrompt : null,
        'think': _shouldThink,
        'images': base64Image != null ? [base64Image] : null,
        'context': _conversationContext,
        'stream': true,
      };

      body.removeWhere((key, value) => value == null);

      final request = http.Request('POST', Uri.parse('${_baseUrlController.text}/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);

      _clearImage();

      final streamedResponse = await _client!.send(request);
      final lines = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());

      String streamedResponseText = '';
      
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

      final finalMessageText = streamedResponseText.trim();
      final finalMessage = ChatMessage(text: finalMessageText, isUser: false);
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
    if (_isLoading) {
      setState(() {
        _isManuallyStopped = true;
      });
      _client?.close();
    }
    _stopSpeaking();
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
    _systemPromptController.removeListener(() {});
    _systemPromptController.dispose();
    _suffixController.dispose();
    _client?.close();
    _speechToText.cancel();
    _flutterTts.stop();
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
        title: const Text('Ollama Flutter'),
        shape: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5)),
        actions: [
          // THEME TOGGLE: Add the new button to the AppBar.
          IconButton(
            icon: Icon(
              // Check the app's brightness to determine which icon to show.
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () {
              // Determine the current brightness and toggle to the opposite mode.
              final newTheme = Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              // Call the changeTheme method from MyApp to update the state.
              MyApp.of(context).changeTheme(newTheme);
            },
          ),
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
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ChatBubble(
                  message: message,
                  onSpeak: message.isUser ? null : _speak,
                  onCopy: message.isUser ? null : _copyToClipboard,
                );
              },
            ),
          ),
          if (_selectedImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.file(
                        _selectedImage!,
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: _clearImage,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  )
                ],
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
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: const Text('Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: _baseUrlController, decoration: const InputDecoration(labelText: 'Ollama Base URL', hintText: 'e.g., http://localhost:11434', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 16.0),
                    TextField(controller: _modelController, decoration: const InputDecoration(labelText: 'Model Name', hintText: 'e.g., llava, llama3', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 16.0),
                    TextField(
                      controller: _systemPromptController,
                      decoration: const InputDecoration(labelText: 'System Prompt (AI Memory)', border: OutlineInputBorder()),
                      maxLines: 8,
                    ),
                    const SizedBox(height: 16.0),
                    TextField(
                      controller: _suffixController,
                      decoration: const InputDecoration(labelText: 'Suffix', hintText: 'Text to append after response', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("'Think' Mode"),
                        Switch(
                          value: _shouldThink,
                          onChanged: (value) {
                            dialogSetState(() {
                              _shouldThink = value;
                            });
                          },
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        "Note: For supported models only.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Divider(height: 32.0),
                    Text('Speech Speed', style: Theme.of(context).textTheme.titleMedium),
                    Slider(
                      value: _speechRate,
                      min: 0.1, max: 2.0, divisions: 19,
                      label: _speechRate.toStringAsFixed(1),
                      onChanged: (newRate) {
                        dialogSetState(() { _speechRate = newRate; });
                        _appStateBox.put('speechRate', newRate);
                      },
                    ),
                    const SizedBox(height: 16.0),
                    Text('Speech Pitch', style: Theme.of(context).textTheme.titleMedium),
                    Slider(
                      value: _speechPitch,
                      min: 0.5, max: 2.0, divisions: 15,
                      label: _speechPitch.toStringAsFixed(1),
                      onChanged: (newPitch) {
                        dialogSetState(() { _speechPitch = newPitch; });
                        _appStateBox.put('speechPitch', newPitch);
                      },
                    ),
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      elevation: 4.0,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8.0, left: 8.0, right: 8.0, top: 8.0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file_outlined),
              onPressed: _pickImage,
              tooltip: 'Attach Image',
            ),
            IconButton(
              icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
              color: _isListening ? Theme.of(context).colorScheme.primary : null,
              onPressed: !_speechEnabled ? null : (_isListening ? _stopListening : _startListening),
              tooltip: _isListening ? 'Stop listening' : 'Listen',
            ),
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
                  backgroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.error),
                  foregroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.onError),
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
  final void Function(String text)? onSpeak;
  final void Function(String text)? onCopy;

  const ChatBubble({
    required this.message,
    this.onSpeak,
    this.onCopy,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser)
              const Padding(
                padding: EdgeInsets.only(right: 8.0, top: 4.0),
                child: CircleAvatar(child: Icon(Icons.auto_awesome)),
              ),
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
                decoration: BoxDecoration(
                  color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: SelectionArea(
                  child: MarkdownBody(
                    data: message.text.isEmpty ? '...' : message.text,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(p: theme.textTheme.bodyLarge),
                  ),
                ),
              ),
            ),
            if (isUser)
              const Padding(
                padding: EdgeInsets.only(left: 8.0, top: 4.0),
                child: CircleAvatar(child: Icon(Icons.person_outline)),
              ),
          ],
        ),
        if (!isUser && message.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 48.0, right: 48.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (onSpeak != null)
                  IconButton(
                    icon: const Icon(Icons.volume_up_outlined),
                    iconSize: 20,
                    tooltip: 'Read aloud',
                    onPressed: () => onSpeak!(message.text),
                  ),
                if (onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    iconSize: 20,
                    tooltip: 'Copy text',
                    onPressed: () => onCopy!(message.text),
                  ),
              ],
            ),
          )
      ],
    );
  }
}