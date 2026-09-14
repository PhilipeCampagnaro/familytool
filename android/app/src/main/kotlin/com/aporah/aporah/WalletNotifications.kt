package com.aporah.aporah

/// One payment, read off a wallet's own notification.
data class WalletPayment(
    val merchant: String,
    val amountCents: Long,
    val currency: String,
    val cardLabel: String?,
    /// True when the merchant was inferred rather than read: nothing could be
    /// named at all, the last-resort naming attempt had to be used, or what was
    /// read still carries the wallet's own vocabulary in it. The row is still
    /// filed — the payment happened — and the Ausgaben page's review drawer is
    /// where it gets its two-second fix, exactly as for an Apple Pay row that
    /// arrived with a hole in it.
    val needsReview: Boolean,
)

/// Turning a wallet's payment notification into a spend.
///
/// **This is a guess, and the whole file is written as one.** Apple hands the
/// App Intent typed fields; Android hands us a sentence a product team wrote for
/// a human, in the phone's language, which changes without notice when Google
/// Play services updates. So nothing here matches a known layout: it looks for
/// an *amount with a currency on it* anywhere in the notification, and treats
/// everything else as material for naming the shop.
///
/// Two rules fall out of that and both matter more than any pattern below:
///
/// - **No amount, no row.** A wallet posts plenty that is not a payment — a pass
///   added, a card verified — and a notification we cannot price is one of
///   those far more often than it is a payment we mis-read.
/// - **A merchant we had to guess is flagged, never dropped.** Same trade the
///   ingest function already makes for Apple's empty-merchant defect.
///
/// Kept free of Android imports so it can be read, reasoned about and tested as
/// the pure function it is.
object WalletNotifications {
    /// **The allowlist, and the only thing that decides what is ever looked at.**
    /// Four wallet apps. Every other package on the phone is dropped by
    /// [SpendNotificationListener] on its first line, before a single extra is
    /// read — see the note there, because this set is the whole of that promise.
    ///
    /// **Google Play services is deliberately not in it.** It is where the
    /// tap-to-pay "Purchases" notification used to come from, and adding it would
    /// catch the handful of phones that still post it there. It is also not a
    /// payments app: it notifies about device scanning, account warnings, nearby
    /// sharing and a dozen other things, so allowing it would mean running a
    /// parser over most of what Google sends a phone in order to find the one
    /// notification that is a payment. Google Wallet has posted its own purchase
    /// notifications since 2024. Missing a payment on an old phone is the
    /// cheaper mistake, and the user can still type it in.
    ///
    /// Adding a package here is not a small change. It widens what this process
    /// reads, which is the one thing the setup page promises it does not do.
    val sourcePackages: Set<String> = setOf(
        // Google Wallet.
        "com.google.android.apps.walletnfcrel",
        // Samsung Wallet, and the payment framework that ships beside it.
        "com.samsung.android.spay",
        "com.samsung.android.spayfw",
    )

    private val DOLLAR = 0x24.toChar()
    private val SYMBOL = "[€" + DOLLAR + "£¥₹₺₩]"

    /// Spelled out rather than `[A-Z]{3}`, which would read the "ALD" in a shop
    /// name as a currency and price a payment at whatever number came after it.
    private const val CODES =
        "EUR|USD|GBP|CHF|SEK|NOK|DKK|PLN|CZK|HUF|RON|BGN|TRY|JPY|CAD|AUD|NZD|ISK|INR|BRL|ZAR|MXN|SGD|HKD"

    /// Grouped thousands first, so "1.234,56" is one number and not "1" followed
    /// by a decimal. Both conventions reach this parser — the phone's language
    /// decides which, and the household may be reading English on a German SIM.
    private const val NUMBER =
        "\\d{1,3}(?:[\\u00a0\\u202f .,]\\d{3})+(?:[.,]\\d{1,2})?|\\d+(?:[.,]\\d{1,2})?"

    private val MARKER = "(?:" + SYMBOL + "|\\b(?:" + CODES + ")\\b)"
    private val AMOUNT_LEADING = Regex(MARKER + "\\s?(" + NUMBER + ")")
    private val AMOUNT_TRAILING = Regex("(" + NUMBER + ")\\s?" + MARKER)

