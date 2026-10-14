import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdFreeYouTubeApp());
}

class AdFreeYouTubeApp extends StatelessWidget {
  const AdFreeYouTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const YouTubeWrapperScreen(),
    );
  }
}

class YouTubeWrapperScreen extends StatefulWidget {
  const YouTubeWrapperScreen({super.key});

  @override
  State<YouTubeWrapperScreen> createState() => _YouTubeWrapperScreenState();
}

class _YouTubeWrapperScreenState extends State<YouTubeWrapperScreen> {
  InAppWebViewController? _webViewController;

  // JavaScript injected into the DOM to strip ad slots, auto-skip video ads,
  // and prevent YouTube from pausing audio when the screen locks.
  static const String _adBlockAndBgScript = '''
    (function() {
      // 1. Spoof Page Visibility API so background audio keeps playing
      Object.defineProperty(document, 'hidden', { get: () => false });
      Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
      window.addEventListener('visibilitychange', (e) => e.stopImmediatePropagation(), true);

      // 2. Inject CSS to hide companion banners and promoted feed cards
      const style = document.createElement('style');
      style.innerHTML = `
        ytm-promoted-sparkles-web-renderer,
        ytm-PromotedVideoRenderer,
        ytm-companion-ad-renderer,
        .ytp-ad-overlay-container,
        .ad-interrupting { display: none !important; }
      `;
      document.head.appendChild(style);

      // 3. Watch player state to auto-skip or fast-forward video ads
      const skipAds = () => {
        const skipBtn = document.querySelector(
          '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button'
        );
        if (skipBtn) skipBtn.click();

        const player = document.querySelector('.html5-video-player.ad-showing');
        const video = document.querySelector('video');
        if (player && video) {
          video.muted = true;
          if (!isNaN(video.duration) && video.duration > 0) {
            video.currentTime = video.duration;
          } else {
            video.playbackRate = 16.0;
          }
        }
      };

      const observer = new MutationObserver(skipAds);
      observer.observe(document.documentElement, { childList: true, subtree: true });
      setInterval(skipAds, 400);
    })();
  ''';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_webViewController != null && await _webViewController!.canGoBack()) {
          await _webViewController!.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('https://m.youtube.com')),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              allowsPictureInPictureMediaPlayback: true,
              contentBlockers: [
                ContentBlocker(
                  trigger: ContentBlockerTrigger(
                    urlFilter: ".*(doubleclick\\.net|googleadservices\\.com|googlesyndication\\.com|youtube\\.com/api/stats/ads|youtube\\.com/pagead/).*",
                  ),
                  action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
                ),
              ],
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: _adBlockAndBgScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
          ),
        ),
      ),
    );
  }
}