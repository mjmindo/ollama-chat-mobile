import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import 'settings_page.dart';
import '../models/conversation.dart';
import '../models/chat_message.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/voice_feedback_overlay.dart';

const uuid = Uuid();

class OllamaChatPage extends StatefulWidget {
  const OllamaChatPage({super.key});

  @override
  State<OllamaChatPage> createState() => _OllamaChatPageState();
}

class _OllamaChatPageState extends State<OllamaChatPage> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  File? _selectedImage;

  http.Client? _client;
  bool _isManuallyStopped = false;

  late Box<ChatMessage> _messageBox;
  late Box<Conversation> _conversationBox;
  late Box _appStateBox;

  Conversation? _activeConversation;
  List<Conversation> _conversations = [];

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  bool _speechEnabled = false;
  bool _isSpeaking = false;
  dynamic _currentlySpeakingMessageKey;
  bool _voiceModeEnabled = false;

  bool _showScrollDownButton = false;

  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    _messageBox = Hive.box<ChatMessage>('messages');
    _conversationBox = Hive.box<Conversation>('conversations');
    _appStateBox = Hive.box('appState');

    _voiceModeEnabled =
        _appStateBox.get('voiceModeEnabled', defaultValue: false);

    _loadConversations();
    final lastActiveId = _appStateBox.get('lastActiveConversationId');
    if (lastActiveId != null && _conversationBox.containsKey(lastActiveId)) {
      _setActiveConversation(lastActiveId);
    } else if (_conversations.isNotEmpty) {
      _setActiveConversation(_conversations.first.id);
    } else {
      _createNewConversation();
    }

    _scrollController.addListener(_scrollListener);
    _initSpeech();
    _initTts();

    if (_voiceModeEnabled) {
      _startListeningForVoiceMode();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _client?.close();
    _speechToText.cancel();
    _flutterTts.stop();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  // --- Conversation Management ---
  void _loadConversations() {
    _conversations = _conversationBox.values.toList();
    _conversations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mounted) setState(() {});
  }

  void _setActiveConversation(String id) {
    _stopAllVoiceActivity();
    setState(() {
      _activeConversation = _conversationBox.get(id);
      _appStateBox.put('lastActiveConversationId', id);
    });
    _scrollToBottom();
    if (_voiceModeEnabled) {
      _startListeningForVoiceMode();
    }
  }

  void _createNewConversation() {
    final newId = uuid.v4();
    final newConversation = Conversation(
      id: newId,
      title: "New Chat",
      createdAt: DateTime.now(),
    );
    _conversationBox.put(newId, newConversation);
    _loadConversations();
    _setActiveConversation(newId);
  }

  Future<void> _deleteConversation(String id) async {
    if (_conversationBox.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Cannot delete the last conversation.")));
      return;
    }

    final messagesToDelete =
        _messageBox.values.where((msg) => msg.conversationId == id).toList();
    for (var msg in messagesToDelete) {
      await msg.delete();
    }

    await _conversationBox.delete(id);

    _loadConversations();
    if (_activeConversation?.id == id) {
      _setActiveConversation(_conversations.first.id);
    } else {
      if (mounted) setState(() {});
    }
  }

  Future<void> _renameConversation(Conversation conversation) async {
    final titleController = TextEditingController(text: conversation.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(hintText: "Enter new title")),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(titleController.text),
              child: const Text('Rename')),
        ],
      ),
    );

    if (newTitle != null && newTitle.trim().isNotEmpty) {
      conversation.title = newTitle.trim();
      await conversation.save();
      _loadConversations();
    }
  }

  // --- Voice and Speech Logic ---
  void _initTts() {
    _flutterTts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
    });

    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      
      final wasAiResponse = _currentlySpeakingMessageKey != null;

      setState(() {
        _isSpeaking = false;
        _currentlySpeakingMessageKey = null;
      });
      
      if (wasAiResponse && _voiceModeEnabled && !_isLoading) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _startListeningForVoiceMode();
        });
      }
    });

    _flutterTts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _currentlySpeakingMessageKey = null;
        });
      }
    });

    _flutterTts.setErrorHandler((msg) {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _currentlySpeakingMessageKey = null;
        });
        debugPrint("TTS Error: $msg");
      }
    });
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) {
          if (mounted && _voiceModeEnabled) {
            setState(() => _isListening = _speechToText.isListening);
          }
        },
        onError: (error) {
            debugPrint("STT Error: $error");
            if (_voiceModeEnabled && (error.errorMsg.contains("error_speech_timeout") || error.errorMsg.contains("error_no_match"))) {
                _handleInactivity();
            }
        },
      );
    } catch (e) {
      debugPrint('Speech recognition failed to initialize: $e');
    }
    if (mounted) setState(() {});
  }
  
  Future<void> _handleInactivity() async {
    if (!_voiceModeEnabled) return; 
    
    _stopAllVoiceActivity();
    await _speak("Exiting voice mode.", null);
    
    if (mounted && _voiceModeEnabled) {
      _toggleVoiceMode();
    }
  }

  Future<void> _startListeningForVoiceMode() async {
    if (!_speechEnabled || _isLoading || _isSpeaking || _isListening) return;
    
    _controller.clear();
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 20), _handleInactivity);

    await _speechToText.listen(
      onResult: (result) {
        _inactivityTimer?.cancel();
        
        _controller.text = result.recognizedWords;
        if (result.finalResult && _voiceModeEnabled) {
          _sendMessage(_controller.text);
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
    );
    if (mounted) setState(() => _isListening = true);
  }

  Future<void> _startListeningManual() async {
    if (_speechEnabled && !_isListening) {
      await _stopSpeaking();
      await _speechToText.listen(
        onResult: (result) => setState(() => _controller.text = result.recognizedWords),
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 10),
      );
      if (mounted) setState(() => _isListening = true);
    }
  }

  Future<void> _stopListening() async {
    _inactivityTimer?.cancel();
    if (!_isListening) return;
    await _speechToText.stop();
    if (mounted) setState(() => _isListening = false);
  }

  String _cleanTextForTts(String text) {
    final emojiRegex = RegExp(r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])');
    return text
        .replaceAll(RegExp(r'\*{1,3}'), '')
        .replaceAll('_', '')
        .replaceAll(RegExp(r'`{1,3}'), '')
        .replaceAll('...', ', ')
        .replaceAll('\n', '. ')
        .replaceAll(':', ', ')
        .replaceAll('-', ', ')
        .replaceAll(emojiRegex, ' ');
  }

  Future<void> _speak(String text, dynamic? messageKey) async {
    final cleanText = _cleanTextForTts(text);
    if (cleanText.trim().isEmpty) return;

    if(messageKey != null) {
      setState(() => _currentlySpeakingMessageKey = messageKey);
    }

    final savedVoiceMap = _appStateBox.get('selectedVoiceMap') as Map?;
    final savedRate = _appStateBox.get('speechRate', defaultValue: 0.7);
    final savedPitch = _appStateBox.get('speechPitch', defaultValue: 1.1);

    await _flutterTts.stop();

    if (savedVoiceMap != null) {
      await _flutterTts.setVoice(Map<String, String>.from(savedVoiceMap));
    } else {
      await _flutterTts.setLanguage("en-US");
    }

    await _flutterTts.setPitch(savedPitch);
    await _flutterTts.setSpeechRate(savedRate);
    await _flutterTts.speak(cleanText);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _currentlySpeakingMessageKey = null;
      });
    }
  }

  void _stopAllVoiceActivity() {
    _inactivityTimer?.cancel();
    if (_speechToText.isListening) {
      _speechToText.stop();
    }
    if (_isSpeaking) {
      _flutterTts.stop();
    }
  }
  
  void _toggleVoiceMode() async {
    final bool enabling = !_voiceModeEnabled;
    setState(() => _voiceModeEnabled = enabling);
    await _appStateBox.put('voiceModeEnabled', _voiceModeEnabled);
    
    if (enabling) {
      _startListeningForVoiceMode();
    } else {
      _stopAllVoiceActivity();
    }
  }

  Future<void> _sendMessage(String text) async {
    _stopAllVoiceActivity();
    
    if (_activeConversation == null) return;
    if (text.trim().isEmpty && _selectedImage == null) return;

    _isManuallyStopped = false;
    
    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      imagePath: _selectedImage?.path,
      conversationId: _activeConversation!.id,
    );
    _messageBox.add(userMessage);

    setState(() => _isLoading = true);
    _scrollToBottom();
    _controller.clear();

    if (_messageBox.values.where((m) => m.conversationId == _activeConversation!.id).length == 1 && _activeConversation!.title == "New Chat") {
      final newTitle = text.trim().length > 30 ? "${text.trim().substring(0, 30)}..." : text.trim();
      if (newTitle.isNotEmpty) {
        _activeConversation!.title = newTitle;
        await _activeConversation!.save();
        _loadConversations();
      }
    }

    final aiMessagePlaceholder = ChatMessage(text: '', isUser: false, conversationId: _activeConversation!.id);
    int? aiMessageKey;

    try {
      aiMessageKey = await _messageBox.add(aiMessagePlaceholder);
      if(mounted) setState(() {});
      _scrollToBottom();

      _client = http.Client();

      String? base64Image;
      if (_selectedImage != null) {
        final imageBytes = await _selectedImage!.readAsBytes();
        base64Image = base64Encode(imageBytes);
      }
      if (mounted) setState(() => _selectedImage = null);

      final systemPrompt = _appStateBox.get('systemPrompt', defaultValue: '');
      final body = {
        'model': _appStateBox.get('modelName', defaultValue: 'gemma3:1b'), 'prompt': text, 'stream': true,
        'think': _appStateBox.get('shouldThink', defaultValue: false),
        if (systemPrompt.isNotEmpty) 'system': systemPrompt,
        if (base64Image != null) 'images': [base64Image],
        if (_activeConversation!.context != null) 'context': _activeConversation!.context,
      };

      final request = http.Request('POST', Uri.parse('${_appStateBox.get('baseUrl')}/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);

      final streamedResponse = await _client!.send(request);
      final lines = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());
      String streamedResponseText = '';
      List<int>? newContext;

      await for (final line in lines) {
        if (mounted) {
          try {
            final chunk = jsonDecode(line);
            final part = chunk['response'] ?? '';
            streamedResponseText += part;
            final currentAIMessage = _messageBox.get(aiMessageKey);
            if (currentAIMessage != null) {
              currentAIMessage.text = streamedResponseText;
              await _messageBox.put(aiMessageKey!, currentAIMessage);
            }
            if (mounted) setState(() {});
            _scrollToBottom();
            if (chunk['done'] == true && chunk['context'] != null) {
              newContext = List<int>.from(chunk['context']);
            }
          } catch (e) {
            debugPrint('Invalid JSON line: $line');
          }
        }
      }
      if (newContext != null) {
        _activeConversation!.context = newContext;
        await _activeConversation!.save();
      }
      if (_voiceModeEnabled && streamedResponseText.trim().isNotEmpty) {
        await _speak(streamedResponseText.trim(), aiMessageKey);
      }
    } on http.ClientException catch (_) {
      if (aiMessageKey != null) _handleError("Network Error: Could not connect to the server. Please check your Base URL and connection in settings.", aiMessageKey);
    } on SocketException catch (_) {
      if (aiMessageKey != null) _handleError("Network Error: Could not reach the server. Is HAL running at that address?", aiMessageKey);
    } on FormatException catch (_) {
      if (aiMessageKey != null) _handleError("Error: Received an invalid response from the server.", aiMessageKey);
    } catch (e) {
      if (!_isManuallyStopped && aiMessageKey != null) {
        _handleError("An unexpected error occurred: ${e.toString()}", aiMessageKey);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _client?.close();
      _client = null;
      _scrollToBottom();
    }
  }

  void _stopGeneration() {
    if (_isLoading) {
      setState(() => _isManuallyStopped = true);
      _client?.close();
    }
    _stopAllVoiceActivity();
    if (_voiceModeEnabled && mounted) {
      _startListeningForVoiceMode();
    }
  }
  
  // --- All Helper and Build Methods Below ---

  Future<void> _clearCurrentConversation() async {
    if (_activeConversation == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Conversation?'),
        content: const Text(
            'This will delete all messages and reset the context for this specific chat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed ?? false) {
      _activeConversation!.context = null;
      await _activeConversation!.save();
      final messagesToDelete = _messageBox.values
          .where((msg) => msg.conversationId == _activeConversation!.id)
          .toList();
      for (var msg in messagesToDelete) {
        await msg.delete();
      }
      _stopAllVoiceActivity();
      if (mounted) setState(() {});
      if (_voiceModeEnabled) _startListeningForVoiceMode();
    }
  }

  void _scrollListener() {
    if (_scrollController.hasClients && _scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      if (!_showScrollDownButton) setState(() => _showScrollDownButton = true);
    } else {
      if (_showScrollDownButton) setState(() => _showScrollDownButton = false);
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
    }
  }

  void _scrollToBottom({bool isManual = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: isManual
              ? const Duration(milliseconds: 500)
              : const Duration(milliseconds: 300),
          curve: isManual ? Curves.easeOut : Curves.easeIn,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
    }
  }

  void _clearImage() {
    setState(() => _selectedImage = null);
  }
  
  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Copied to clipboard'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 20,
              right: 20),
        ),
      );
    }
  }

  Future<void> _handleError(String errorMessage, int messageKey) async {
    if (mounted && !_isManuallyStopped) {
      final aiMessage = _messageBox.get(messageKey);
      if (aiMessage != null) {
        aiMessage.text = errorMessage;
        await _messageBox.put(messageKey, aiMessage);
      }
      if (_voiceModeEnabled) await _speak(errorMessage, messageKey);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _scrollToTop,
          child: Tooltip(
            message: 'Scroll to Top',
            child: Text(_activeConversation?.title ?? 'HAL',
                overflow: TextOverflow.ellipsis),
          ),
        ),
        shape: Border(
            bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5)),
        actions: [
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            tooltip: 'Toggle Theme',
            onPressed: () => MyApp.of(context).changeTheme(
                Theme.of(context).brightness == Brightness.dark
                    ? ThemeMode.light
                    : ThemeMode.dark),
          ),
          IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear Current Conversation',
              onPressed: _clearCurrentConversation),
          IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const SettingsPage()))),
        ],
      ),
      drawer: _buildConversationDrawer(),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: _messageBox.listenable(),
                  builder: (context, Box<ChatMessage> box, _) {
                    final currentMessages = box.values
                        .where((msg)
                            => msg.conversationId == _activeConversation?.id)
                        .toList();

                    if (currentMessages.isEmpty) {
                      return _buildEmptyState();
                    }

                    return Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      interactive: true,
                      thickness: 8.0,
                      radius: const Radius.circular(4.0),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 72),
                        itemCount: currentMessages.length,
                        itemBuilder: (context, index) {
                          final message = currentMessages[index];
                          final isCurrentlySpeaking =
                              message.key == _currentlySpeakingMessageKey;

                          if (index == currentMessages.length - 1 &&
                              _isLoading &&
                              message.text.isEmpty &&
                              !message.isUser) {
                            return const TypingIndicator();
                          }
                          return ChatBubble(
                            message: message,
                            messageKey: message.key,
                            isCurrentlySpeaking: isCurrentlySpeaking,
                            isAnyMessageSpeaking: _isSpeaking,
                            onSpeak: message.isUser || _voiceModeEnabled
                                ? null
                                : _speak,
                            onStop: _stopSpeaking,
                            onCopy: message.isUser ? null : _copyToClipboard,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              if (_selectedImage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(8.0)),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: Image.file(_selectedImage!,
                                height: 100, width: 100, fit: BoxFit.cover)),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: _clearImage,
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              if (_voiceModeEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: VoiceModeFeedbackOverlay(
                      isListening: _isListening,
                      isSpeaking: _isSpeaking,
                      isLoading: _isLoading,
                      onExitVoiceMode: _toggleVoiceMode),
                ),
              _buildInputArea(context),
            ],
          ),
          Positioned(
            right: 16.0,
            bottom: 170.0,
            child: AnimatedOpacity(
              opacity: _showScrollDownButton ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: FloatingActionButton.small(
                onPressed: () => _scrollToBottom(isManual: true),
                tooltip: 'Scroll to Bottom',
                heroTag: 'scroll_down_btn',
                child: const Icon(Icons.arrow_downward),
              ),
            ),
          ),
          Positioned(
            right: 10.0,
            bottom: 90.0,
            child: FloatingActionButton(
              onPressed: _speechEnabled && !_isSpeaking ? _toggleVoiceMode : null,
              backgroundColor: _voiceModeEnabled && _isListening
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              elevation: 4.0,
              shape: const CircleBorder(),
              heroTag: 'voice_mode_btn',
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder:
                    (Widget child, Animation<double> animation) =>
                        ScaleTransition(scale: animation, child: child),
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
              tooltip:
                  _voiceModeEnabled ? 'Exit Voice Mode' : 'Enter Voice Mode',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: OutlinedButton.icon(
                onPressed: () {
                  _createNewConversation();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.add),
                label: const Text('New Chat'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conversation = _conversations[index];
                  final isActive = _activeConversation?.id == conversation.id;
                  return ListTile(
                    title: Text(conversation.title,
                        overflow: TextOverflow.ellipsis),
                    selected: isActive,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.5),
                    onTap: () {
                      _setActiveConversation(conversation.id);
                      Navigator.of(context).pop();
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'rename') {
                          _renameConversation(conversation);
                        } else if (value == 'delete') {
                          _deleteConversation(conversation.id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: 'rename', child: Text('Rename')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64.0),
          SizedBox(height: 16.0),
          Text("Welcome to HAL",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 8.0),
          Text(
              "Start a new chat from the drawer, type a message, or use voice mode.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      elevation: 4.0,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 8.0,
            left: 8.0,
            right: 8.0,
            top: 8.0),
        child: Row(
          children: [
            IconButton(
                icon: const Icon(Icons.attach_file_outlined),
                onPressed: _isLoading ? null : _pickImage,
                tooltip: 'Attach Image'),
            if (!_voiceModeEnabled)
              IconButton(
                icon: Icon(_isListening ? Icons.mic : Icons.mic_off),
                color:
                    _isListening ? Theme.of(context).colorScheme.primary : null,
                onPressed: !_speechEnabled || _isLoading || _isSpeaking
                    ? null
                    : (_isListening ? _stopListening : _startListeningManual),
                tooltip: _isListening ? 'Stop listening' : 'Listen',
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_isLoading || _voiceModeEnabled)
                    ? null
                    : (text) => _sendMessage(text),
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText: _isListening ? 'Listening...' : 'Message HAL...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: BorderSide.none),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  backgroundColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.error),
                  foregroundColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.onError),
                ),
              )
            else if (!_voiceModeEnabled)
              IconButton.filled(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () => _sendMessage(_controller.text),
                  tooltip: 'Send Message',
                  iconSize: 28),
          ],
        ),
      ),
    );
  }
}