#!/usr/bin/env python3
"""
Inject per-page SEO metadata into <head>, and generate sitemap.xml + robots.txt.

    python3 tools/seo-tags.py            # write
    python3 tools/seo-tags.py --check    # report, touch nothing

Called by tools/apply-responsive-fixes.sh, so a design-tool re-export cannot
quietly drop any of this.

WHAT THE EXPORT SHIPPED
    Nothing. No <meta name="description">, no Open Graph, no Twitter card, no
    structured data, no sitemap — on any of the five pages. A link to the site
    pasted into LinkedIn or Slack rendered as a bare URL with no image and no
    summary, and search results had to fall back to scraped body text.

    <title> and <link rel="canonical"> DID exist, but only because an earlier
    one-off migration added them by hand — nothing re-applied them, so the next
    re-export would have taken them out too. They are emitted here now, which is
    why this script strips any pre-existing copy of both from <head> before
    writing its own block: after a re-export there is none to strip, and on the
    current files there is exactly one, and either way the result is identical.

WHY THE BLOCK IS DELIMITED
    Everything lives between <!-- seo:start --> and <!-- seo:end --> so a re-run
    replaces its own output instead of appending a second copy. That marker is
    the idempotency contract; don't hand-edit inside it.

WHY <head> AND NOT <helmet>
    support.js hoists <style> out of the in-body <helmet> element, but the tags
    here have to be in the served HTML *before* any script runs: link unfurlers
    (LinkedIn, Slack, iMessage, Twitter) do not execute JavaScript at all. Real
    <head>, in the bytes on disk, or it does not work.

    Crawlability was measured, not assumed: the raw HTML ahead of the
    <script type="text/x-dc"> block already carries the <h1> and ~25k characters
    of prose, so search engines index real content without executing anything.
    Only the metadata was missing.

ROBOTS.TXT IS A PARTIAL WIN AND THAT IS WORTH KNOWING
    Crawlers read robots.txt ONLY from the origin root — https://daamndaniel.
    github.io/robots.txt. This is a project site served from /portfolio/, so the
    file written here lands at /portfolio/robots.txt and NO crawler will read it.
    The origin root belongs to a different repo (the daamndaniel.github.io user
    site), which this project does not control.

    It ships anyway because it costs nothing, documents intent, and starts
    working the moment a custom domain is attached. Until then the sitemap has to
    be handed to Google Search Console directly, since robots.txt is its only
    other discovery route.

NO hreflang
    The language toggle swaps copy in place; English and Spanish share one URL.
    hreflang annotations describe *alternate URLs* and would be a lie here, so
    the pages declare og:locale plus og:locale:alternate and stop there.
"""
import html
import os
import re
import subprocess
import sys

SITE = 'https://daamndaniel.github.io/portfolio/'
AUTHOR = 'Daniel Pazmiño'
PERSON_ID = SITE + '#daniel'
LINKEDIN = 'https://www.linkedin.com/in/daniel-pazmi%C3%B1o-c-8a5550158/'
OG_SHARE = 'assets/og-share.jpg'          # 1200x630, built by optimize-assets.sh
START, END = '<!-- seo:start -->', '<!-- seo:end -->'

# Descriptions are written from each page's own copy — the h1, the standfirst,
# the stat row — not invented. They sit in the 120-160 char band that Google
# renders without truncating on desktop.
PAGES = [
    {
        'file': 'index.html',
        'slug': '',
        'title': 'Daniel Pazmiño — Product Designer',
        'og_title': 'Daniel Pazmiño — Product Designer',
        'desc': ('UX/UI designer in Quito, Ecuador. 4+ years turning complex ideas into '
                 'clear, human experiences — currently 0→1 on an AI platform for judged sports.'),
        'image': OG_SHARE,
        'image_alt': 'Daniel Pazmiño',
        'dims': (1200, 630),
        'kind': 'person',
    },
    {
        'file': 'about.html',
        'slug': 'about',
        'title': 'About — Daniel Pazmiño',
        'og_title': 'About Daniel Pazmiño',
        'desc': ('From multimedia to product design: six years of work, the tools I reach '
                 'for, and what I make away from a screen. Based in Quito, Ecuador.'),
        'image': OG_SHARE,
        'image_alt': 'Daniel Pazmiño',
        'dims': (1200, 630),
        'kind': 'person',
    },
    {
        'file': 'sales-landing-cro.html',
        'slug': 'sales-landing-cro',
        'title': 'Sales Landing CRO — Daniel Pazmiño',
        'og_title': 'Turning high-intent traffic into completed sales conversations',
        'desc': ('A conversion-rate case study: redesigning a high-traffic sales landing '
                 'page into a low-friction, confidence-building path to sign-up.'),
        'image': 'assets/cro-cover.jpg',
        'image_alt': 'Redesigned contact sales landing page',
        'dims': (2560, 1440),
        'kind': 'work',
    },
    {
        'file': 'stack-builders-website.html',
        'slug': 'stack-builders-website',
        'title': 'Stack Builders Website — Daniel Pazmiño',
        'og_title': 'Turning a company website into a stronger first conversation',
        'desc': ('A website strategy and redesign case study: making an outdated company '
                 'site into a clear, credible first conversation. Now in implementation.'),
        'image': 'assets/sb-cover.jpg',
        'image_alt': 'Redesigned Stack Builders homepage',
        'dims': (2560, 1440),
        'kind': 'work',
    },
    {
        'file': 'judged-sports-platform.html',
        'slug': 'judged-sports-platform',
        'title': 'Judged Sports Platform — Daniel Pazmiño',
        'og_title': 'Building the foundation for a new era of judged sports',
        'desc': ('A 0→1 case study: leading brand, product, and design system for XGrab, '
                 'an AI platform bringing clarity to judged sports.'),
        'image': 'assets/xg-cover.jpg',
        'image_alt': 'XGrab brand and product direction',
        'dims': (2560, 1440),
        'kind': 'work',
    },
]


