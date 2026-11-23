#!/usr/bin/env python3
"""Generates the comparison pages, sitemap, robots.txt, llms.txt and manifest for docs/."""
import json, os, datetime
ROOT = os.path.join(os.path.dirname(__file__), "..", "docs")
SITE = "https://itsnicksimpson.github.io/spitball/"
TODAY = datetime.date.today().isoformat()
V = "34"

HEAD = """<!doctype html>
<html lang="en" data-theme="pacific">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<link rel="canonical" href="{url}">
<meta name="robots" content="index, follow, max-image-preview:large">
<meta property="og:type" content="article"><meta property="og:site_name" content="Spitball">
<meta property="og:title" content="{title}"><meta property="og:description" content="{desc}">
<meta property="og:url" content="{url}"><meta property="og:image" content="{site}img/og.png">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="{site}img/og.png">
<link rel="icon" type="image/png" href="{rel}favicon.png"><link rel="apple-touch-icon" href="{rel}apple-touch-icon.png">
<link rel="preload" href="{rel}assets/fonts/InstrumentSerif-Regular.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="{rel}assets/fonts/InstrumentSerif-Italic.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{rel}assets/site.css?v={v}">
<script type="application/ld+json">{ld}</script>
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header class="topnav">
  <a class="home" href="{rel}"><img src="{rel}favicon.png" alt="" width="28" height="28"><span class="script">Spitball</span></a>
  <div class="right"><a class="btn" href="https://github.com/itsnicksimpson/spitball" rel="noopener" style="padding:8px 12px;font-size:12px">★ GitHub</a><a class="pill small" href="{rel}#install">Get it free</a></div>
</header>
<main id="main"><article class="doc">
"""
FOOT = """</article></main>
<footer>
  <div class="wrap">
    <span class="huge script" aria-hidden="true">Spitball</span>
    <p class="serif" style="font-size:28px;margin:0"><em>Say it. Ship it.</em></p>
    <div class="badges"><span class="chip">Free forever</span><span class="chip">Open source · MIT</span><span class="chip">100% on-device</span></div>
    <nav aria-label="Footer"><a href="{rel}">Home</a><a href="{rel}alternatives/">Alternatives</a><a href="{rel}alternatives/wispr-flow/">vs Wispr Flow</a><a href="{rel}alternatives/monologue/">vs Monologue</a><a href="{rel}alternatives/superwhisper/">vs Superwhisper</a><a href="https://github.com/itsnicksimpson/spitball">GitHub</a></nav>
    <p class="small">Spitball is independent and not affiliated with the products compared here. Competitor details come from their public pages and reviews as of November 2026; check their sites for current pricing.</p>
  </div>
</footer>
</body>
</html>
"""

