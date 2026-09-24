/// A recipe video, turned into the same [ListPlan] a recipe page gives.
///
/// ## Why a video at all
///
/// Plenty of households never open a recipe blog. They watch somebody cook the
/// thing, and the ingredients are written out underneath — which is a list in
/// a language, sitting on a page we can already read.
///
/// ## What this is worth, measured
///
/// 24 recipe videos from four German cooking channels: **15 carried a list we
/// could take** (62%). That is a long way short of the ~90% a marked-up recipe
/// page gives, and the reason is not technical — a page that wants Google's
/// recipe rich card *must* publish `recipeIngredient`, and a video description
/// is a free-text box with no such obligation. Some channels write a clean
/// list, some link to their blog, and some write the narration script.
///
/// The misses fail cleanly: [parseYoutubePage] answers null and the card says
/// there were no ingredients in the description, rather than producing a Liste
/// with "Subscribe to my channel" on it. See [_ingredientBlock] in
/// [recipe_import.dart](recipe_import.dart) for why it refuses so much.
///
/// ## Where the description comes from
///
/// The watch page carries it in `ytInitialPlayerResponse`, server-rendered, no
/// JavaScript needed. `/watch` is **not** disallowed by YouTube's robots.txt
/// (`/youtubei/` — the internal API — is, and is not touched here).
///
/// **The known risk is the EU consent wall.** A cookieless request from an
/// EEA address can be redirected to `consent.youtube.com`, which carries no
/// description and therefore reads here as "no ingredients". Nothing is done
/// to get around it: declaring consent on the reader's behalf by sending a
/// `CONSENT` cookie would be lying to them and to YouTube. If it turns out to
/// bite in practice the answer is the official Data API, which returns the
/// description with a key and is the defensible route for a paid app anyway.
library;

import 'dart:convert';

import 'recipe_import.dart';

/// The eleven characters YouTube gives a video, from any address that names
/// one — `youtube.com/watch?v=`, a `youtu.be` short link (what iOS's share
/// sheet hands over, `?si=` tracking and all), a Short, an embed or a stream.
///
/// Null for every other URL, which is how the import path tells a video from
/// an ordinary page.
String? youtubeVideoId(Uri url) {
  final host = url.host.toLowerCase();
  if (host == 'youtu.be') return _asId(url.pathSegments.firstOrNull);
  if (host != 'youtube.com' && host != 'www.youtube.com' && host != 'm.youtube.com') return null;

  final query = _asId(url.queryParameters['v']);
  if (query != null) return query;
  final segments = url.pathSegments;
  if (segments.length >= 2 && const {'shorts', 'embed', 'live', 'v'}.contains(segments.first)) {
    return _asId(segments[1]);
  }
  return null;
}

final _idShape = RegExp(r'^[A-Za-z0-9_-]{11}$');
String? _asId(String? candidate) =>
    candidate != null && _idShape.hasMatch(candidate) ? candidate : null;

/// The one address worth fetching for a video, whatever shape the share sheet
/// handed over. A Short and a `youtu.be` link serve different markup from the
/// same id; the desktop watch page is the one that carries the description.
Uri youtubeWatchUrl(String videoId) =>
    Uri.https('www.youtube.com', '/watch', {'v': videoId});

/// `"shortDescription":"…"` inside `ytInitialPlayerResponse`.
///
/// Read with a regex rather than by parsing the blob, which is a megabyte of
/// JSON holding the entire watch page. The capture stops at the first
/// unescaped quote, and the escapes are then undone by handing the raw capture
/// back to the JSON decoder as a string literal — so `\n` becomes the line
/// breaks the whole ingredient block depends on.
final _shortDescription = RegExp(r'"shortDescription":"((?:[^"\\]|\\.)*)"');

/// The title from the same object. Anchored on the key that follows it,
/// because `"title"` on its own appears some hundreds of times on a watch
/// page — every related video has one.
final _videoTitle = RegExp(r'"title":"((?:[^"\\]|\\.)*)","lengthSeconds"');