def esc(s):
    """Escape for an HTML attribute value."""
    return html.escape(s, quote=True)


def person_jsonld():
    return {
        '@type': 'Person',
        '@id': PERSON_ID,
        'name': AUTHOR,
        'jobTitle': 'Product Designer',
        'url': SITE,
        'image': SITE + OG_SHARE,
        'sameAs': [LINKEDIN],
        'address': {'@type': 'PostalAddress',
                    'addressLocality': 'Quito', 'addressCountry': 'EC'},
        'knowsAbout': ['UX Design', 'UI Design', 'Design Systems',
                       'UX Research', 'Conversion Rate Optimization'],
    }


def jsonld_for(p):
    if p['kind'] == 'person':
        graph = [person_jsonld()]
        if p['slug'] == '':
            graph.append({'@type': 'WebSite', 'url': SITE,
                          'name': AUTHOR + ' — Portfolio',
                          'inLanguage': ['en', 'es'],
                          'author': {'@id': PERSON_ID}})
        else:
            graph.append({'@type': 'ProfilePage', 'url': SITE + p['slug'],
                          'name': p['og_title'], 'mainEntity': {'@id': PERSON_ID}})
    else:
        graph = [{
            '@type': 'CreativeWork',
            'name': p['og_title'],
            'headline': p['og_title'],
            'description': p['desc'],
            'url': SITE + p['slug'],
            'image': SITE + p['image'],
            'inLanguage': ['en', 'es'],
            'author': {'@id': PERSON_ID},
            'creator': {'@id': PERSON_ID},
        }, person_jsonld()]

    # Hand-rolled so the output is stable and diff-friendly. No user input reaches
    # this, but </script> in a value would still break out of the script element,
    # so the one escape that matters is applied below.
    def enc(v, ind):
        pad = '  ' * ind
        if isinstance(v, dict):
            items = ',\n'.join('%s  "%s": %s' % (pad, k, enc(x, ind + 1))
                               for k, x in v.items())
            return '{\n%s\n%s}' % (items, pad)
        if isinstance(v, list):
            items = ',\n'.join('%s  %s' % (pad, enc(x, ind + 1)) for x in v)
            return '[\n%s\n%s]' % (items, pad)
        return '"%s"' % str(v).replace('\\', '\\\\').replace('"', '\\"')

    body = enc({'@context': 'https://schema.org', '@graph': graph}, 0)
    return body.replace('</', '<\\/')


def block_for(p):
    url = SITE + p['slug']
    canon = './' if p['slug'] == '' else p['slug']
    L = [START]
    L.append('<title>%s</title>' % esc(p['title']))
    L.append('<meta name="description" content="%s">' % esc(p['desc']))
    L.append('<link rel="canonical" href="%s">' % esc(canon))
    L.append('<meta name="author" content="%s">' % esc(AUTHOR))
    L.append('<meta name="robots" content="index, follow, max-image-preview:large">')
    L.append('<meta name="theme-color" content="#F2F1EC" media="(prefers-color-scheme: light)">')
    L.append('<meta name="theme-color" content="#14130E" media="(prefers-color-scheme: dark)">')
    L.append('<meta property="og:type" content="%s">'
             % ('website' if p['kind'] == 'person' else 'article'))
    L.append('<meta property="og:site_name" content="%s">' % esc(AUTHOR))
    L.append('<meta property="og:title" content="%s">' % esc(p['og_title']))
    L.append('<meta property="og:description" content="%s">' % esc(p['desc']))
    L.append('<meta property="og:url" content="%s">' % esc(url))
    L.append('<meta property="og:image" content="%s">' % esc(SITE + p['image']))
    L.append('<meta property="og:image:width" content="%d">' % p['dims'][0])
    L.append('<meta property="og:image:height" content="%d">' % p['dims'][1])
    L.append('<meta property="og:image:alt" content="%s">' % esc(p['image_alt']))
    L.append('<meta property="og:locale" content="en_US">')
    L.append('<meta property="og:locale:alternate" content="es_ES">')
    L.append('<meta name="twitter:card" content="summary_large_image">')
    L.append('<meta name="twitter:title" content="%s">' % esc(p['og_title']))
    L.append('<meta name="twitter:description" content="%s">' % esc(p['desc']))
    L.append('<meta name="twitter:image" content="%s">' % esc(SITE + p['image']))
    L.append('<meta name="twitter:image:alt" content="%s">' % esc(p['image_alt']))
    L.append('<script type="application/ld+json">%s</script>' % jsonld_for(p))
    L.append(END)
    return '\n'.join(L)