def ld_for(title, desc, url, crumbs, faqs):
    graph = [
        {"@type": "Article", "headline": title, "description": desc, "url": url, "dateModified": TODAY,
         "author": {"@type": "Person", "name": "Nick Simpson", "url": "https://github.com/itsnicksimpson"},
         "about": {"@id": SITE + "#app"}},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": i + 1, "name": n, "item": u} for i, (n, u) in enumerate(crumbs)]},
        {"@type": "SoftwareApplication", "@id": SITE + "#app", "name": "Spitball", "applicationCategory": "ProductivityApplication",
         "operatingSystem": "macOS 26 or later (Apple Silicon)", "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
         "url": SITE, "license": "https://opensource.org/licenses/MIT"},
    ]
    if faqs:
        graph.append({"@type": "FAQPage", "mainEntity": [
            {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs]})
    return json.dumps({"@context": "https://schema.org", "@graph": graph}, ensure_ascii=False)

def table(rows, them):
    head = f'<thead><tr><th scope="col"><span class="sr">Feature</span></th><th scope="col">Spitball</th><th scope="col">{them}</th></tr></thead>'
    body = "".join(f'<tr><th scope="row">{k}</th><td class="us">{a}</td><td>{b}</td></tr>' for k, a, b in rows)
    return f'<div class="table-wrap"><table class="compare"><caption class="sr">Spitball vs {them}</caption>{head}<tbody>{body}</tbody></table></div>'

def faq_html(faqs):
    return '<div class="faq">' + "".join(f"<details><summary>{q}</summary><div><p>{a}</p></div></details>" for q, a in faqs) + "</div>"

PAGES = {
  "wispr-flow": dict(
    name="Wispr Flow",
    title="Free Wispr Flow Alternative for Mac: Spitball (Open Source, On-Device)",
    desc="Spitball is a free, open-source alternative to Wispr Flow for Mac. Same double-tap-and-talk workflow, Command Mode and per-app styles, but 100% on-device with no subscription.",
    h1="The free, on-device <em>Wispr Flow alternative</em> for Mac.",
    tldr="Wispr Flow is a polished, cloud-based dictation app with Pro plans around $12–15 a month. Spitball does the same core job on your Mac for free: double-tap ⌘, talk, and clean text lands in any app. Your voice never leaves your computer.",
    rows=[("Price","Free forever","Free Basic tier; Pro about $15/mo, or $12/mo billed yearly"),
          ("Where speech is processed","On your Mac (NVIDIA Parakeet + Apple Intelligence)","In the cloud; no offline mode"),
          ("Works offline","Yes","No"),("Open source","Yes, MIT","No"),("Account required","No","Yes"),
          ("Edit text by voice","Command Mode, on-device","Command Mode (Pro or trial)"),
          ("Per-app styles","Yes","Yes"),("Dictionary &amp; snippets","Yes","Yes"),
          ("Platforms","Mac","Mac, Windows, iOS")],
    pick_them="You need Windows or iPhone apps, team admin features, or you'd rather pay for a hosted service with sync across devices.",
    pick_us="You're on a Mac, you want it free, and you'd rather your voice, your text and your clipboard never touch a server.",
    faqs=[("Is Spitball really a free Wispr Flow alternative?","Yes. Spitball is MIT-licensed open source with no account and no subscription. It covers Wispr Flow's core Mac workflow: talk anywhere, Command Mode, styles per app, a personal dictionary and snippets."),
          ("Does Wispr Flow work offline?","According to Wispr's own enterprise page and independent reviews, Wispr Flow runs in the cloud and has no offline mode. Spitball runs fully offline once its speech model has downloaded."),
          ("Can I switch from Wispr Flow to Spitball?","Yes. Install Spitball, double-tap ⌘ instead of holding Fn, and add your common names and terms under Words. Your old history stays in Wispr Flow.")]),
  "monologue": dict(
    name="Monologue",
    title="Free Monologue Alternative for Mac: Spitball (Open Source, On-Device)",
    desc="Looking for a free alternative to Monologue? Spitball is open-source Mac dictation: double-tap ⌘, talk, done. On-device transcription, Command Mode, styles per app, no subscription.",
    h1="A free, open-source <em>Monologue alternative.</em>",
    tldr="Monologue from Every is a lovely subscription dictation app for Mac and iPhone, around $10–15 a month. Spitball is the free, open-source take on the same idea for Mac, running entirely on your computer.",
    rows=[("Price","Free forever","Subscription, about $10–15/mo"),
          ("Where speech is processed","On your Mac","Cloud, with an offline local model on Mac"),
          ("Open source","Yes, MIT","No"),("Account required","No","Yes"),
          ("Modes / styles per app","Yes","Yes"),("Edit text by voice","Command Mode","Yes"),
          ("Personal dictionary","Yes","Yes, learns automatically"),
          ("Platforms","Mac","Mac, iOS, with sync")],
    pick_them="You want the same dictation on your iPhone with your dictionary synced, or you like Monologue's automatic vocabulary learning.",
    pick_us="You want a Mac dictation app that's free, open source and private by default, with no account.",
    faqs=[("Is there a free version of Monologue?","Monologue is subscription-based. Spitball is a free, open-source alternative for Mac with a similar double-tap-and-talk workflow."),
          ("Does Spitball have modes like Monologue?","Yes. Spitball's Styles let you pick a tone per app: as spoken, polished, formal, casual or texting, rewritten on-device by Apple Intelligence.")]),
  "superwhisper": dict(
    name="Superwhisper",
    title="Free Superwhisper Alternative for Mac: Spitball (Open Source)",
    desc="Spitball is a free, open-source alternative to Superwhisper for Mac: on-device Parakeet transcription in about 100 ms, Command Mode, per-app styles, no license fee.",
    h1="A simpler, free <em>Superwhisper alternative.</em>",
    tldr="Superwhisper is a powerful local-first dictation app with a free tier, a Pro plan ($8.49/mo) and a $249.99 lifetime license. Spitball keeps the local-first part, drops the price to zero, and keeps things simple: double-tap ⌘ and talk.",
    rows=[("Price","Free forever","Free tier; Pro $8.49/mo, $84.99/yr or $249.99 lifetime"),
          ("Where speech is processed","On your Mac","Local models, optional cloud models"),
          ("Open source","Yes, MIT","No"),("Speech model","NVIDIA Parakeet (Core ML)","Whisper and Parakeet models"),
          ("Custom modes / styles","Styles per app","Custom modes"),("Edit text by voice","Command Mode","Yes"),
          ("Platforms","Mac","Mac, Windows, iOS")],
    pick_them="You want lots of model choices, custom prompt modes, file transcription, or Windows and iPhone.",
    pick_us="You want fast, private dictation that just works with two taps, and you don't want to pay for a license.",
    faqs=[("Is Spitball as private as Superwhisper's local mode?","Yes. Spitball only uses on-device models: NVIDIA Parakeet for speech and Apple Intelligence's on-device model for rewriting. There's no cloud option at all."),
          ("Is Spitball faster than Superwhisper?","Spitball uses Parakeet on the Neural Engine and typically returns a sentence in about 100 ms on Apple Silicon. Speed in Superwhisper depends on which model you pick.")]),
}

def page(slug, p):
    url = f"{SITE}alternatives/{slug}/"
    crumbs = [("Spitball", SITE), ("Alternatives", SITE + "alternatives/"), (f"vs {p['name']}", url)]
    out = HEAD.format(title=p["title"], desc=p["desc"], url=url, site=SITE, rel="../../", v=V,
                      ld=ld_for(p["title"], p["desc"], url, crumbs, p["faqs"]))
    out += f'<nav class="crumbs" aria-label="Breadcrumb"><a href="../../">Spitball</a> / <a href="../">Alternatives</a> / vs {p["name"]}</nav>\n'
    out += f'<span class="label" style="display:block;margin-top:18px">Spitball vs {p["name"]}</span>\n<h1>{p["h1"]}</h1>\n'
    out += f'<div class="tldr"><p><b>TL;DR:</b> {p["tldr"]}</p></div>\n'
    out += f'<h2>Side by side</h2>\n{table(p["rows"], p["name"])}\n<p class="note">As of November 2026, from {p["name"]}\'s public pages and independent reviews.</p>\n'
    out += f'<h2>Which should <em>you</em> pick?</h2>\n<h3>Pick {p["name"]} if…</h3><p>{p["pick_them"]}</p>\n<h3>Pick Spitball if…</h3><p>{p["pick_us"]}</p>\n'
    out += ('<h2>How Spitball works</h2>\n<ol><li><b>Double-tap ⌘.</b> A little island grows out of your notch and starts listening.</li>'
            '<li><b>Talk.</b> NVIDIA Parakeet transcribes on your Mac\'s Neural Engine.</li>'
            '<li><b>Tap ⌘.</b> Clean text pastes at your cursor in about 100 ms, in any app.</li></ol>\n')
    out += f'<h2>Questions</h2>\n{faq_html(p["faqs"])}\n'
    out += '<p style="margin-top:40px;display:flex;gap:14px;flex-wrap:wrap"><a class="pill" href="../../#install">Get Spitball free</a><a class="btn" href="../../#top">Try it in your browser</a></p>\n'
    out += FOOT.format(rel="../../")
    d = os.path.join(ROOT, "alternatives", slug); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "index.html"), "w").write(out)

