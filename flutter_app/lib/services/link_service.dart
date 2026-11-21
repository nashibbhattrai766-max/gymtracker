import 'package:flutter/services.dart';

/// Opens a link (YouTube video, search) in its app or the browser.
/// Native intent via MainActivity — no url_launcher plugin needed.
class LinkService {
  static const _channel = MethodChannel('gymtracker/system');

  static Future<bool> open(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