def patch_head(path, p):
    """Replace the delimited block in <head>, or insert it after the viewport meta.

    Everything is done on a slice bounded by the FIRST </head>: the word 'title'
    and stray <link> tags also appear far below inside the page's JSX template,
    and a document-wide regex would happily corrupt them.
    """
    src = open(path, encoding='utf-8').read()
    hs, he = src.find('<head>'), src.find('</head>')
    if hs < 0 or he < 0 or he < hs:
        raise SystemExit('FAIL %s: no usable <head>' % path)
    head, rest = src[hs:he], src[he:]

    head = re.sub(re.escape(START) + r'.*?' + re.escape(END), '', head, flags=re.S)
    head = re.sub(r'[ \t]*<title>.*?</title>\n?', '', head, flags=re.S)
    head = re.sub(r'[ \t]*<link[^>]*rel="canonical"[^>]*>\n?', '', head)
    head = re.sub(r'\n{3,}', '\n\n', head)

    anchor = re.search(r'<meta name="viewport"[^>]*>', head)
    if not anchor:
        raise SystemExit('FAIL %s: no viewport meta to anchor to' % path)
    at = anchor.end()
    head = head[:at] + '\n' + block_for(p) + head[at:]
    return src[:hs] + head + rest


def git_date(path):
    try:
        out = subprocess.run(['git', 'log', '-1', '--format=%cs', '--', path],
                             capture_output=True, text=True, timeout=10)
        d = out.stdout.strip()
        return d if re.fullmatch(r'\d{4}-\d{2}-\d{2}', d) else None
    except Exception:
        return None


def sitemap():
    L = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for p in PAGES:
        L.append('  <url>')
        L.append('    <loc>%s</loc>' % (SITE + p['slug']))
        d = git_date(p['file'])
        if d:
            L.append('    <lastmod>%s</lastmod>' % d)
        L.append('    <priority>%s</priority>' % ('1.0' if p['slug'] == '' else '0.8'))
        L.append('  </url>')
    L.append('</urlset>')
    return '\n'.join(L) + '\n'


def robots():
    return ('\n'.join([
        '# Served at /portfolio/robots.txt, which crawlers do NOT read — they only',
        '# fetch robots.txt from the origin root. Kept so intent is explicit and so',
        '# it starts working the moment a custom domain is attached. Until then the',
        '# sitemap must be submitted to Google Search Console by hand.',
        'User-agent: *',
        'Allow: /',
        '',
        'Sitemap: %ssitemap.xml' % SITE,
    ]) + '\n')


def main():
    check = '--check' in sys.argv
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

    if not os.path.exists(OG_SHARE):
        print('  WARN %s missing — run tools/optimize-assets.sh first' % OG_SHARE)

    changed = same = 0
    for p in PAGES:
        out = patch_head(p['file'], p)
        cur = open(p['file'], encoding='utf-8').read()
        if out == cur:
            same += 1
            print('  ok   %-30s already tagged' % p['file'])
        else:
            changed += 1
            print('  %-4s %-30s %s' % ('WOULD' if check else 'seo', p['file'],
                                       '%d meta tags + JSON-LD' % out[out.find(START):
                                                                     out.find(END)].count('<meta')))
            if not check:
                open(p['file'], 'w', encoding='utf-8').write(out)

    for name, text in (('sitemap.xml', sitemap()), ('robots.txt', robots())):
        cur = open(name, encoding='utf-8').read() if os.path.exists(name) else None
        if cur == text:
            print('  ok   %-30s unchanged' % name)
        else:
            print('  %-4s %-30s %s' % ('WOULD' if check else 'gen', name,
                                       'created' if cur is None else 'updated'))
            if not check:
                open(name, 'w', encoding='utf-8').write(text)

    print('  pages tagged=%d unchanged=%d' % (changed, same))


if __name__ == '__main__':
    main()
