import 'package:flutter/material.dart';

/// Paint a Flutter frame before starting native browser initialization.
class BrowserStartup extends StatefulWidget {
  const BrowserStartup({
    super.key,
    required this.initialize,
    required this.child,
    this.timeout = const Duration(seconds: 20),
  });

  final Future<void> Function() initialize;
  final Widget child;
  final Duration timeout;

  @override
  State<BrowserStartup> createState() => _BrowserStartupState();
}

class _BrowserStartupState extends State<BrowserStartup> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize().timeout(widget.timeout);
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return Scaffold(
      appBar: AppBar(title: const Text('MyTube Music')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  const Text('Starting the music browser…'),
                ] else ...[
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 24),
                  const Text('The music browser could not start.'),
                  const SizedBox(height: 16),
                  const SelectableText(
                    'Close the app, install or repair the Microsoft Edge WebView2 '
                    'Evergreen Runtime (x64), then reopen it. Extract the entire '
                    'app ZIP with its DLLs and data folder before launching.\n\n'
                    'https://developer.microsoft.com/microsoft-edge/webview2/',
                  ),
                  const SizedBox(height: 16),
                  SelectableText('Startup details: $_error'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
