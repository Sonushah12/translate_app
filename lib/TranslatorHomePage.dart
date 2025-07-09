import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';


import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';

class TranslationDashboard extends StatefulWidget {
  const TranslationDashboard({super.key});

  @override
  State<TranslationDashboard> createState() => _TranslationDashboardState();
}

class _TranslationDashboardState extends State<TranslationDashboard> {
  static const platform = MethodChannel('floating_window');
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController _inputController = TextEditingController();
  String selectedLanguage = 'English';
  String translatedText = '';
  List<Map<String, String>> translationHistory = [];
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isTranslating = false;

  final List<String> languages = [
    'English', 'Hindi', 'Gujarati', 'French', 'Spanish', 'German', 'Chinese',
  ];

  @override
  void initState() {
    super.initState();
    _initBannerAd();
    _initTts();
    _loadHistory();
  }

  void _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('translationHistory');
    if (historyJson != null) {
      setState(() {
        translationHistory = List<Map<String, String>>.from(
          (jsonDecode(historyJson) as List).map((e) => Map<String, String>.from(e)),
        );
      });
    }
  }

  void _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('translationHistory', jsonEncode(translationHistory));
  }

  void _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      translationHistory.clear();
    });
    await prefs.remove('translationHistory');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Translation history cleared')),
    );
  }

  void _deleteHistoryItem(int index) {
    setState(() {
      translationHistory.removeAt(index);
    });
    _saveHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Translation deleted')),
    );
  }

  void _initBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Ad failed to load: $error');
          ad.dispose();
        },
      ),
    )..load();
  }

  void _initTts() {
    flutterTts.setLanguage('en-US');
    flutterTts.setSpeechRate(0.5);
    flutterTts.setVolume(1.0);
    flutterTts.setPitch(1.0);
  }

  void startFloatingWindow() async {
    try {
      await platform.invokeMethod('startFloating');
    } on PlatformException catch (e) {
      debugPrint("Failed to start floating: '${e.message}'.");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start floating window: ${e.message}')),
      );
    }
  }

  void checkOverlayPermission() async {
    final isGranted = await platform.invokeMethod('checkOverlayPermission');
    if (isGranted == true) {
      startFloatingWindow();
    } else {
      await platform.invokeMethod('requestOverlayPermission');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please grant overlay permission')),
      );
    }
  }

  void _translateText() async {
    final inputText = _inputController.text.trim();
    if (inputText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter text to translate')),
      );
      return;
    }

    const apiKey = 'AIzaSyAy5xW2-z_anLdPYhFixJZPO-PBWtDUE3w';
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

    setState(() {
      _isTranslating = true;
      translatedText = 'Translating...';
    });

    try {
      final promptText = 'Only translate "$inputText" to $selectedLanguage. Give only the translated text, no extra words.';
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': promptText}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final translated = jsonResponse['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          translatedText = translated;
          translationHistory.insert(0, {
            'input': inputText,
            'translated': translated,
            'language': selectedLanguage,
            'timestamp': DateTime.now().toString(),
          });
          _isTranslating = false;
        });
        _saveHistory();
      } else {
        throw Exception('Failed to translate: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Translation failed: ${e.toString()}')),
      );
      setState(() {
        translatedText = '';
        _isTranslating = false;
      });
    }
  }

  String _getLanguageCode(String language) {
    const languageCodes = {
      'english': 'en',
      'hindi': 'hi',
      'gujarati': 'gu',
      'french': 'fr',
      'spanish': 'es',
      'german': 'de',
      'chinese': 'zh',
    };
    return languageCodes[language.toLowerCase()] ?? 'en';
  }

  void _playTranslatedText() async {
    if (translatedText.isNotEmpty && translatedText != 'Translating...') {
      await flutterTts.speak(translatedText);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No translated text to play')),
      );
    }
  }

  void _copyTranslatedText() async {
    if (translatedText.isNotEmpty && translatedText != 'Translating...') {
      await Clipboard.setData(ClipboardData(text: translatedText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Translated text copied to clipboard')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No translated text to copy')),
      );
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _inputController.dispose();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        primaryColor: const Color(0xFF2C426A),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2C426A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C426A)),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF2C426A),
          title: const Text(
            'Translation Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2),
          centerTitle: true,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter Text to Translate',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _inputController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Enter or paste your text here',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        style: const TextStyle(fontSize: 16),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _translateText(),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 600.ms, delay: 200.ms).slideX(begin: -0.2),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedLanguage,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF2C426A)),
                      items: languages.map((lang) {
                        return DropdownMenuItem(
                          value: lang,
                          child: Text(lang, style: const TextStyle(fontSize: 16)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedLanguage = value!;
                          flutterTts.setLanguage(_getTtsLanguageCode(value));
                        });
                      },
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 600.ms, delay: 300.ms).slideX(begin: 0.2),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.translate,
                    label: 'Translate',
                    onPressed: _translateText,
                    isLoading: _isTranslating,
                  ),
                  _buildActionButton(
                    icon: Icons.volume_up,
                    label: 'Play',
                    onPressed: _playTranslatedText,
                  ),
                  _buildActionButton(
                    icon: Icons.copy,
                    label: 'Copy',
                    onPressed: _copyTranslatedText,
                  ),
                ],
              ).animate().fadeIn(duration: 600.ms, delay: 400.ms).scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Translated Text',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        AnimatedOpacity(
                          opacity: _isTranslating ? 0.5 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            translatedText.isEmpty ? 'Translation will appear here' : translatedText,
                            style: TextStyle(
                              fontSize: 16,
                              color: translatedText.isEmpty ? Colors.grey : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 600.ms, delay: 500.ms).slideX(begin: -0.2),
              ),
              const SizedBox(height: 16),
              if (_isAdLoaded && _bannerAd != null)
                Center(
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ).animate().fadeIn(duration: 600.ms, delay: 600.ms),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Translation History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (translationHistory.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearHistory,
                      icon: const Icon(Icons.clear_all, color: Colors.red),
                      label: const Text('Clear All', style: TextStyle(color: Colors.red)),
                    ),
                ],
              ).animate().fadeIn(duration: 600.ms, delay: 700.ms),
              const SizedBox(height: 12),
              translationHistory.isEmpty
                  ? const Text(
                'No translations yet',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ).animate().fadeIn(duration: 600.ms, delay: 800.ms)
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: translationHistory.length,
                itemBuilder: (context, index) {
                  final history = translationHistory[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      title: Text(
                        'Input: ${history['input']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'To ${history['language']}: ${history['translated']}\n${history['timestamp']}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.volume_up, color: Color(0xFF2C426A)),
                            onPressed: () {
                              flutterTts.speak(history['translated']!);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteHistoryItem(index),
                          ),
                        ],
                      ),
                    ),
                  ).animate()
                      .fadeIn(duration: 600.ms, delay: (800 + index * 100).ms)
                      .slideX(begin: 0.2);
                },
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: checkOverlayPermission,
          backgroundColor: const Color(0xFF2C426A),
          icon: const Icon(Icons.open_in_new, color: Colors.white),
          label: const Text('Floating Window', style: TextStyle(color: Colors.white)),
        ).animate().fadeIn(duration: 600.ms, delay: 900.ms).scale(begin: const Offset(0.8, 0.8)),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
      ).animate().shimmer(duration: 1000.ms),
    );
  }

  String _getTtsLanguageCode(String language) {
    const languageCodes = {
      'English': 'en-US',
      'Hindi': 'hi-IN',
      'Gujarati': 'gu-IN',
      'French': 'fr-FR',
      'Spanish': 'es-ES',
      'German': 'de-DE',
      'Chinese': 'zh-CN',
    };
    return languageCodes[language] ?? 'en-US';
  }
}
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About App'),
        backgroundColor: const Color.fromRGBO(44, 66, 106, 1),
      ),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Floating Translator helps you instantly translate text from any app with a floating icon. \n\nVersion: 1.0.0',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class TranslationHistoryScreen extends StatelessWidget {
  const TranslationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Translation History'),
        backgroundColor: const Color.fromRGBO(44, 66, 106, 1),
      ),
      body: const Center(
        child: Text(
          'No translation history yet.',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class AppRoutes {
  static const home = '/';
  static const translationHistory = '/translation_history';
  static const about = '/about';
}