    private val SYMBOL_CODES = mapOf(
        '€' to "EUR",
        DOLLAR to "USD",
        '£' to "GBP",
        '¥' to "JPY",
        '₹' to "INR",
        '₺' to "TRY",
        '₩' to "KRW",
    )

    /// "Visa ••••1234", "•• 7890", "Mastercard *4321". The masked digits are the
    /// reliable part; the brand in front of them is taken when it is there.
    private val CARD = Regex("([\\p{L}]{3,16})?\\s*[•*·×]{2,}\\s*(\\d{3,4})")

    /// What the wallet calls itself, and what it says about the payment rather
    /// than about the shop. A notification titled "Google Pay" names the app and
    /// one titled "Zahlung erfolgreich" names the event; filing a month of
    /// payments to a merchant called either is worse than admitting we did not
    /// catch the name.
    ///
    /// **Single words, tested as whole words**, because the candidate is split on
    /// non-letters before any of this is checked. Matching these as substrings
    /// would disqualify Kaufland for containing "kauf" and PayPal for containing
    /// "pay". A candidate made *entirely* of these words is thrown away; one that
    /// merely contains some of them is kept and flagged, because "Zahlung REWE"
    /// probably is REWE and is still not a name we read cleanly.
    private val GENERIC = setOf(
        "google", "samsung", "pay", "wallet", "purchase", "purchases", "payment",
        "payments", "paid", "card", "transaction", "receipt", "complete",
        "completed", "successful", "success", "approved",
        "zahlung", "zahlungen", "einkauf", "bezahlt", "karte", "kauf",
        "transaktion", "beleg", "quittung", "erfolgreich", "abgeschlossen",
        "bestätigt", "genehmigt",
        // Portuguese and Spanish. `compra` and `compras` are the ones that earn
        // their place: a Google Wallet notice in either language leads with them,
        // and without these a Lisbon household would file a month of payments to
        // a shop called "Compra".
        "compra", "compras", "pagamento", "pago", "pagado", "pagou", "cartão",
        "cartao", "tarjeta", "recibo", "talão", "talao", "transação", "transacao",
        "transacción", "transaccion", "concluído", "concluido", "aprovado",
        "aprobado", "correcto", "realizado", "efetuado", "efectuado",
    )

    /// The joining words a wallet puts between the parts of its sentence. They
    /// are not evidence of anything on their own: "$5.00 with Visa ••1234" leaves
    /// exactly "with" behind once the price and the card are stripped, and a
    /// review drawer offering the user a shop called "with" reads as a bug rather
    /// than as a question. Counted only towards deciding a candidate is *nothing*
    /// — never towards flagging one, or a shop legitimately named "Bei Hans"
    /// would go to review for its first word.
    private val FILLER = setOf(
        "with", "using", "via", "at", "from", "to", "for", "on", "in", "and",
        "mit", "auf", "über", "von", "bei", "für", "am", "um", "per", "und", "an",
        // Portuguese and Spanish. Both contract their prepositions with the
        // article — `no`, `na`, `del`, `al` — so the contracted forms have to be
        // here too or "Pago en el Mercadona" leaves "el" behind as the shop.
        "em", "no", "na", "nos", "nas", "de", "da", "do", "das", "dos", "com",
        "por", "para", "e",
        "en", "el", "la", "los", "las", "del", "al", "con", "y",
    )

    /// A payment that did not happen, or happened backwards. Filing either as a
    /// spend puts a number in the household's month that nobody spent.
    ///
    /// **The notification is written in the phone's language, not the app's**, so
    /// the four Aporah speaks are not enough here. The amount parser already reads
    /// two dozen currencies, which means a Turkish or Polish refund notice prices
    /// itself perfectly and would be filed as a purchase for want of one word.
    /// Bounded on letters rather than tested as substrings, because at four
    /// characters "iade" would otherwise turn up inside somebody's shop name.
    private val NOT_A_PURCHASE = Regex(
        "(?<![\\p{L}])(?:" + listOf(
            "refund", "refunded", "declined", "failed", "reversed", "cancelled", "canceled",
            "rückerstattung", "erstattet", "abgelehnt", "fehlgeschlagen", "storniert",
            "gutschrift", "rückbuchung",
            "remboursement", "refusé", "annulé", "échec",
            "reembolso", "rechazado", "cancelado", "anulado", "devolución",
            "devolucion", "denegado", "fallido", "rechazada",
            "estornado", "estorno", "recusado", "recusada", "devolvido",
            "cancelada", "anulada", "falhou",
            "rimborso", "rifiutato", "annullato",
            "terugbetaling", "geweigerd", "geannuleerd",
            "zwrot", "odrzucono", "anulowano", "nieudana",
            "iade", "reddedildi", "iptal", "başarısız",
            "rambursare", "respins", "anulat",
            "vrácení", "zamítnuto", "zrušeno",
        ).joinToString("|") + ")(?![\\p{L}])",
        RegexOption.IGNORE_CASE,
    )

