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
  await Hive.openBox('appState'); // For settings

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
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    // Load the saved theme mode
    final appStateBox = Hive.box('appState');
    final theme = appStateBox.get('themeMode');
    if (theme == 'light') {
      _themeMode = ThemeMode.light;
    } else if (theme == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
  }

  void changeTheme(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
    });
    // Save the theme mode
    final appStateBox = Hive.box('appState');
    appStateBox.put('themeMode', themeMode.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HAL 9000',
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          // CHANGED: Using a different color for a more modern feel
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          // CHANGED: Using a different color for a more modern feel
          seedColor: Colors.deepPurple,
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
  @HiveField(2)
  final String? imagePath;

  ChatMessage({required this.text, required this.isUser, this.imagePath});
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
  bool _isSpeaking = false;

  double _speechRate = 1.0;
  double _speechPitch = 1.0;
  bool _voiceModeEnabled = false;


  @override
  void initState() {
    super.initState();
    _chatBox = Hive.box<ChatMessage>('chatHistory');
    _appStateBox = Hive.box('appState');

    // --- PERSISTENCE: Load all settings from Hive ---
    _baseUrlController = TextEditingController(text: _appStateBox.get('baseUrl', defaultValue: 'http://localhost:11434'));
    _modelController = TextEditingController(text: _appStateBox.get('modelName', defaultValue: 'gemma3:1B'));
    _systemPromptController = TextEditingController(text: _appStateBox.get('systemPrompt', defaultValue: ''));
    _suffixController = TextEditingController(text: _appStateBox.get('suffix', defaultValue: ''));
    _shouldThink = _appStateBox.get('shouldThink', defaultValue: false);
    _speechRate = _appStateBox.get('speechRate', defaultValue: 1.0);
    _speechPitch = _appStateBox.get('speechPitch', defaultValue: 1.0);
    _voiceModeEnabled = _appStateBox.get('voiceModeEnabled', defaultValue: false);

    _messages = _chatBox.values.toList();
    _conversationContext = _appStateBox.get('lastContext')?.cast<int>();

    // Add listeners to save settings on change
    _systemPromptController.addListener(() => _appStateBox.put('systemPrompt', _systemPromptController.text));

    _initSpeech();
    _initTts();

    if (_voiceModeEnabled) {
      _startListeningForVoiceMode();
    }
  }

  void _initTts() {
    _flutterTts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
    });

    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() => _isSpeaking = false);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_voiceModeEnabled && !_isLoading) {
            _startListeningForVoiceMode();
          }
        });
      }
    });

    _flutterTts.setErrorHandler((msg) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  void _initSpeech() async {
    try {
       _speechEnabled = await _speechToText.initialize(
         onStatus: (status) {
           if (_voiceModeEnabled) {
             bool isCurrentlyListening = status == SpeechToText.listeningStatus;
             if (isCurrentlyListening != _isListening) {
               setState(() => _isListening = isCurrentlyListening);
             }
           }
         }
       );
    } catch (e) {
      debugPrint('Speech recognition failed to initialize: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _startListeningForVoiceMode() async {
    if (!_speechEnabled || _isLoading || _isSpeaking || _isListening) return;

    _controller.clear();

    await _speechToText.listen(
      onResult: (result) {
        _controller.text = result.recognizedWords;
        if (result.finalResult && _voiceModeEnabled) {
          _sendMessage(_controller.text);
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 3),
      partialResults: true, // Set to true for more responsive feedback in controller
    );
    if(mounted) setState(() => _isListening = true);
  }

  Future<void> _startListeningManual() async {
    if (_speechEnabled && !_isListening) {
      await _stopSpeaking();
      await _speechToText.listen(
        onResult: (result) => setState(() => _controller.text = result.recognizedWords),
      );
      if (mounted) setState(() => _isListening = true);
    }
  }

  Future<void> _stopListening() async {
    if(!_isListening) return;
    await _speechToText.stop();
    if (mounted) setState(() => _isListening = false);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(_speechPitch);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Copied to clipboard'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 150, left: 20, right: 20),
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
    }
  }

  void _clearImage() => setState(() => _selectedImage = null);


  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty && _selectedImage == null) {
      if (_voiceModeEnabled && !_isLoading && !_isSpeaking) {
        _startListeningForVoiceMode();
      }
      return;
    }

    _isManuallyStopped = false;
    await _stopListening();
    await _stopSpeaking();

    final userMessage = ChatMessage(text: text, isUser: true, imagePath: _selectedImage?.path);
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _chatBox.add(userMessage);
    _scrollToBottom();
    _controller.clear();

    // Use a placeholder message index for the typing indicator
    final int aiMessageIndex = _messages.length;
    final aiMessagePlaceholder = ChatMessage(text: '', isUser: false);
    setState(() => _messages.add(aiMessagePlaceholder));
    _scrollToBottom();

    // The key for the final message in Hive
    final int aiMessageKey = await _chatBox.add(aiMessagePlaceholder);


    try {
      _client = http.Client();

      String? base64Image;
      if (_selectedImage != null) {
        final imageBytes = await _selectedImage!.readAsBytes();
        base64Image = base64Encode(imageBytes);
      }
      // Since image is now encoded, we can clear the selection from the UI
      if(mounted) setState(() => _selectedImage = null);

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
              _messages[aiMessageIndex] = ChatMessage(text: streamedResponseText, isUser: false);
            });
            _scrollToBottom();

            if (chunk['done'] == true && chunk['context'] != null) {
                _conversationContext = List<int>.from(chunk['context']);
                await _appStateBox.put('lastContext', _conversationContext);
            }
          } catch (e) {
            debugPrint('Invalid JSON line: $line');
          }
        }
      }

      final finalMessageText = streamedResponseText.trim();
      final finalMessage = ChatMessage(text: finalMessageText, isUser: false);
      await _chatBox.put(aiMessageKey, finalMessage);

      if (_voiceModeEnabled && finalMessageText.isNotEmpty) {
        await _speak(finalMessageText);
      }

    } catch (e) {
      if (mounted) {
        final finalMessage = _isManuallyStopped
            ? ChatMessage(text: "[Generation stopped by user]", isUser: false)
            : ChatMessage(text: "Error: ${e.toString()}", isUser: false);
        setState(() => _messages[aiMessageIndex] = finalMessage);
        await _chatBox.put(aiMessageKey, finalMessage);
        if (_voiceModeEnabled) await _speak(finalMessage.text);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _client?.close();
      _client = null;
      _scrollToBottom();

      if (_voiceModeEnabled && mounted && !_isSpeaking) {
        _startListeningForVoiceMode();
      }
    }
  }

  void _stopGeneration() {
    if (_isLoading) {
      setState(() => _isManuallyStopped = true);
      _client?.close();
    }
    _stopSpeaking();
    _stopListening();
    if (_voiceModeEnabled && mounted) {
      _startListeningForVoiceMode();
    }
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
      await _stopListening();
      await _stopSpeaking();
      if (_voiceModeEnabled) {
        _startListeningForVoiceMode();
      }
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

  void _toggleVoiceMode() async {
    setState(() => _voiceModeEnabled = !_voiceModeEnabled);
    await _appStateBox.put('voiceModeEnabled', _voiceModeEnabled);

    if (_voiceModeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Voice Mode ON. Speak to chat.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 150, left: 16, right: 16),
        ),
      );
      _startListeningForVoiceMode();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Voice Mode OFF.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 150, left: 16, right: 16),
        ),
      );
      await _stopListening();
      await _stopSpeaking();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HAL 9000'),
        shape: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5)),
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () {
              final newTheme = Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              MyApp.of(context).changeTheme(newTheme);
            },
          ),
          IconButton(icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'Clear Conversation', onPressed: _clearConversation),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => _showSettingsDialog(context)),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                // NEW: Show a welcome message if the chat is empty
                child: _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          // NEW: If it's the last message and we are loading, show typing indicator
                          if (index == _messages.length - 1 && _isLoading && !message.isUser) {
                            return const TypingIndicator();
                          }
                          return ChatBubble(
                            message: message,
                            onSpeak: message.isUser || _voiceModeEnabled ? null : _speak,
                            onCopy: message.isUser ? null : _copyToClipboard,
                            imagePath: message.imagePath,
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
                          child: Image.file(_selectedImage!, height: 100, width: 100, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: _clearImage,
                          child: Container(
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
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
          if (_voiceModeEnabled)
            Positioned(
              top: 8.0 + MediaQuery.of(context).padding.top,
              left: 0,
              right: 0,
              child: VoiceModeFeedbackOverlay(
                isListening: _isListening,
                isSpeaking: _isSpeaking,
                isLoading: _isLoading,
                onExitVoiceMode: _toggleVoiceMode,
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        // CHANGED: Increased bottom padding slightly
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton(
          onPressed: _speechEnabled ? _toggleVoiceMode : null,
          backgroundColor: _voiceModeEnabled && _isListening
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          elevation: 4.0,
          shape: const CircleBorder(),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Icon(
              _voiceModeEnabled
                  ? (_isListening ? Icons.mic : Icons.record_voice_over)
                  : Icons.voice_chat,
              key: ValueKey<bool>(_voiceModeEnabled && _isListening),
              color: _voiceModeEnabled && _isListening
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          tooltip: _voiceModeEnabled ? 'Exit Voice Mode' : 'Enter Voice Mode',
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // NEW: Empty state widget
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64.0),
          SizedBox(height: 16.0),
          Text(
            "Welcome to HAL 9000",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8.0),
          Text(
            "Type a message, attach an image,\nor use voice mode to begin.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
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
                    // --- PERSISTENCE: Save settings on change ---
                    Text('Connection', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8.0),
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(labelText: 'HAL 9000 Base URL', border: OutlineInputBorder(), isDense: true),
                      onChanged: (value) => _appStateBox.put('baseUrl', value),
                    ),
                    const Divider(height: 32.0),
                    Text('Model', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8.0),
                    TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(labelText: 'Model Name', border: OutlineInputBorder(), isDense: true),
                      onChanged: (value) => _appStateBox.put('modelName', value),
                    ),
                    const SizedBox(height: 16.0),
                    TextField(
                      controller: _systemPromptController,
                      decoration: const InputDecoration(labelText: 'System Prompt (AI Memory)', border: OutlineInputBorder()),
                      maxLines: 8,
                      // Listener is already attached in initState
                    ),
                    const SizedBox(height: 16.0),
                    TextField(
                      controller: _suffixController,
                      decoration: const InputDecoration(labelText: 'Suffix', hintText: 'Text to append after response', border: OutlineInputBorder()),
                      onChanged: (value) => _appStateBox.put('suffix', value),
                    ),
                    const SizedBox(height: 16.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("'Think' Mode"),
                        Switch(
                          value: _shouldThink,
                          onChanged: (value) {
                            dialogSetState(() => _shouldThink = value);
                            _appStateBox.put('shouldThink', value);
                          },
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text("Note: For supported models only.", style: Theme.of(context).textTheme.bodySmall),
                    ),
                    const Divider(height: 32.0),
                    Text('Speech', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8.0),
                    Text('Speech Speed', style: Theme.of(context).textTheme.labelLarge),
                    Slider(
                      value: _speechRate, min: 0.1, max: 2.0, divisions: 19,
                      label: _speechRate.toStringAsFixed(1),
                      onChanged: (newRate) {
                        dialogSetState(() => _speechRate = newRate);
                        _appStateBox.put('speechRate', newRate);
                      },
                    ),
                    const SizedBox(height: 16.0),
                    Text('Speech Pitch', style: Theme.of(context).textTheme.labelLarge),
                    Slider(
                      value: _speechPitch, min: 0.5, max: 2.0, divisions: 15,
                      label: _speechPitch.toStringAsFixed(1),
                      onChanged: (newPitch) {
                        dialogSetState(() => _speechPitch = newPitch);
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
              // CHANGED: Disable button while loading
              onPressed: _isLoading ? null : _pickImage,
              tooltip: 'Attach Image',
            ),
            if (!_voiceModeEnabled)
              IconButton(
                icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                color: _isListening ? Theme.of(context).colorScheme.primary : null,
                // CHANGED: Disable button while loading
                onPressed: !_speechEnabled || _isLoading ? null : (_isListening ? _stopListening : _startListeningManual),
                tooltip: _isListening ? 'Stop listening' : 'Listen',
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                // CHANGED: Disable submission when loading or in voice mode
                onSubmitted: (_isLoading || _voiceModeEnabled) ? null : (text) => _sendMessage(text),
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText: _isListening ? 'Listening...' : 'Message HAL 9000...',
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
            else if (!_voiceModeEnabled)
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
  final String? imagePath;

  const ChatBubble({
    required this.message,
    this.onSpeak,
    this.onCopy,
    this.imagePath,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    // CORRECTED: This stylesheet is now valid.
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge,
      // The 'code' parameter styles the text inside BOTH inline code and code blocks.
      code: theme.textTheme.bodyMedium!.copyWith(
        fontFamily: 'monospace',
        // This background color applies to inline `code` snippets.
        backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
      ),
      // 'codeblockDecoration' styles the entire block container.
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surface, // Background for the whole block
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.dividerColor),
      ),
    );

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                child: CircleAvatar(child: Icon(Icons.auto_awesome, color: theme.colorScheme.onPrimaryContainer)),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imagePath != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: Image.file(
                              File(imagePath!),
                              height: 150,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      MarkdownBody(
                        data: message.text,
                        styleSheet: markdownStyle,
                      ),
                      // CHANGED: Moved action buttons here, inside the bubble
                      if (!isUser && message.text.isNotEmpty && (onSpeak != null || onCopy != null))
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min, // Take only needed space
                            children: [
                              if (onSpeak != null)
                                IconButton(
                                  icon: const Icon(Icons.volume_up_outlined),
                                  iconSize: 20,
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Read aloud',
                                  onPressed: () => onSpeak!(message.text),
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
                child: CircleAvatar(child: Icon(Icons.person_outline)),
              ),
          ],
        ),
      ],
    );
  }
}

// NEW: Animated typing indicator widget
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 8.0),
      child: Row(
        children: [
           Padding(
            padding: const EdgeInsets.only(right: 8.0, top: 4.0),
            child: CircleAvatar(child: Icon(Icons.auto_awesome, color: theme.colorScheme.onPrimaryContainer)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return FadeTransition(
                  opacity: Tween(begin: 0.3, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: Interval(index * 0.2, (index * 0.2) + 0.6, curve: Curves.easeInOut),
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}


class VoiceModeFeedbackOverlay extends StatelessWidget {
  final bool isListening;
  final bool isSpeaking;
  final bool isLoading;
  final VoidCallback onExitVoiceMode;

  const VoiceModeFeedbackOverlay({
    super.key,
    required this.isListening,
    required this.isSpeaking,
    required this.isLoading,
    required this.onExitVoiceMode,
  });

  String get _statusText {
    if (isLoading) return "Processing...";
    if (isSpeaking) return "Speaking...";
    if (isListening) return "Listening...";
    return "Voice Mode Active";
  }

  IconData get _statusIcon {
    if (isLoading) return Icons.hourglass_empty;
    if (isSpeaking) return Icons.volume_up;
    if (isListening) return Icons.mic;
    return Icons.record_voice_over;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
        elevation: 8.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(_statusIcon, color: theme.colorScheme.onPrimaryContainer, size: 30),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  _statusText,
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: theme.colorScheme.onPrimaryContainer,
                onPressed: onExitVoiceMode,
                tooltip: 'Exit Voice Mode',
              ),
            ],
          ),
        ),
      ),
    );
  }
}