def hub():
    url = SITE + "alternatives/"
    title = "Best Free Alternatives to Wispr Flow, Monologue & Superwhisper (Mac)"
    desc = "Comparing Mac dictation apps? Spitball is a free, open-source, on-device alternative to Wispr Flow, Monologue and Superwhisper. See honest side-by-side comparisons."
    faqs = [("What is the best free dictation app for Mac?","Spitball is a free, open-source dictation app for Mac that runs entirely on-device. Double-tap ⌘, talk, and text appears in any app in about 100 ms."),
            ("What's the best Wispr Flow alternative?","For Mac users who want it free and private, Spitball. It matches Wispr Flow's core workflow, including Command Mode and per-app styles, without the cloud or the subscription.")]
    out = HEAD.format(title=title, desc=desc, url=url, site=SITE, rel="../", v=V,
                      ld=ld_for(title, desc, url, [("Spitball", SITE), ("Alternatives", url)], faqs))
    out += '<nav class="crumbs" aria-label="Breadcrumb"><a href="../">Spitball</a> / Alternatives</nav>\n'
    out += '<h1>Free alternatives to the <em>big dictation apps.</em></h1>\n'
    out += '<div class="tldr"><p><b>TL;DR:</b> Wispr Flow, Monologue and Superwhisper are all good apps that charge for their best features. Spitball is a free, open-source Mac app that covers the core workflow on-device: double-tap ⌘, talk, done.</p></div>\n'
    out += '<h2>Compare</h2><div class="alts">' + "".join(f'<a class="btn" href="{s}/">Spitball vs {p["name"]} →</a>' for s, p in PAGES.items()) + '</div>\n'
    out += f'<h2>Questions</h2>\n{faq_html(faqs)}\n'
    out += '<p style="margin-top:40px"><a class="pill" href="../#install">Get Spitball free</a></p>\n'
    out += FOOT.format(rel="../")
    os.makedirs(os.path.join(ROOT, "alternatives"), exist_ok=True)
    open(os.path.join(ROOT, "alternatives", "index.html"), "w").write(out)