    /// The prepositions a wallet puts in front of a shop name, in the four
    /// languages Aporah speaks. Anything else falls through to the line-stripping
    /// path below, which does not care what language it is reading.
    ///
    /// `em|no|na|en` are the Portuguese and Spanish forms, and the contracted
    /// ones matter most: a wallet writes "Pagamento no Continente", never
    /// "Pagamento em o Continente". `de` is deliberately **not** here even though
    /// it is a preposition — it joins two halves of a shop's own name ("El Corte
    /// Inglés de Castellana") far more often than it introduces one.
    private val AT_PHRASE = Regex(
        "\\b(?:at|bei|from|von|an|em|no|na|en)\\s+(.{2,60}?)" +
            "(?=\\s+(?:with|mit|using|auf|für|am|um|com|con|mediante)\\b|[,;·•]|\\z)",
        RegexOption.IGNORE_CASE,
    )

    fun isSource(packageName: String): Boolean = packageName in sourcePackages

    /// Null when this notification is not a payment we can price.
    fun parse(title: String?, text: String?, bigText: String?, subText: String?): WalletPayment? {
        val lines = listOfNotNull(title, text, bigText, subText)
            .map { it.replace('\n', ' ').trim() }
            .filter { it.isNotEmpty() }
            .distinct()
        if (lines.isEmpty()) return null

        if (NOT_A_PURCHASE.containsMatchIn(lines.joinToString(" · "))) return null

        val priced = lines.firstNotNullOfOrNull { line -> findAmount(line)?.let { line to it } }
            ?: return null
        val (amountLine, amount) = priced

        val card = lines.firstNotNullOfOrNull { readCard(it) }
        val merchant = readMerchant(lines, amountLine, amount.text, card)

        return WalletPayment(
            merchant = merchant?.name ?: "",
            amountCents = amount.cents,
            currency = amount.currency,
            cardLabel = card,
            needsReview = merchant == null || merchant.inferred,
        )
    }

    // -- the amount -----------------------------------------------------------

    private data class Amount(val cents: Long, val currency: String, val text: String)

    private fun findAmount(line: String): Amount? {
        val match = AMOUNT_LEADING.find(line) ?: AMOUNT_TRAILING.find(line) ?: return null
        val digits = match.groupValues[1]
        val cents = toCents(digits) ?: return null
        // Zero is what Apple's broken trigger sends and what a "card verified"
        // notification prices itself at. Neither is a payment.
        if (cents <= 0L) return null
        return Amount(cents, currencyOf(match.value), match.value)
    }

    /// **How many digits follow the last separator, not which separator it is.**
    ///
    /// "Whichever of `.` and `,` came last is the decimal point" is the obvious
    /// rule and it is wrong on the one case that actually turns up: `1,234` is
    /// twelve hundred and thirty-four in English and in German, because no
    /// currency here has three decimal places. Read as a decimal point it
    /// becomes `1.23`, and a shop that charged twelve hundred euros lands in the
    /// month as one. So a separator with one or two digits after it is a decimal
    /// point and everything else is a thousands separator, which settles
    /// `12,34`, `1.234,56`, `1,234.56`, `1,234` and `1.234` alike.
    private fun toCents(raw: String): Long? {
        // The separators a locale can put between thousands also include a
        // no-break space and a narrow no-break space, which is what a German
        // number formatter actually emits. Written as escapes because neither is
        // distinguishable from an ordinary space in a diff.
        val cleaned = raw.replace("\u00a0", "").replace("\u202f", "").replace(" ", "")
        val lastSeparator = maxOf(cleaned.lastIndexOf(','), cleaned.lastIndexOf('.'))
        val decimals = if (lastSeparator < 0) 0 else cleaned.length - lastSeparator - 1

        val normalised = if (lastSeparator >= 0 && decimals in 1..2) {
            cleaned.substring(0, lastSeparator).filter { it.isDigit() } +
                "." + cleaned.substring(lastSeparator + 1)
        } else {
            cleaned.filter { it.isDigit() }
        }

        val value = normalised.toDoubleOrNull() ?: return null
        if (!value.isFinite()) return null
        return Math.round(Math.abs(value) * 100.0)
    }

