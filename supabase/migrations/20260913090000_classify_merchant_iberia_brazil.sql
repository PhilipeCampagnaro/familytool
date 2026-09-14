-- Teach `private.classify_merchant` the Brazilian, Spanish and Portuguese high street.
--
-- **Why this is not cosmetic.** The ring chart *is* Ausgaben: without a category
-- every payment lands in `other` and the whole screen is one grey circle. The
-- classifier shipped knowing REWE, dm and Aral, so a household in São Paulo,
-- Madrid or Lisbon would have seen exactly that — a feature that technically
-- worked and told them nothing.
--
-- **Still one copy of the rules, still in SQL.** The reason the classifier lives
-- here rather than in Dart has not changed: `spend-ingest` and the app's own
-- form both write spends, and two copies of these rules would drift into putting
-- one shop in two slices of the same ring. Adding a country is adding names to
-- the one list, never a second list beside it.
--
-- **No country column, and deliberately not.** A German family on holiday in the
-- Algarve buys petrol at a Galp, and a Portuguese household orders from Amazon;
-- the chains are matched regardless of where the household says it lives, which
-- is both simpler and more often right than asking. The cost is a name that
-- means different things in two countries, which is why every short or ambiguous
-- token below is anchored with `\y…\y`.
--
-- Ordering still matters — first match wins — so the department stores sit in
-- `shopping` while their own supermarket brands (Hipercor, Supercor) sit in
-- `groceries` above them.
create or replace function private.classify_merchant(p_merchant text)
returns public.spend_category
language sql
immutable
set search_path = ''
as $$
  select case
    when p_merchant is null or trim(p_merchant) = '' then 'other'::public.spend_category

    -- Groceries. `\ydia\y` and `\yextra\y` are the two genuinely risky tokens in
    -- this function: DIA (Spain) and Extra (Brazil) are both too big to leave
    -- out, and both words are ordinary vocabulary in their own language. The
    -- word anchors hold them to a standalone token, and a wrong guess is a
    -- category the user can change — which is the whole contract of
    -- `classify_merchant`, a starting guess and not a verdict. `\yposto\y` in
    -- the fuel branch is the same bargain: in Brazil a merchant called "Posto
    -- …" is a filling station essentially every time.
    --
    -- Brazil's own wallet gap is worth stating here rather than discovering
    -- later: **Pix is not a card tap and posts no wallet notification**, so a
    -- large share of Brazilian household spending never reaches this function
    -- at all and is entered by hand. That is a limit of the capture mechanism,
    -- not of these rules.
    when p_merchant ~* '^(rewe|lidl|aldi|edeka|netto|penny|kaufland|tegut|globus|metro|billa|norma)'
      or p_merchant ~* '(marktkauf|supermarkt|lebensmittel|inkoop)'
      or p_merchant ~* '(mercadona|carrefour|alcampo|consum|eroski|ahorramas|caprabo|supercor|hipercor|condis|gadis|froiz|coviran|bonarea|simply)'
      or p_merchant ~* '(continente|pingo.?doce|minipreco|mini.?preço|intermarch|auchan|jumbo|recheio|meu.?super|amanhecer|supermercado|mercearia)'
      or p_merchant ~* '(pao.?de.?acucar|pão.?de.?açúcar|assai|assaí|atacadao|atacadão|hortifruti|zona.?sul|prezunic|guanabara|angeloni|zaffari|condor|sonda|sendas|st.?marche)'
      or p_merchant ~* '\y(spar|hit|dia|extra|tenda|oxxo)\y'      then 'groceries'

    when p_merchant ~* '(rossmann|budni|m.ller|mueller)'
      or p_merchant ~* '(primor|druni|perfumer|drogaria|droguer|wells)'
      or p_merchant ~* '(drogasil|droga.?raia|pacheco|pague.?menos|extrafarma|panvel|nissei|araujo|araújo|venancio|venâncio)'
      or p_merchant ~* '\y(dm|pens|raia)\y'                      then 'drugstore'

    when p_merchant ~* '(tankstelle|benzin|tanken)'
      or p_merchant ~* '(repsol|cepsa|petronor|ballenoil|galp|prio|gasolinera|combustivel|combustível)'
      or p_merchant ~* '(ipiranga|petrobras|texaco)'
      or p_merchant ~* '\y(aral|total|shell|esso|bp|q1|jet|agip|posto)\y' then 'fuel'

    when p_merchant ~* '(mcdonald|burger.?king|subway|pizza|d.ner|kebab|sushi|restaurant|bistro|imbiss|lieferando|wolt|uber.?eat|domino)'
      or p_merchant ~* '(telepizza|goiko|rodilla|montaditos|foster|glovo|just.?eat|bolt.?food|restaurante|tasca|churrasqueira|marisqueira|cerveceria|cervecer)'
      or p_merchant ~* '(ifood|rappi|habib|giraffas|outback|madero|spoleto|china.?in.?box|churrascaria|lanchonete|hamburgueria)'
      or p_merchant ~* '\ybob.?s\y'
      or p_merchant ~* '\y(vips|kfc|h3)\y'                       then 'restaurant'

    when p_merchant ~* '(starbucks|mccafe|backwerk|b.cker|konditorei|cafe|kaffee)'
      or p_merchant ~* '(padaria|pastelaria|confeitaria|panader|pasteler|granier|santagloria|dunkin)'
      or p_merchant ~* '(pao.?de.?queijo|pão.?de.?queijo|kopenhagen|cacau.?show|doceria)'
      or p_merchant ~* '\ycaf[eé]'                                then 'cafe'

    when p_merchant ~* '(hermes|deutsche.?post)'
      or p_merchant ~* '(correos|correios|chronopost|celeritas|nacex|jadlog|braspress|total.?express|mercado.?envios)'
      or p_merchant ~* '\y(dhl|ups|gls|fedex|dpd|ctt|seur|mrw|loggi)\y' then 'shipping'

    when p_merchant ~* '(primark|about.?you|bonprix|shein|uniqlo|peek.und.cloppenburg|takko|new.?yorker|vero.?moda|jack.?jones|s\.oliver|ernsting)'
      or p_merchant ~* '(bershka|stradivarius|pull.?(and|&).?bear|massimo.?dutti|springfield|cortefiel|lefties|desigual|decathlon|salsa|throttleman|decenio)'
      or p_merchant ~* '(renner|riachuelo|pernambucanas|havaianas|centauro|marisa|hering)'
      or p_merchant ~* '\y(zara|h&m|hm|c&a|p&c|kik|mango|oysho)\y' then 'clothing'

    -- Department stores and marketplaces. Below groceries on purpose: Hipercor
    -- and Supercor are El Corte Inglés's supermarkets and have already matched.
    when p_merchant ~* '(amazon|zalando|temu)'
      or p_merchant ~* '(corte.?ingl|aliexpress|wallapop|vinted)'
      or p_merchant ~* '(mercado.?livre|magazine.?luiza|magalu|americanas|submarino|shopee)'
      or p_merchant ~* '\y(otto|ebay)\y'                         then 'shopping'

    when p_merchant ~* '(saturn|media.?markt|cyberport|notebooksb)'
      or p_merchant ~* '(pccomponentes|worten|r.dio.?popular|radio.?popular)'
      or p_merchant ~* '(casas.?bahia|ponto.?frio|kabum|fast.?shop)'
      or p_merchant ~* '\y(dyson|fnac)\y'                        then 'electronics'

    when p_merchant ~* '(deutsche.?bahn|flixbus|ryanair|lufthansa|easyjet)'
      or p_merchant ~* '(renfe|alsa|cabify|comboios|carris|vueling|iberia|tap.?air|parquimetro|parqu.metro|estacionamento|aparcamiento)'
      or p_merchant ~* '(latam|localiza|movida|bilhete.?unico|bilhete.?único|metr[oô])'
      or p_merchant ~* '\y(db|bvg|mvg|mvv|uber|lyft|taxi|emt|tmb|via.?verde|cptm)\y' then 'transport'

    when p_merchant ~* '(netflix|spotify|disney|kino|cinema|theater|dazn|prime.?video|apple.?tv)'
      or p_merchant ~* '(filmin|cines|cinemas|movistar|teatro)'
      or p_merchant ~* '(globoplay|cinemark|kinoplex|ingresso\.com)'
      or p_merchant ~* '\y(steam|sky|meo|uci)\y'                 then 'entertainment'

    when p_merchant ~* '(apotheke|pharmacy|zahnarzt|optiker|doctolib|gesundheit)'
      or p_merchant ~* '(farmacia|farm.cia|clinica|cl.nica|dentista|hospital|laborat)'
      or p_merchant ~* '(unimed|hapvida|amil|fleury|sabin)'        then 'health'

    when p_merchant ~* '(h.ffner|segm.ller|wayfair|home24|westwing|m.max)'
      or p_merchant ~* '(leroy.?merlin|bricomart|bricodepot|brico.?dep|conforama|maisons.?du.?monde|ferreteria|ferreter|maxmat)'
      or p_merchant ~* '(telhanorte|tok.?stok|camicado|obramax|material.?de.?constru)'
      or p_merchant ~* '\y(ikea|roller|poco|xxxl|porta|bauhaus|aki)\y' then 'home'

    else 'other'
  end;
$$;

-- Unchanged from the original grant, and restated because `create or replace`
-- keeps the old ACL only for a function it actually replaced in place. `private`
-- is what keeps this off the API; the revoke is not what was protecting it.
revoke all on function private.classify_merchant(text) from public, anon;
grant execute on function private.classify_merchant(text) to authenticated;
