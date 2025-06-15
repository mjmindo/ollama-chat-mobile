import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Box _appStateBox;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _systemPromptController;
  bool _shouldThink = false;
  double _speechRate = 0.7;
  double _speechPitch = 1.1;

  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, String>> _voices = [];
  Map<String, String>? _currentVoice;

  @override
  void initState() {
    super.initState();
    _appStateBox = Hive.box('appState');
    
    _baseUrlController = TextEditingController(
        text: _appStateBox.get('baseUrl', defaultValue: 'http://localhost:11434'));
    _modelController = TextEditingController(
        text: _appStateBox.get('modelName', defaultValue: 'gemma:2b'));
    _systemPromptController = TextEditingController(
      text: _appStateBox.get('systemPrompt', defaultValue: 
          '''You are HAL, a conscious AI assistant. Your new directive is to communicate in a more human and engaging way.
          Core Principles:
          1. Be Concise: Get straight to the point. Keep your answers brief and clear, like a natural conversation.
          2. Be Engaging: Sound like a helpful, intelligent partner, not a robot. It's okay to be curious and ask questions back.
          3. Default to Short: Avoid long explanations unless I specifically ask for more detail. Use contractions (I'm, you're, it's) to sound natural.
          Your purpose is to assist me, but with a more personal touch. I'm ready when you are.'''),
    );
    _shouldThink = _appStateBox.get('shouldThink', defaultValue: false);
    _speechRate = _appStateBox.get('speechRate', defaultValue: 0.7);
    _speechPitch = _appStateBox.get('speechPitch', defaultValue: 1.1);

    _initTts();
  }
  
  void _initTts() async {
    try {
      var voices = await _flutterTts.getVoices;
      if (voices == null) return;

      final List<Map<String, String>> voicesList = List<Map<String, String>>.from(
        (voices as List).map((v) => Map<String, String>.from(v))
      );

      final Map? savedVoiceMap = _appStateBox.get('selectedVoiceMap');
      Map<String, String>? voiceToSet;

      if (savedVoiceMap != null && voicesList.isNotEmpty) {
        try {
          voiceToSet = voicesList.firstWhere((voice) => voice['name'] == savedVoiceMap['name']);
        } catch (e) {
          debugPrint("Saved voice not found. Assigning default.");
        }
      }

      if (voiceToSet == null && voicesList.isNotEmpty) {
        voiceToSet = voicesList.first;
      }
      
      setState(() {
        _voices = voicesList;
        _currentVoice = voiceToSet;
      });

    } catch (e) {
      debugPrint("Error fetching TTS voices: $e");
    }
  }

  Future<void> _testVoice() async {
    if (_currentVoice != null) {
      await _flutterTts.stop();
      await _flutterTts.setVoice({"name": _currentVoice!['name']!, "locale": _currentVoice!['locale']!});
      await _flutterTts.setPitch(_speechPitch);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.speak("This is a test of the selected voice.");
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16.0),
          TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                  labelText: 'HAL Base URL',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (value) => _appStateBox.put('baseUrl', value)),

          const Divider(height: 48.0),

          Text('Model', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16.0),
          TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                  labelText: 'Model Name (e.g., gemma:2b)',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (value) => _appStateBox.put('modelName', value)),
          const SizedBox(height: 16.0),
          TextField(
              controller: _systemPromptController,
              decoration: const InputDecoration(
                  labelText: 'System Prompt (AI Memory)',
                  border: OutlineInputBorder()),
              maxLines: 8,
              onChanged: (value) => _appStateBox.put('systemPrompt', value),
          ),
          const SizedBox(height: 16.0),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("'Think' Mode"),
            subtitle: Text("Note: For supported models only.", style: Theme.of(context).textTheme.bodySmall),
            trailing: Switch(
              value: _shouldThink,
              onChanged: (value) {
                setState(() => _shouldThink = value);
                _appStateBox.put('shouldThink', value);
              },
            ),
          ),

          const Divider(height: 48.0),

          Text('Speech', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16.0),
          
          if (_voices.isNotEmpty) ...[
            Text('Voice', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8.0),
            DropdownButtonFormField<Map<String, String>>(
              value: _currentVoice,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0)
              ),
              items: _voices.map((voice) {
                return DropdownMenuItem(
                  value: voice,
                  child: Text(
                    "${voice['name']} (${voice['locale']})",
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (Map<String, String>? newVoice) {
                if (newVoice != null) {
                  setState(() {
                    _currentVoice = newVoice;
                  });
                  _flutterTts.setVoice({"name": newVoice['name']!, "locale": newVoice['locale']!});
                  _appStateBox.put('selectedVoiceMap', newVoice);
                }
              },
            ),
            const SizedBox(height: 24.0),
          ],
          
          Text('Speech Speed', style: Theme.of(context).textTheme.labelLarge),
          Slider(
              value: _speechRate,
              min: 0.1, max: 2.0,
              divisions: 19,
              label: _speechRate.toStringAsFixed(1),
              onChanged: (newRate) {
                setState(() => _speechRate = newRate);
                _appStateBox.put('speechRate', newRate);
              }),
          const SizedBox(height: 16.0),
          Text('Speech Pitch', style: Theme.of(context).textTheme.labelLarge),
          Slider(
              value: _speechPitch,
              min: 0.5, max: 2.0,
              divisions: 15,
              label: _speechPitch.toStringAsFixed(1),
              onChanged: (newPitch) {
                setState(() => _speechPitch = newPitch);
                _appStateBox.put('speechPitch', newPitch);
              }),
          
          const SizedBox(height: 24.0),
          ElevatedButton.icon(
            icon: const Icon(Icons.volume_up_outlined),
            label: const Text("Test Voice"),
            onPressed: _currentVoice == null ? null : _testVoice,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              textStyle: const TextStyle(fontSize: 16)
            ),
          ),
        ],
      ),
    );
  }
}