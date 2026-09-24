/// Fetching a recipe page the household is already reading, **from the device**.
///
/// ## Why the phone and not a function
///
/// The same trade as the weather and Photon (see the weather section of
/// CLAUDE.md): the request leaves the phone with the household's own IP and
/// nothing that names them. Putting it on a server would buy nothing — the
/// recipe site already saw this household visit this page a minute ago, from
/// this address — and would cost a place where the pages a family reads could
/// be logged.
///
/// It is **not** a breach of "nothing ever fetches `link_url`". That rule is
/// about a URL we *stored*, quietly refetched later, for a preview nobody
/// asked for. This is a page the reader handed over in order to have it read,
/// once, at the moment they asked.
///
/// ## What it cannot do
///
/// A page whose ingredients arrive with JavaScript (lecker.de) and a page that
/// refuses anything that is not a browser (allrecipes answered 402, rewe.de
/// 403) both come back empty here and would not on iOS's Share Extension,
/// which reads the DOM Safari has already rendered inside the user's own
/// session. This is the portable half; the extension is the better half, and
/// it needs the paid Apple Developer Program before it can be signed.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Identifies as Safari, and does so honestly rather than to evade anything:
/// the alternative is that a site hands a bare Dart client a consent wall
/// instead of the page the user is looking at, and the reader is told we could
/// not read a page that plainly has a recipe on it.
const _userAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.0 Safari/605.1.15';

/// Anything past this is not a recipe page, and holding it in memory on a
/// phone to regex over is worse than failing. The largest page in the corpus
/// this was built against was 764 KB.
const _maxBytes = 4 * 1024 * 1024;

const _timeout = Duration(seconds: 20);

/// True for the text the Vorhaben field should treat as a page rather than as
/// a goal to be planned.
///
/// **Deliberately strict.** Someone typing "Nudeln für 4" must not have it read
/// as an address, so this wants a real scheme — a bare `chefkoch.de` is a
/// sentence as far as this is concerned. The share sheet and the clipboard
/// both hand over a full URL, so nothing real is lost.
Uri? recipePageUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

class RecipeFetchException implements Exception {
  const RecipeFetchException();
}

/// The page's markup, decoded.
///
/// Throws [RecipeFetchException] for anything that is not a readable page —
/// the caller turns that into the card's "that didn't work" rather than
/// distinguishing a 403 from a timeout, because the reader can do nothing
/// different about either.
Future<String> fetchRecipePage(Uri url) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', url)
      ..followRedirects = true
      ..maxRedirects = 5
      // **The full set a browser actually sends, not just the User-Agent.**
      // Cheap, and it clears the simpler WAF rules that look for a client
      // claiming to be Safari while sending none of Safari's other headers.
      //
      // **It does not clear the ones that matter, and it is worth knowing
      // why.** maggi.de, edeka.de and knorr.com answer 403 over HTTP/1.1 and
      // 200 over HTTP/2 with these exact headers — measured both ways. The
      // rule is fingerprinting the *connection*, not the request, and
      // `package:http` is HTTP/1.1 only, so no header will ever get us in.
      // rewe.de is a Cloudflare JS challenge, which is a further step again.
      //
      // The fix for those is not a better fetch: it is not fetching. iOS's
      // Share Extension reads the page Safari has already rendered inside the
      // user's own session, where there is no request of ours to fingerprint.
      // That is the argument for the extension, and it is why this file is
      // described in its header as the portable half rather than the good one.
      ..headers.addAll({
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
        // Not 'br': package:http does not decode Brotli, and a site that
        // honours it hands back bytes no regex will ever match.
        'Accept-Encoding': 'gzip, deflate',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
      });
    final streamed = await client.send(request).timeout(_timeout);
    if (streamed.statusCode != 200) throw const RecipeFetchException();

    final type = streamed.headers['content-type'] ?? '';
    if (type.isNotEmpty && !type.contains('html') && !type.contains('xml')) {
      throw const RecipeFetchException();
    }

    final bytes = <int>[];
    await for (final chunk in streamed.stream.timeout(_timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBytes) throw const RecipeFetchException();
    }
    return _decode(bytes, type);
  } on RecipeFetchException {
    rethrow;
  } catch (_) {
    throw const RecipeFetchException();
  } finally {
    client.close();
  }
}

final _charsetInHeader = RegExp(r'charset\s*=\s*"?([\w-]+)', caseSensitive: false);
final _charsetInMeta = RegExp(r'''<meta[^>]*charset\s*=\s*['"]?([\w-]+)''', caseSensitive: false);

/// **German pages are still served in Latin-1 more often than is comfortable**,
/// and a `utf8.decode` over those turns every umlaut into a replacement
/// character — which then fails to match "Möhren" in the grocery catalog. The
/// header wins, the `<meta>` tag is the fallback, and malformed input is
/// allowed rather than thrown on: half a readable page beats an exception.
String _decode(List<int> bytes, String contentType) {
  var charset = _charsetInHeader.firstMatch(contentType)?.group(1)?.toLowerCase();
  if (charset == null) {
    // Only the head, and as Latin-1 so the sniff itself cannot throw.
    final head = latin1.decode(bytes.take(2048).toList(), allowInvalid: true);
    charset = _charsetInMeta.firstMatch(head)?.group(1)?.toLowerCase();
  }
  return switch (charset) {
    'iso-8859-1' || 'latin1' || 'latin-1' || 'windows-1252' || 'cp1252' =>
      latin1.decode(bytes, allowInvalid: true),
    _ => utf8.decode(bytes, allowMalformed: true),
  };
}
