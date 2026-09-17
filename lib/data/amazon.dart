/// Amazon search links for the articles on a non-grocery list.
///
/// **Nothing here is stored and nothing here is fetched.** The link is built
/// from the article's own text at the moment the row is drawn, handed to the
/// device by `external_links.dart`, and forgotten. That is the difference
/// between this and `list_items.link_url`, which means *the shop page this
/// particular article points at* and is set deliberately by the household: our
/// partner tag never lands in their data, a list shared outward carries no tag,
/// and turning the whole thing off is deleting this file rather than a
/// migration. See the Amazon section of [docs/list-planner.md].
///
/// **Groceries are deliberately excluded**, and not for a legal reason: nobody
/// orders a cucumber from Amazon, so a badge under every article on the weekly
/// shop would be fourteen pieces of advertising nobody will ever tap. The
/// hardware run, the school-supplies list and the camping trip are where the
/// link is actually useful.
///
/// **A search, never a product.** We have no ASINs, and asking a model for one
/// produces a plausible 404 — see the same doc section.
library;

/// Our PartnerNet tag per marketplace, and **the only thing that decides
/// whether the badge exists at all.** A marketplace with no tag draws no badge:
/// an untagged Amazon link earns nothing, and an unlabelled one would be
/// advertising without the Werbekennzeichnung German law requires. Failing
/// closed is therefore both the honest default and the safe one.
///
/// Keyed by the marketplace host's country, not by language — a household in
/// Austria shops at amazon.de, and one in Portugal at amazon.es, because
/// neither country has a marketplace of its own.
const Map<String, String> _partnerTags = {
  // TODO(philipe): paste the real PartnerNet tags. Until a line here has a
  // non-empty tag, that marketplace simply shows no badge — nothing breaks and
  // nothing untagged goes out.
  'DE': '',
  'BR': '',
  'ES': '',
  'US': '',
  'GB': '',
};

/// Which marketplace a country shops in. Only the countries that differ from
/// "its own marketplace" need a line; everything unknown falls back by
/// language, below.
const Map<String, String> _marketplaceOf = {
  'DE': 'DE',
  'AT': 'DE',
  'CH': 'DE',
  'LI': 'DE',
  'BR': 'BR',
  'ES': 'ES',
  'PT': 'ES',
  'US': 'US',
  'CA': 'US',
  'MX': 'US',
  'GB': 'GB',
  'IE': 'GB',
};

/// The host for each marketplace.
const Map<String, String> _hostOf = {
  'DE': 'www.amazon.de',
  'BR': 'www.amazon.com.br',
  'ES': 'www.amazon.es',
  'US': 'www.amazon.com',
  'GB': 'www.amazon.co.uk',
};

/// Last resort when the device reports a country we have no marketplace for:
/// the language the app is being read in. A Brazilian phone set to English
/// still gets amazon.com.br if its region says BR; this only catches the case
/// where the region says nothing useful at all.
const Map<String, String> _marketplaceOfLanguage = {'de': 'DE', 'pt': 'BR', 'es': 'ES', 'en': 'US'};

/// The marketplace to send this reader to, from the device's own region with
/// the app's language as the fallback.
///
/// **The device's region, never an IP lookup and never the household address.**
/// A geo-IP service would mean the household's address leaving the phone to
/// decide which shop to link to, which is a wildly disproportionate trade for
/// choosing between five hosts — and this app already refuses that trade for
/// the map and the weather. `countryCode` is set from the phone's own Region
/// setting, costs no permission, no network and no personal data at all.
String? amazonMarketplace({String? countryCode, required String languageCode}) {
  final country = countryCode?.toUpperCase();
  final byCountry = country == null ? null : _marketplaceOf[country];
  return byCountry ?? _marketplaceOfLanguage[languageCode];
}

/// An Amazon search for [article], and whether it carries our partner tag.
///
/// **`sponsored` is the whole legal hinge.** An untagged search is a search —
/// we earn nothing, so it is not advertising and needs no label. The moment the
/// tag goes on it becomes advertising, and German law (§ 5a Abs. 4 UWG) wants
/// that recognisable *at the link*. So the flag travels with the URL rather
/// than being re-derived by each caller, and no caller can tag a link without
/// being told that it did.
///
/// [article] is the household's own words, so it is percent-encoded rather than
/// trusted into a URL: an article called "Farbe & Pinsel" must not become two
/// query parameters.
({String url, bool sponsored}) amazonSearch(String article, {String? marketplace}) {
  // Falls back to the German store, which is what this did before there were
  // marketplaces at all — the household that sees no region still gets a shop.
  final market = marketplace ?? 'DE';
  final host = _hostOf[market] ?? _hostOf['DE']!;
  final tag = _partnerTags[market];
  final query = Uri.encodeQueryComponent(article.trim());

  if (tag == null || tag.isEmpty) {
    return (url: 'https://$host/s?k=$query', sponsored: false);
  }
  return (url: 'https://$host/s?k=$query&tag=$tag', sponsored: true);
}

/// Whether any marketplace has a tag yet. The per-article badge is gated on
/// this: before a tag exists it earns nothing, so putting one under every
/// article would be clutter with no purpose. The item menu's "Bei Amazon
/// suchen" is *not* gated — an untagged search is still useful to the reader.
bool get amazonConfigured => _partnerTags.values.any((t) => t.isNotEmpty);
