// lib/main.dart — Hostel Mirror
// Lightweight WebView wrapper that streams the Flutter Web app.
// With local notification support via MethodChannel.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Notification channels ──────────────────────────────────
final _notificationsPlugin = FlutterLocalNotificationsPlugin();
const _methodChannel = MethodChannel('hostel.mirror/notifications');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init local notifications
  await _initNotifications();

  // Handle notification taps from background
  _methodChannel.setMethodCallHandler(_handleMethodCall);

  runApp(const HostelMirrorApp());
}

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await _notificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse resp) {
      // Notification tapped — could navigate to a specific screen
    },
  );

  // Create notification channel
  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'hostel_alerts',
          'Hostel Alerts',
          description: 'Rent, insurance, and task notifications',
          importance: Importance.high,
        ),
      );

  // Request permission (Android 13+)
  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<dynamic> _handleMethodCall(MethodCall call) async {
  if (call.method == 'notify') {
    final args = call.arguments as Map?;
    final title = args?['title'] ?? 'Hostel Alert';
    final body = args?['body'] ?? '';
    final id = args?['id'] ?? 0;
    await showLocalNotification(id: id, title: title, body: body);
  }
}

Future<void> showLocalNotification({
  required int id,
  required String title,
  required String body,
}) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'hostel_alerts',
      'Hostel Alerts',
      channelDescription: 'Rent, insurance, and task notifications',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  await _notificationsPlugin.show(id, title, body, details);
}

// ════════════════════════════════════════════════════════

class HostelMirrorApp extends StatelessWidget {
  const HostelMirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hostel Mirror',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF112E81),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MirrorScreen(),
    );
  }
}

class MirrorScreen extends StatefulWidget {
  const MirrorScreen({super.key});

  @override
  State<MirrorScreen> createState() => _MirrorScreenState();
}

class _MirrorScreenState extends State<MirrorScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  int _loadingProgress = 0;
  MethodChannel? _webChannel;

  static const String _webUrl = 'https://medo962006.github.io/GMRental/';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF112E81))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onProgress: (int progress) {
            if (mounted) setState(() => _loadingProgress = progress);
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = false;
              });
              // Inject JS bridge for notifications after page loads
              _injectNotificationBridge();
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.parse(request.url);
            if (uri.host.contains('medo962006.github.io') ||
                uri.host.contains('supabase.co') ||
                uri.host.contains('supabase.com') ||
                uri.scheme == 'tel' ||
                uri.scheme == 'https' ||
                uri.scheme == 'http') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'MirrorBridge',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = Map<String, dynamic>.from(
              // Simple JSON parse — expects {"title":"...","body":"...","id":123}
              _parseJs(message.message),
            );
            showLocalNotification(
              id: data['id'] ?? 0,
              title: data['title'] ?? 'Hostel Alert',
              body: data['body'] ?? '',
            );
          } catch (_) {}
        },
      )
      ..loadRequest(Uri.parse(_webUrl));
  }

  Map<String, dynamic> _parseJs(String message) {
    // Minimal JSON decode — handles {"key":"value","id":123} format
    final map = <String, dynamic>{};
    final strRegex = RegExp(r'"(\w+)":"([^"]*)"');
    for (final m in strRegex.allMatches(message)) {
      map[m.group(1)!] = m.group(2);
    }
    final intRegex = RegExp(r'"(\w+)":(\d+)');
    final idMatch = intRegex.firstMatch(message);
    if (idMatch != null) {
      final parsed = int.tryParse(idMatch.group(2)!);
      if (parsed != null) map[idMatch.group(1)!] = parsed;
    }
    return map;
  }

  Future<void> _injectNotificationBridge() async {
    // Check if web app has notification permission and hook into Supabase
    await _controller.runJavaScript('''
      // Hook into Supabase realtime to trigger local notifications
      window.mirrorNotify = function(title, body, id) {
        if (window.MirrorBridge) {
          window.MirrorBridge.postMessage(JSON.stringify({
            title: title,
            body: body,
            id: id || 0
          }));
        }
      };

      // Request browser notification permission as fallback
      if ('Notification' in window && Notification.permission === 'default') {
        Notification.requestPermission();
      }
    ''');
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _isLoading = true;
    });
    _controller.loadRequest(Uri.parse(_webUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final canGoBack = await _controller.canGoBack();
        if (canGoBack) {
          _controller.goBack();
        } else {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF112E81),
        body: SafeArea(
          minimum: EdgeInsets.zero,
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),

              if (_isLoading && !_hasError)
                Container(
                  color: const Color(0xFF112E81),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.apartment, size: 64, color: Colors.white70),
                        const SizedBox(height: 24),
                        const Text('Hostel Manager',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text('Loading your dashboard...',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14)),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: 200,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _loadingProgress > 0
                                  ? _loadingProgress / 100
                                  : null,
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_hasError)
                Container(
                  color: const Color(0xFF112E81),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              size: 72,
                              color: Colors.white.withValues(alpha: 0.5)),
                          const SizedBox(height: 24),
                          const Text('Hostel Server Unreachable',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Text(
                              'Check your internet connection and try again.\nThe app will auto-reconnect when the server is back.',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                  height: 1.5),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try Again'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF112E81),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