    private fun currencyOf(matched: String): String {
        // Before the symbol table, because `R$` contains `$` and the table maps
        // that to USD — a Brazilian wallet would otherwise price every tap in
        // dollars and the household's month would be off by a factor of five.
        // Checked as a pair rather than by adding 'R' to SYMBOL_CODES, which
        // would file any shop with an R in its name as Brazilian.
        if (matched.contains("R$", ignoreCase = true)) return "BRL"
        SYMBOL_CODES.forEach { (symbol, code) -> if (matched.contains(symbol)) return code }
        Regex("\\b(" + CODES + ")\\b").find(matched)?.let { return it.groupValues[1] }
        // The household's own currency, and the only sensible guess: a German
        // family's wallet does not post an unlabelled number in dollars.
        return "EUR"
    }

    // -- the shop -------------------------------------------------------------

    private fun readCard(line: String): String? {
        val match = CARD.find(line) ?: return null
        val brand = match.groupValues[1].trim()
        val digits = match.groupValues[2]
        return if (brand.isNotEmpty() && brand.lowercase() !in GENERIC) {
            "$brand ••$digits"
        } else {
            "••$digits"
        }
    }

    /// A shop name, and whether we actually read it or worked it out.
    private data class Named(val name: String, val inferred: Boolean)

    /// Null means "we could not read it at all", and `inferred` means "this is
    /// the best we could do". Both set `needs_review`; the difference is only
    /// whether the drawer shows the user a name to correct or a blank to fill.
    ///
    /// Three tries, best first — and **the third is a guess by construction**,
    /// so it says so. It keeps whatever survives stripping the price, the card
    /// and the wallet's own words off the priced line, which is a sentence
    /// fragment far more often than it is a shop. Returning that unflagged is how
    /// a payment gets filed to a merchant called "Zahlung erfolgreich", land in
    /// `other` from the SQL classifier, and never surface for anyone to fix.
    private fun readMerchant(
        lines: List<String>,
        amountLine: String,
        amountText: String,
        card: String?,
    ): Named? {
        // 1. The wallet said so in words: "12,34 € bei REWE".
        for (line in lines) {
            AT_PHRASE.find(line)?.let { match ->
                clean(match.groupValues[1], amountText, card)?.let { return it }
            }
        }

        // 2. The title, when it is the shop rather than the app's own name. This
        //    is the shape Google Wallet has posted since it took its
        //    notifications back from Play services.
        lines.firstOrNull()?.let { first ->
            if (first != amountLine || lines.size == 1) {
                clean(first, amountText, card)?.let { return it }
            }
        }

        // 3. Whatever is left of the priced line once the price, the card and the
        //    wallet's own name are taken out of it. Always flagged — see above.
        return clean(amountLine, amountText, card)?.copy(inferred = true)
    }

    private fun clean(candidate: String, amountText: String, card: String?): Named? {
        var value = candidate.replace(amountText, " ")
        value = CARD.replace(value, " ")
        if (card != null) value = value.replace(card, " ")
        value = value.replace(Regex("[·•|]+"), " ")
        value = value.replace(Regex("\\s+"), " ").trim().trim('-', '–', '—', ',', ';', ':', '.')
        if (value.length < 2 || value.length > 60) return null
        // A leftover that is only punctuation and digits is not a shop name.
        if (!value.any { it.isLetter() }) return null

        val words = value.lowercase().split(Regex("[^\\p{L}\\d]+")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return null
        // Every word of it is the wallet talking about itself, or the grammar it
        // said it with. There is no shop name in here to keep, so this is a miss
        // rather than a poor read.
        if (words.all { it in GENERIC || it in FILLER }) return null
        return Named(value, words.any { it in GENERIC })
    }
}
