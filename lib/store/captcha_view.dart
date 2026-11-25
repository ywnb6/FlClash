import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Draws the panel's own human check and reports the token it issues.
///
/// The widget is the page the provider publishes, so nothing about the check
/// lives in the app: the site key, the size and the language all come from the
/// panel, and a turnstile or reCAPTCHA key is used exactly as served.
class CaptchaView extends StatefulWidget {
  const CaptchaView({
    super.key,
    required this.siteKey,
    required this.type,
    required this.onToken,
    this.height = 78,
  });

  final String siteKey;

  /// `turnstile` or `recaptcha`; anything else falls back to turnstile.
  final String type;
  final ValueChanged<String> onToken;
  final double height;

  @override
  State<CaptchaView> createState() => _CaptchaViewState();
}

class _CaptchaViewState extends State<CaptchaView> {
  WebViewController? _controller;

  String get _script => widget.type.startsWith('recaptcha')
      ? '''
<script src="https://www.google.com/recaptcha/api.js?render=explicit"></script>
<div id="cap"></div>
<script>
  grecaptcha.render('cap', {
    sitekey: '${widget.siteKey}',
    callback: function (t) { Captcha.post(t); }
  });
</script>
'''
      : '''
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"></script>
<div id="cap"></div>
<script>
  turnstile.render('#cap', {
    sitekey: '${widget.siteKey}',
    callback: function (t) { Captcha.post(t); }
  });
</script>
''';

  /// The page has to sit on a real origin, or the provider's script refuses to
  /// run and the widget shows its own "cannot reach the site" notice.
  static String _baseUrlFor(String type) => type.startsWith('recaptcha')
      ? 'https://www.google.com/'
      : 'https://challenges.cloudflare.com/';

  @override
  void initState() {
    super.initState();
    if (widget.siteKey.isEmpty) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'Captcha',
        onMessageReceived: (message) {
          final token = message.message.trim();
          if (token.isNotEmpty) widget.onToken(token);
        },
      )
      ..loadHtmlString(
        '<!DOCTYPE html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>body{margin:0;background:transparent}</style>'
        '</head><body>$_script</body></html>',
        baseUrl: _baseUrlFor(widget.type),
      );
    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: WebViewWidget(controller: controller),
    );
  }
}

/// Escape helper for embedding the site key in the page above.
String captchaSiteKeyLiteral(String key) => jsonEncode(key);
