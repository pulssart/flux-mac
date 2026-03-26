// AdKeywordFilter.swift
// Filtre les articles publicitaires et promotionnels par mots-clés multilingues.

import Foundation

/// Détecte les articles publicitaires/promotionnels en cherchant des mots-clés
/// dans le titre et le contenu texte de l'article.
enum AdKeywordFilter {

    // MARK: - API publique

    /// Retourne `true` si le titre de l'article contient des mots-clés publicitaires/promotionnels.
    static func isAd(_ article: Article) -> Bool {
        let title = article.title.lowercased()
        return adKeywords.contains { title.contains($0) }
    }

    // MARK: - Liste de mots-clés (toutes langues)

    /// Mots-clés en minuscules, triés par langue puis par pertinence.
    /// On cherche des sous-chaînes pour attraper les déclinaisons.
    private static let adKeywords: [String] = {
        var kw: [String] = []

        // ── Français ──
        kw += [
            "sponsorisé", "contenu sponsorisé", "article sponsorisé",
            "en partenariat avec", "partenariat commercial",
            "publi-rédactionnel", "publirédactionnel", "publi-communiqué",
            "contenu promotionnel", "offre promotionnelle",
            "offre spéciale", "offre exclusive", "offre limitée",
            "bon plan", "code promo", "code de réduction",
            "réduction exclusive", "profitez de", "bénéficiez de",
            "jusqu'à -", "jusqu'à %", "% de réduction",
            "achetez maintenant", "acheter maintenant",
            "commander maintenant", "commandez maintenant",
            "essai gratuit", "essayez gratuitement",
            "livraison gratuite", "frais de port offerts",
            "lien affilié", "liens affiliés",
            "publicité", "[pub]", "(pub)", "– pub –",
            "annonce payée", "annonce commerciale",
            "idée cadeau", "guide d'achat",
            "meilleur prix", "prix cassé", "vente flash",
            "black friday", "cyber monday", "soldes",
            "comparatif achat",
            "petit prix", "à prix", "meilleurs prix",
            "promotion", "promo", "bonne affaire", "bonnes affaires",
            "aliexpress", "cdiscount",
        ]

        // ── English ──
        kw += [
            "sponsored", "sponsored content", "sponsored post",
            "paid partnership", "in partnership with",
            "advertorial", "paid promotion", "promoted content",
            "special offer", "exclusive offer", "limited time offer",
            "limited offer", "deal of the day", "deal alert",
            "promo code", "discount code", "coupon code",
            "exclusive discount", "% off", "% discount",
            "save up to", "up to % off",
            "buy now", "shop now", "order now", "get it now",
            "free trial", "try for free", "start free trial",
            "free shipping", "free delivery",
            "affiliate link", "affiliate links",
            "advertisement", "[ad]", "(ad)", "– ad –",
            "paid post", "paid content",
            "gift guide", "buying guide",
            "best deals", "flash sale", "clearance sale",
            "black friday", "cyber monday",
            "as low as", "starting at $",
            "use code", "apply code",
            "low price", "best price", "bargain", "great deal",
            "promotion", "promo",
            "aliexpress", "cdiscount",
        ]

        // ── Español ──
        kw += [
            "patrocinado", "contenido patrocinado", "artículo patrocinado",
            "en colaboración con", "colaboración comercial",
            "publi-reportaje", "publireportaje",
            "contenido promocional", "oferta promocional",
            "oferta especial", "oferta exclusiva", "oferta limitada",
            "código promocional", "código de descuento",
            "descuento exclusivo", "% de descuento",
            "aprovecha", "aprovéchate",
            "compra ahora", "comprar ahora", "pide ahora",
            "prueba gratuita", "prueba gratis",
            "envío gratuito", "envío gratis",
            "enlace de afiliado", "enlaces de afiliados",
            "publicidad", "[anuncio]", "(anuncio)",
            "anuncio pagado", "guía de compra",
            "mejor precio", "venta flash",
            "black friday", "cyber monday", "rebajas",
            "precio", "promoción", "promo", "ganga", "chollo",
            "aliexpress", "cdiscount",
        ]

        // ── Deutsch ──
        kw += [
            "gesponsert", "gesponserter inhalt", "gesponserter beitrag",
            "bezahlte partnerschaft", "in zusammenarbeit mit",
            "anzeige", "werbung", "[anzeige]", "(anzeige)",
            "advertorial", "bezahlter beitrag", "bezahlte werbung",
            "sonderangebot", "exklusives angebot", "begrenztes angebot",
            "aktionscode", "rabattcode", "gutscheincode",
            "exklusiver rabatt", "% rabatt",
            "jetzt kaufen", "jetzt bestellen", "jetzt shoppen",
            "kostenlose testversion", "gratis testen",
            "kostenloser versand", "gratis versand",
            "affiliate-link", "affiliate-links",
            "kaufberatung", "geschenkideen",
            "bester preis", "flash-sale",
            "black friday", "cyber monday", "schlussverkauf",
            "preis", "aktion", "schnäppchen",
            "aliexpress", "cdiscount",
        ]

        // ── Italiano ──
        kw += [
            "sponsorizzato", "contenuto sponsorizzato", "articolo sponsorizzato",
            "in collaborazione con", "collaborazione commerciale",
            "publiredazionale", "contenuto promozionale",
            "offerta speciale", "offerta esclusiva", "offerta limitata",
            "codice promozionale", "codice sconto",
            "sconto esclusivo", "% di sconto",
            "approfitta", "approfittane",
            "acquista ora", "compra ora", "ordina ora",
            "prova gratuita", "provalo gratis",
            "spedizione gratuita", "consegna gratuita",
            "link affiliato", "link affiliati",
            "pubblicità", "[annuncio]", "(annuncio)",
            "annuncio a pagamento", "guida all'acquisto",
            "miglior prezzo", "vendita flash",
            "black friday", "cyber monday", "saldi",
            "prezzo", "promozione", "promo", "affare", "occasione",
            "aliexpress", "cdiscount",
        ]

        // ── Português ──
        kw += [
            "patrocinado", "conteúdo patrocinado", "artigo patrocinado",
            "em parceria com", "parceria comercial",
            "publi-editorial", "publieditorial",
            "conteúdo promocional", "oferta promocional",
            "oferta especial", "oferta exclusiva", "oferta limitada",
            "código promocional", "código de desconto", "cupom de desconto",
            "desconto exclusivo", "% de desconto",
            "aproveite", "não perca",
            "compre agora", "comprar agora", "peça agora",
            "teste gratuito", "teste grátis", "experimente grátis",
            "frete grátis", "entrega gratuita",
            "link de afiliado", "links de afiliados",
            "publicidade", "[anúncio]", "(anúncio)",
            "anúncio pago", "guia de compra",
            "melhor preço", "venda relâmpago",
            "black friday", "cyber monday", "liquidação",
            "preço", "promoção", "promo", "pechincha", "negócio",
            "aliexpress", "cdiscount",
        ]

        // ── 日本語 (Japonais) ──
        kw += [
            "広告", "pr", "【pr】", "【広告】", "(広告)",
            "スポンサード", "スポンサー記事", "タイアップ",
            "プロモーション", "提供", "協賛",
            "アフィリエイト", "アフィリエイトリンク",
            "期間限定", "特別価格", "特別オファー",
            "限定オファー", "お得な", "割引",
            "クーポンコード", "プロモコード", "割引コード",
            "今すぐ購入", "今すぐ注文", "購入はこちら",
            "無料トライアル", "無料お試し", "無料体験",
            "送料無料",
            "セール", "フラッシュセール", "タイムセール",
            "ブラックフライデー", "サイバーマンデー",
            "おすすめ商品", "購入ガイド",
            "価格", "激安", "お買い得", "特価",
            "aliexpress",
        ]

        // ── 中文 (Chinois) ──
        kw += [
            "广告", "推广", "赞助内容", "赞助文章",
            "商业合作", "品牌合作", "付费推广",
            "促销", "优惠活动", "限时优惠", "限时特价",
            "特别优惠", "独家优惠", "独家折扣",
            "优惠码", "折扣码", "促销代码", "优惠券",
            "立即购买", "马上购买", "立即下单",
            "免费试用", "免费体验",
            "包邮", "免运费",
            "联盟链接", "推荐链接",
            "购买指南", "选购指南",
            "最低价", "闪购", "秒杀",
            "黑色星期五", "双十一", "双十二",
            "价格", "特惠", "划算", "便宜",
            "aliexpress", "速卖通",
        ]

        // ── 한국어 (Coréen) ──
        kw += [
            "광고", "스폰서", "스폰서드", "협찬",
            "제휴 콘텐츠", "브랜드 협업",
            "프로모션", "홍보", "유료 광고",
            "특별 할인", "한정 할인", "독점 할인",
            "할인 코드", "프로모 코드", "쿠폰 코드",
            "지금 구매", "바로 구매", "지금 주문",
            "무료 체험", "무료 배송",
            "제휴 링크", "어필리에이트",
            "구매 가이드", "추천 상품",
            "최저가", "플래시 세일", "타임 세일",
            "블랙프라이데이", "사이버먼데이",
            "가격", "특가", "알뜰", "거래",
            "aliexpress", "알리익스프레스",
        ]

        // ── Русский (Russe) ──
        kw += [
            "реклама", "спонсировано", "спонсорский контент",
            "партнёрский материал", "на правах рекламы",
            "промо", "промоакция", "рекламная акция",
            "специальное предложение", "эксклюзивное предложение",
            "ограниченное предложение", "скидка",
            "промокод", "код скидки", "купон",
            "эксклюзивная скидка", "% скидка",
            "купить сейчас", "заказать сейчас",
            "бесплатная пробная версия", "попробуйте бесплатно",
            "бесплатная доставка",
            "партнёрская ссылка", "аффилиатная ссылка",
            "руководство по покупке",
            "лучшая цена", "флеш-распродажа",
            "чёрная пятница", "киберпонедельник", "распродажа",
            "цена", "акция", "выгода", "сделка",
            "aliexpress",
        ]

        return kw
    }()
}
