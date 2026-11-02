import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'startup.dart';
import 'mobile_media_controls.dart';

WebViewEnvironment? _windowsEnvironment;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MusicApp());
}

Future<void> _initializeWindowsBrowser() async {
  final version = await WebViewEnvironment.getAvailableVersion();
  if (version == null || version.isEmpty) {
    throw StateError('Microsoft Edge WebView2 Runtime was not found.');
  }
  final localData = Platform.environment['LOCALAPPDATA'];
  if (localData == null) {
    throw StateError('Local application data is unavailable.');
  }
  final folder = Directory('$localData/MyTubeMusic/WebView2');
  await folder.create(recursive: true);
  _windowsEnvironment = await WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(userDataFolder: folder.path),
  );
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MyTube Music',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFFB4F272),
          scaffoldBackgroundColor: const Color(0xFF101310),
          useMaterial3: true,
        ),
        home: Platform.isWindows
            ? const BrowserStartup(
                initialize: _initializeWindowsBrowser,
                child: MusicScreen(),
              )
            : const MusicScreen(),
      );
}

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  InAppWebViewController? _web;
  final _search = TextEditingController();
  late final MobileMediaControls _mobileControls;
  bool _mediaErrorShown = false;

  @override
  void initState() {
    super.initState();
    _mobileControls = MobileMediaControls(
      enabled: Platform.isAndroid || Platform.isIOS,
      onCommand: (action, position) => _control(action, position: position),
    )..attach();
  }

  Future<void> _publishMedia(Map<String, dynamic> state) async {
    try {
      await _mobileControls.update({...state, 'background': _backgroundEnabled});
    } catch (_) {
      if (mounted && !_mediaErrorShown) {
        _mediaErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('System music controls are unavailable. You can still use the app player.'),
        ));
      }
    }
  }

  double _progress = 0;
  String? _error;
  String _title = 'Choose a song to start listening';
  bool _playing = false;
  bool _backgroundEnabled = false;
  bool _changingBackground = false;
  static const _backgroundChannel = MethodChannel('mytube/background');

  // Keep the website's visibility checks from stopping music when requested.
  // Native OS suspension and account restrictions remain outside this script.
  static const _backgroundScript = r'''
(() => {
  if (window.__mytubeVisibilityInstalled) return;
  window.__mytubeVisibilityInstalled = true;
  window.__mytubeBackground = false;
  const hidden = Object.getOwnPropertyDescriptor(Document.prototype, 'hidden');
  const visibility = Object.getOwnPropertyDescriptor(Document.prototype, 'visibilityState');
  if (hidden && hidden.get) Object.defineProperty(document, 'hidden', {
    configurable: true,
    get: () => window.__mytubeBackground ? false : hidden.get.call(document)
  });
  if (visibility && visibility.get) Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => window.__mytubeBackground ? 'visible' : visibility.get.call(document)
  });
  window.addEventListener('visibilitychange', event => {
    if (window.__mytubeBackground) event.stopImmediatePropagation();
  }, true);
})();
''';

  Future<void> _setBackground(bool enabled) async {
    if (_changingBackground) return;
    setState(() => _changingBackground = true);
    try {
      if (Platform.isAndroid) {
        await _backgroundChannel.invokeMethod<void>('setEnabled', enabled);
      }
      await _web?.evaluateJavascript(
        source: 'window.__mytubeBackground = $enabled;',
      );
      if (mounted) setState(() => _backgroundEnabled = enabled);
    } catch (_) {
      if (Platform.isAndroid && enabled) {
        try { await _backgroundChannel.invokeMethod<void>('setEnabled', false); } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not change background playback. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _changingBackground = false);
    }
  }

  bool _hasMedia = false;
  int _tab = 0;

  // Install once per document. Observe metadata without transferring audio or
  // downloading media. Playback quality remains controlled by YouTube Music.
  static const _playerScript = r'''
(() => {
  if (window.__mytubeInstalled) return;
  window.__mytubeInstalled = true;
  let previous = '';
  const report = () => {
    const media = document.querySelector('video, audio');
    const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
    const state = {
      title: metadata ? [metadata.title, metadata.artist].filter(Boolean).join(' · ') : document.title,
      trackTitle: metadata && metadata.title ? metadata.title : document.title,
      artist: metadata && metadata.artist ? metadata.artist : '',
      duration: media && Number.isFinite(media.duration) ? Math.round(media.duration * 1000) : 0,
      position: media && Number.isFinite(media.currentTime) ? Math.round(media.currentTime * 1000) : 0,
      playing: !!media && !media.paused && !media.ended,
      hasMedia: !!media && !!media.currentSrc
    };
    const serialized = JSON.stringify(state);
    if (serialized !== previous && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('playerState', state);
      previous = serialized;
    }
  };
  window.__mytubeControl = async (action, position) => {
    const media = document.querySelector('video, audio');
    if (['play', 'pause', 'toggle', 'seek'].includes(action)) {
      if (!media) return false;
      try {
        if (action === 'seek') {
          if (!Number.isFinite(position) || position < 0 || !Number.isFinite(media.duration)) return false;
          media.currentTime = Math.min(position, media.duration);
        } else if (action === 'pause' || (action === 'toggle' && !media.paused)) {
          media.pause();
        } else {
          await media.play();
        }
        report();
        return true;
      } catch (_) { return false; }
    }
    if (!['next', 'previous'].includes(action)) return false;
    const button = document.querySelector('ytmusic-player-bar .' + action + '-button');
    if (!button || button.disabled) return false;
    button.click();
    return true;
  };
  setInterval(report, 1000);
  document.addEventListener('play', report, true);
  document.addEventListener('pause', report, true);
  // Seek only while the player explicitly marks the current media as an ad.
  // Never change volume or playback rate: these persist into the next song.
  const skipAds = () => {
    const button = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
    if (button) button.click();
    const player = document.querySelector('.html5-video-player.ad-showing');
    const media = player && player.querySelector('video, audio');
    if (media && Number.isFinite(media.duration) && media.duration > 0) {
      try { media.currentTime = media.duration; } catch (_) {}
    }
  };
  setInterval(skipAds, 400);
  new MutationObserver(skipAds).observe(document.documentElement, {childList: true, subtree: true});
  const style = document.createElement('style');
  style.textContent = '.ytp-ad-overlay-container, ytm-promoted-sparkles-web-renderer, ytm-PromotedVideoRenderer, ytm-companion-ad-renderer { display:none !important; }';
  (document.head || document.documentElement).appendChild(style);
})();
''';

  @override
  void dispose() {
    _mobileControls.dispose().catchError((_) {});
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String url) async {
    setState(() { _error = null; _progress = 0; });
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _control(String action, {double? position}) async {
    try {
      final result = await _web?.callAsyncJavaScript(
        functionBody: 'if (!window.__mytubeControl) return false; return await window.__mytubeControl(action, position);',
        arguments: {'action': action, 'position': position},
      );
      if (mounted && result?.value != true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Use the player on the page for this action.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Player is not ready. Open a song and try again.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (await _web?.canGoBack() ?? false) {
            await _web?.goBack();
          } else if (Platform.isAndroid) {
            await SystemNavigator.pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Row(children: [Icon(Icons.graphic_eq), SizedBox(width: 10), Text('MyTube Music')]),
            actions: [IconButton(
              tooltip: 'Playback information', icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
                title: const Text('Made for listening'),
                content: const Text('Search music, explore playlists, and use your YouTube library. Audio quality is managed by YouTube Music; choose the highest available quality in its settings.\n\nAd skipping is best effort. Background playback, lock-screen controls, and available quality depend on your account, device, and YouTube. This app does not upgrade the source audio.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
              )),
            )],
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Songs, artists, albums',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (query) {
                    if (query.trim().isEmpty) return;
                    FocusScope.of(context).unfocus();
                    _load(Uri.https('music.youtube.com', '/search', {'q': query.trim()}).toString());
                  },
                ),
              ),
              if (Platform.isAndroid || Platform.isWindows)
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.headphones),
                  title: const Text('Background playback'),
                  subtitle: Text(Platform.isWindows
                      ? 'Listen with display off. Keep Windows awake in Power settings.'
                      : 'Listen with screen off. Turn off here when finished.'),
                  value: _backgroundEnabled,
                  onChanged: _changingBackground ? null : _setBackground,
                ),
              if (_progress < 1 && _error == null) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              Expanded(child: Stack(children: [
                InAppWebView(
                  webViewEnvironment: _windowsEnvironment,
                  initialUrlRequest: URLRequest(url: WebUri('https://music.youtube.com')),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    allowsPictureInPictureMediaPlayback: true,
                    contentBlockers: [ContentBlocker(
                      trigger: ContentBlockerTrigger(urlFilter: r'.*(doubleclick\.net|googleadservices\.com|googlesyndication\.com|youtube\.com/api/stats/ads|youtube\.com/pagead/).*'),
                      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
                    )],
                  ),
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: '$_backgroundScript\nwindow.__mytubeBackground = $_backgroundEnabled;',
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                    UserScript(source: _playerScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
                  ]),
                  onWebViewCreated: (controller) {
                    _web = controller;
                    controller.addJavaScriptHandler(handlerName: 'playerState', callback: (args) {
                      if (!mounted || args.isEmpty || args.first is! Map) return;
                      final state = Map<String, dynamic>.from(args.first as Map);
                      setState(() {
                        _title = state['title'] is String ? state['title'] as String : _title;
                        _playing = state['playing'] == true;
                        _hasMedia = state['hasMedia'] == true;
                      });
                      _publishMedia(state);
                    });
                  },
                  onLoadStart: (_, url) {
                    _publishMedia({'hasMedia': false});
                    if (mounted) setState(() { _error = null; _progress = 0; _hasMedia = false; _playing = false; });
                  },
                  onLoadStop: (controller, url) async {
                    await controller.evaluateJavascript(
                      source: 'window.__mytubeBackground = $_backgroundEnabled;',
                    );
                  },
                  onProgressChanged: (_, progress) { if (mounted) setState(() => _progress = progress / 100); },
                  onReceivedError: (_, request, error) {
                    if (mounted && request.isForMainFrame == true) setState(() => _error = 'Unable to load music. Check your connection and try again.');
                  },
                  onReceivedHttpError: (_, request, response) {
                    if (mounted && request.isForMainFrame == true) setState(() => _error = 'YouTube Music returned an error (${response.statusCode}).');
                  },
                ),
                if (_error != null) Positioned.fill(child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [const Icon(Icons.wifi_off, size: 40), const SizedBox(height: 16), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: () { setState(() => _error = null); _web?.reload(); }, icon: const Icon(Icons.refresh), label: const Text('Try again'))],
                  ))),
                )),
              ])),
              if (_hasMedia) Material(
                color: const Color(0xFF253020),
                child: ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Previous song', onPressed: () => _control('previous'), icon: const Icon(Icons.skip_previous)),
                    IconButton(tooltip: _playing ? 'Pause' : 'Play', onPressed: () => _control('toggle'), icon: Icon(_playing ? Icons.pause : Icons.play_arrow)),
                    IconButton(tooltip: 'Next song', onPressed: () => _control('next'), icon: const Icon(Icons.skip_next)),
                  ]),
                ),
              ),
            ]),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) {
              setState(() => _tab = index);
              _load(['https://music.youtube.com', 'https://music.youtube.com/explore', 'https://music.youtube.com/library'][index]);
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Listen'),
              NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
            ],
          ),
        ),
      );
}
