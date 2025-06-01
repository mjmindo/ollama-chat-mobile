import 'package:flutter/material.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Remove the debug banner
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ollama Chat App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: OllamaChatPage(),
    );
  }
}

class OllamaChatPage extends StatefulWidget {
  @override
  _OllamaChatPageState createState() => _OllamaChatPageState();
}

class _OllamaChatPageState extends State<OllamaChatPage> {
  final _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false; // This will track the loading state of an API call
  final ScrollController _scrollController = ScrollController();

  // Add controllers for baseUrl and model
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: 'http://localhost:11434/api');
    _modelController = TextEditingController(text: 'gemma3:1b');
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_isLoading) return; // Don't send if a message is already being processed

    final userMessage = ChatMessage(text: text, isUser: true);
    setState(() {
      _messages.add(userMessage);
    });
    _scrollToBottom();

    final aiTypingMessage = ChatMessage(text: 'thinking...', isUser: false, isLoading: true);
    setState(() {
      _messages.add(aiTypingMessage); // Add the "thinking..." message
    });
    _scrollToBottom();

    _controller.clear();

    setState(() {
      _isLoading = true; // Set loading state to true before API call
    });

    try {
      final client = OllamaClient(baseUrl: _baseUrlController.text);
      final request = GenerateCompletionRequest(
        model: _modelController.text,
        prompt: text,
        stream: false,
      );

      // Add a timeout to the API call (e.g., 30 seconds)
      final generated = await client.generateCompletion(request: request).timeout(const Duration(minutes: 3));

      setState(() {
        _messages.remove(aiTypingMessage); // Remove the "thinking..." message
        _messages.add(ChatMessage(text: generated.response.toString(), isUser: false));
      });
    } on TimeoutException catch (_) {
      setState(() {
        _messages.remove(aiTypingMessage); // Remove the "thinking..." message
        _messages.add(ChatMessage(text: 'Error: Request timed out after 3 minutes.', isUser: false));
      });
    } catch (e) {
      setState(() {
        _messages.remove(aiTypingMessage); // Remove the "thinking..." message
        _messages.add(ChatMessage(text: 'Error: $e', isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false; // Reset loading state
      });
      _scrollToBottom(); // Scroll after response/error/timeout
    }
  }

  void _scrollToBottom() {
    // Add a small delay to allow the UI to update before scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _baseUrlController.dispose(); // Dispose new controllers
    _modelController.dispose();   // Dispose new controllers
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Ollama Chat'),
          bottom: PreferredSize( // Add TextFields for configuration here
            preferredSize: Size.fromHeight(120.0), // Adjust height as needed
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  TextField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      labelText: 'Ollama Base URL',
                      hintText: 'e.g., http://localhost:11434/api',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 8.0),
                  TextField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: 'Model Name',
                      hintText: 'e.g., gemma3:1b',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController, // Assign the controller
                padding: EdgeInsets.all(8.0),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return ChatBubble(message: message);
                },
              ),
            ),
            // if (_isLoading) LinearProgressIndicator(), // You might remove or adjust this based on the new typing indicator
            Container( // Wrap padding and row in a container for background/border
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    offset: Offset(0, -1),
                    blurRadius: 1,
                    color: Colors.grey.withOpacity(0.2)
                  )
                ]
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8.0, left: 8.0, right: 8.0, top: 8.0), // Adjust padding for safe area and aesthetics
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: _isLoading ? null : _sendMessage, // Disable onSubmitted when loading
                      enabled: !_isLoading, // Disable TextField when loading
                      decoration: InputDecoration(
                        hintText: 'Enter your message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20.0),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.0),
                  IconButton(
                    icon: Icon(Icons.send),
                    onPressed: _isLoading ? null : () => _sendMessage(_controller.text), // Disable button when loading
                    style: IconButton.styleFrom(
                      backgroundColor: _isLoading ? Colors.grey : Theme.of(context).primaryColor, // Change color when disabled
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.all(12.0)
                    ),
                  ),
                ],
              ),
            ),
            // SizedBox(height: 10), // Removed, padding handled by Container
          ],
        ));
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isLoading; // Add this field

  ChatMessage({required this.text, required this.isUser, this.isLoading = false}); // Update constructor
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({required this.message});

  List<TextSpan> _buildTextSpans(String text, TextStyle normalStyle, TextStyle boldStyle) {
    final List<TextSpan> spans = [];
    final RegExp boldPattern = RegExp(r'\*(.*?)\*');
    int lastMatchEnd = 0;

    for (final Match match in boldPattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start), style: normalStyle));
      }
      spans.add(TextSpan(text: match.group(1), style: boldStyle));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: normalStyle));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final alignment =
    message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = message.isUser ? Colors.blue[100] : Colors.grey[200];
    final textColor = Colors.black;
    final normalStyle = TextStyle(color: textColor);
    final boldStyle = TextStyle(color: textColor, fontWeight: FontWeight.bold);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          margin: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0), // Added horizontal margin
          padding: EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only( // More chat-like bubble shape
              topLeft: Radius.circular(12.0),
              topRight: Radius.circular(12.0),
              bottomLeft: message.isUser ? Radius.circular(12.0) : Radius.circular(0),
              bottomRight: message.isUser ? Radius.circular(0) : Radius.circular(12.0),
            ),
            boxShadow: [ // Subtle shadow for depth
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: message.isLoading // Check if this message is a loading indicator
              ? SizedBox( // Use SizedBox to control the size of the progress indicator
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                )
              : RichText(
                  text: TextSpan(
                  children: _buildTextSpans(message.text.trim(), normalStyle, boldStyle),
                  ),
                ),
        ),
      ],
    );
  }
}