/// What a watch page says about itself. Null when the markup carried no
/// player response — a consent wall, an age gate, or a page that is not a
/// video at all.
({String title, String description})? youtubeVideoDetails(String html) {
  final description = _unescape(_shortDescription.firstMatch(html)?.group(1));
  if (description == null) return null;
  return (title: _unescape(_videoTitle.firstMatch(html)?.group(1)) ?? '', description: description);
}

String? _unescape(String? raw) {
  if (raw == null) return null;
  try {
    return jsonDecode('"$raw"') as String;
  } catch (_) {
    return null;
  }
}

/// A watch page → a plan, or null when the description held no list.
RecipeImport? parseYoutubePage({required String html, required String pageUrl}) {
  final details = youtubeVideoDetails(html);
  if (details == null) return null;
  return parseRecipeText(
    text: details.description,
    title: cleanVideoTitle(details.title),
    pageUrl: pageUrl,
  );
}

/// A video title is written to be clicked, and a Liste is written to be read.
///
/// The channel's own name after a pipe goes, and so does the clickbait tail
/// after a `|` or a `//`; what is left is trimmed of ornament at both ends.
/// Deliberately conservative — the reader renames a Liste in one tap, and a
/// title cut to pieces by a clever rule is worse than a long honest one.
String cleanVideoTitle(String raw) {
  var title = raw.split(RegExp(r'\s+(?:\||//|–\s*Rezept\b)')).first.trim();
  title = title.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');
  title = title.replaceFirst(RegExp(r'[\s!.…]+$'), '').trim();
  if (title.length > 60) title = '${title.substring(0, 59).trimRight()}…';
  return title.isEmpty ? raw.trim() : title;
}

/// The link in a description that the channel itself calls the recipe.
///
/// **Only a labelled one.** A cooking channel's description carries ten or
/// more links — the knife, the book, the shop, three social networks — and
/// "the first link that is not social" lands on a bookshop, which was measured
/// rather than guessed. But a line reading `❤ Zum Rezept:` above a URL is the
/// channel saying where the recipe is, and following that one is worth a
/// second fetch when the description itself held no list.
///
/// Returns null unless the cue and the link are on the same line or adjacent
/// ones, and never returns a link to a shop or a social network.
Uri? recipeLinkInDescription(String description) {
  final lines = const LineSplitter().convert(description);
  for (var i = 0; i < lines.length; i++) {
    if (!_recipeCue.hasMatch(lines[i])) continue;
    for (final line in [lines[i], if (i + 1 < lines.length) lines[i + 1]]) {
      for (final match in _urlInText.allMatches(line)) {
        final url = Uri.tryParse(match.group(0)!.replaceFirst(RegExp(r'[.,;)\]]+$'), ''));
        if (url == null || !url.hasAuthority) continue;
        if (_notARecipeHost.hasMatch(url.host)) continue;
        return url;
      }
    }
  }
  return null;
}

/// "Zum Rezept", "Full recipe", "Receita completa". Word-initial so that
/// "Rezepte" in a channel slogan does not qualify a link to the shop.
final _recipeCue = RegExp(
  r'\b(rezept|recipe|receita|receta|ricetta|nachlesen|nachkochen)',
  caseSensitive: false,
);

final _urlInText = RegExp(r'https?://[^\s<>"]+');

/// Everything a cooking channel links that is not a recipe. `sallys-shop.de`
/// is caught by `shop`, while the `sallys.link` redirector is not — and it
/// resolves to the blog, which is the point.
final _notARecipeHost = RegExp(
  r'youtu|amzn|amazon|shop|store|instagram|facebook|tiktok|pinterest|twitter'
  r'|x\.com|threads|spotify|patreon|linktr|paypal|tiny\.cc',
  caseSensitive: false,
);