for s, p in PAGES.items(): page(s, p)
hub()

urls = [SITE, SITE + "alternatives/"] + [f"{SITE}alternatives/{s}/" for s in PAGES]
open(os.path.join(ROOT, "sitemap.xml"), "w").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    "".join(f"  <url><loc>{u}</loc><lastmod>{TODAY}</lastmod></url>\n" for u in urls) + "</urlset>\n")

open(os.path.join(ROOT, "robots.txt"), "w").write(f"""# Everyone's welcome, including AI answer engines.
User-agent: *
Allow: /

User-agent: GPTBot
Allow: /
User-agent: OAI-SearchBot
Allow: /
User-agent: ChatGPT-User
Allow: /
User-agent: ClaudeBot
Allow: /
User-agent: Claude-SearchBot
Allow: /
User-agent: PerplexityBot
Allow: /
User-agent: Google-Extended
Allow: /
User-agent: Applebot-Extended
Allow: /

Sitemap: {SITE}sitemap.xml
""")

open(os.path.join(ROOT, "llms.txt"), "w").write(f"""# Spitball

> Spitball is a free, open-source (MIT) voice dictation app for macOS. Double-tap the Command key, speak, and your words are typed into any app about 100 ms after you stop talking. Speech recognition runs on-device with NVIDIA Parakeet (via FluidAudio and Core ML); optional rewriting uses Apple Intelligence's on-device model. No account, no subscription, audio never leaves the Mac.

Key facts:
- Price: free forever. License: MIT. Source: https://github.com/itsnicksimpson/spitball
- Platform: Apple Silicon Macs on macOS 26 or later. Supports notched MacBooks and Dynamic Island MacBook Pro models.
- How to use: double-tap ⌘ to start, tap ⌘ once to finish, Esc to cancel. Hold-to-talk keys are also available.
- Features: Command Mode (select text, speak an edit), per-app writing styles (as spoken, polished, formal, casual, texting), personal dictionary, voice snippets, searchable history with the app you dictated into, echo and noise cancellation during calls, VoiceOver support.
- Privacy: transcription and rewriting are on-device. An optional, opt-in leaderboard shares only word counts.
- Alternatives it replaces: Wispr Flow (cloud, paid Pro), Monologue (subscription), Superwhisper (paid Pro/lifetime).

## Pages
- [Home]({SITE}): overview, live demo, install
- [Spitball vs Wispr Flow]({SITE}alternatives/wispr-flow/)
- [Spitball vs Monologue]({SITE}alternatives/monologue/)
- [Spitball vs Superwhisper]({SITE}alternatives/superwhisper/)
- [All alternatives]({SITE}alternatives/)
- [README / docs](https://github.com/itsnicksimpson/spitball#readme)
""")

open(os.path.join(ROOT, "site.webmanifest"), "w").write(json.dumps({
    "name": "Spitball", "short_name": "Spitball", "description": "Free, on-device voice dictation for Mac.",
    "start_url": "/spitball/", "scope": "/spitball/", "display": "standalone", "background_color": "#fffbf3", "theme_color": "#66b3f5",
    "icons": [{"src": "img/icon.png", "sizes": "512x512", "type": "image/png"}, {"src": "apple-touch-icon.png", "sizes": "180x180", "type": "image/png"}]}, indent=2))

open(os.path.join(ROOT, "404.html"), "w").write(HEAD.format(title="Lost at sea · Spitball", desc="This page drifted off. Head back to Spitball.", url=SITE + "404.html", site=SITE, rel="/spitball/", v=V, ld="{}") +
    '<h1>This page <em>drifted off.</em></h1><p>Probably floating somewhere near the Bahamas. Let\'s get you back to the beach.</p><p style="margin-top:30px"><a class="pill" href="/spitball/">Back to Spitball</a></p>' + FOOT.format(rel="/spitball/"))
print("built", len(urls), "urls")
