"""Papyr brand assets from the mark geometry (spec section 8, appendix A).

Run from the repo root: python3 -I tool/brand.py [--logo /path/to/logo.jpeg]
--logo rebuilds assets/brand/wordmark.png; without it the existing one is read.
Previews go to build/brand/ (git-ignored).
"""
import argparse
import base64
import io
import shutil
import subprocess
import tempfile
from math import copysign, cos, erf, hypot, pi, sin, sqrt
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android/app/src/main/res'
WORDMARK = ROOT / 'assets/brand/wordmark.png'
PREVIEW = ROOT / 'build/brand'

NAVY, SKY, GREEN, PAPER, SHADE = '#102E50', '#32B0FA', '#00FD9A', '#F6F3EC', '#EEF1F8'
CENTER = (1024, 829)
WIDTH = 977  # outer width of the frame corners

BRACKETS = ('M552,506 V399 Q552,347 604,347 H711 '
            'M1336,347 H1443 Q1495,347 1495,399 V506 '
            'M1495,1152 V1259 Q1495,1311 1443,1311 H1336 '
            'M711,1311 H604 Q552,1311 552,1259 V1152')
SHADOW = 'M600,1145 C820,1180 1080,1110 1310,955 L1400,1400 L560,1400 Z'
LINE = 'M553,851 H1495'
LINE_Y, LINE_X0, LINE_X1 = 851, 553, 1495

# The glow is the line at stroke 90, opacity 0.7, blurred with deviation 26. VectorDrawable
# has no blur, so it gets the blurred capsule's own cross-section as gradient stops: a band
# with a vertical linear gradient along the line and a radial half disc at each end.
# ponytail: the band/half-disc joints leave a ~1 px antialiasing seam (about 6% darker),
# invisible at real size; a single-path glow needs a blur, which VectorDrawable lacks.
GLOW_REACH, GLOW_STOPS = 110, 6


def glow_alpha(d):
    """Alpha at distance d from the line's axis: a 90-wide stroke at 0.7 blurred by 26."""
    def phi(z):
        return (1 + erf(z / sqrt(2))) / 2
    return 0.7 * (phi((45 - d) / 26) - phi((-45 - d) / 26))


GLOW = [(k / GLOW_STOPS, f'#{round(255 * glow_alpha(k / GLOW_STOPS * GLOW_REACH)):02X}00FD9A')
        for k in range(GLOW_STOPS)] + [(1, '#0000FD9A')]


def num(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def rounded(pts, r):
    """Closed polygon with each corner cut r units back and joined by a quadratic."""
    def toward(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        k = r / hypot(dx, dy)
        return f'{num(a[0] + dx * k)},{num(a[1] + dy * k)}'
    d = []
    for i, v in enumerate(pts):
        prev, nxt = pts[i - 1], pts[(i + 1) % len(pts)]
        d.append(f"{'L' if d else 'M'}{toward(v, prev)} Q{v[0]},{v[1]} {toward(v, nxt)}")
    return ' '.join(d) + ' Z'


def circle(cx, cy, r):
    return f'M{num(cx - r)},{num(cy)} a{num(r)},{num(r)} 0 1,0 {num(2 * r)},0 a{num(r)},{num(r)} 0 1,0 {num(-2 * r)},0 Z'


def squircle(cx, cy, r, n=4):
    pts = ((cos(t), sin(t)) for t in (i * pi / 180 for i in range(360)))
    return 'M' + ' L'.join(f'{num(cx + r * copysign(abs(c) ** (2 / n), c))},'
                           f'{num(cy + r * copysign(abs(s) ** (2 / n), s))}' for c, s in pts) + ' Z'


SHEET = rounded([(850, 405), (1262, 490), (1375, 645), (1225, 1270), (660, 1150)], 22)
FOLD = rounded([(1262, 490), (1240, 622), (1375, 645)], 12)


def layers(glow, mono=False):
    """Draw order from appendix A as dicts; glow is 'blur', 'gradient' or None."""
    def stroke(d, color, width):
        return {'d': d, 'stroke': '#000000' if mono else color, 'width': width}
    if mono:
        return [stroke(BRACKETS, SKY, 34), stroke(SHEET, NAVY, 26),
                stroke(FOLD, NAVY, 26), stroke(LINE, GREEN, 34)]
    out = [stroke(BRACKETS, SKY, 34), {'d': SHEET, 'fill': '#FFFFFF'},
           {'d': SHADOW, 'fill': SHADE, 'clip': SHEET}, {'d': FOLD, 'fill': '#FFFFFF'},
           stroke(SHEET, NAVY, 26), stroke(FOLD, NAVY, 26)]
    if glow == 'blur':
        out.append(stroke(LINE, GREEN, 90) | {'opacity': 0.7, 'blur': 26})
    elif glow == 'gradient':
        x0, x1, y, h = LINE_X0, LINE_X1, LINE_Y, GLOW_REACH
        across = [(0.5 - o / 2, c) for o, c in reversed(GLOW)] + [(0.5 + o / 2, c) for o, c in GLOW[1:]]
        out.append({'d': f'M{x0},{y - h} H{x1} V{y + h} H{x0} Z', 'linear': (x0, y - h, x0, y + h, across)})
        out.append({'d': f'M{x0},{y - h} A{h},{h} 0 0,0 {x0},{y + h} Z', 'radial': (x0, y, h, GLOW)})
        out.append({'d': f'M{x1},{y - h} A{h},{h} 0 0,1 {x1},{y + h} Z', 'radial': (x1, y, h, GLOW)})
    return out + [stroke(LINE, GREEN, 34)]


# --- VectorDrawable ---

def vector_xml(frame_dp, mark_dp, mono=False):
    side = WIDTH * frame_dp / mark_dp
    body = []
    for l in layers(None if mono else 'gradient', mono):
        attrs = f'android:pathData="{l["d"]}"'
        if 'fill' in l:
            attrs += f' android:fillColor="{l["fill"]}"'
        if 'stroke' in l:
            attrs += (f' android:strokeColor="{l["stroke"]}" android:strokeWidth="{l["width"]}"'
                      ' android:strokeLineCap="round" android:strokeLineJoin="round"')
        kind = 'radial' if 'radial' in l else 'linear' if 'linear' in l else None
        if kind:
            *geo, stops = l[kind]
            keys = ('centerX', 'centerY', 'gradientRadius') if kind == 'radial' else (
                'startX', 'startY', 'endX', 'endY')
            grad = ''.join(f' android:{k}="{num(v)}"' for k, v in zip(keys, geo))
            items = ''.join(f'\n    <item android:offset="{num(o)}" android:color="{c}"/>' for o, c in stops)
            path = (f'<path {attrs}>\n<aapt:attr name="android:fillColor">\n'
                    f'<gradient android:type="{kind}"{grad}>{items}\n</gradient>\n</aapt:attr>\n</path>')
        else:
            path = f'<path {attrs}/>'
        if 'clip' in l:
            path = f'<group>\n<clip-path android:pathData="{l["clip"]}"/>\n{path}\n</group>'
        body.append(path)
    inner = '\n'.join(body).replace('\n', '\n        ')
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/brand.py; do not edit. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="{frame_dp}dp"
    android:height="{frame_dp}dp"
    android:viewportWidth="{num(side)}"
    android:viewportHeight="{num(side)}">
    <group
        android:name="mark"
        android:translateX="{num(side / 2 - CENTER[0])}"
        android:translateY="{num(side / 2 - CENTER[1])}">
        {inner}
    </group>
</vector>
'''


SPLASH_ICON = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/brand.py; do not edit. Animatable only so the system
     draws splash_mark at full size instead of a blurry 108 dp bitmap. -->
<animated-vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:drawable="@drawable/splash_mark">
    <target android:name="mark">
        <aapt:attr name="android:animation">
            <objectAnimator
                android:duration="1"
                android:propertyName="rotation"
                android:valueFrom="0"
                android:valueTo="0" />
        </aapt:attr>
    </target>
</animated-vector>
'''


# --- SVG (reference and previews) ---

def svg_color(c):
    """'#AARRGGBB' or '#RRGGBB' -> (svg color, opacity)."""
    return ('#' + c[3:], int(c[1:3], 16) / 255) if len(c) == 9 else (c, 1)


def mark_svg(glow, side, mono=False, uid='m'):
    """<g> drawing the mark centered in a side x side user space."""
    defs, body = [], []
    for i, l in enumerate(layers(glow, mono)):
        a = f'd="{l["d"]}"'
        a += f' fill="{l["fill"]}"' if 'fill' in l else ' fill="none"'
        if 'stroke' in l:
            a += (f' stroke="{l["stroke"]}" stroke-width="{l["width"]}"'
                  ' stroke-linecap="round" stroke-linejoin="round"')
        if 'opacity' in l:
            a += f' opacity="{l["opacity"]}"'
        if 'blur' in l:
            defs.append(f'<filter id="{uid}b{i}" filterUnits="userSpaceOnUse" x="0" y="0" '
                        f'width="2048" height="2048"><feGaussianBlur stdDeviation="{l["blur"]}"/></filter>')
            a += f' filter="url(#{uid}b{i})"'
        if 'clip' in l:
            defs.append(f'<clipPath id="{uid}c{i}"><path d="{l["clip"]}"/></clipPath>')
            a += f' clip-path="url(#{uid}c{i})"'
        kind = 'radial' if 'radial' in l else 'linear' if 'linear' in l else None
        if kind:
            *geo, stops = l[kind]
            keys = ('cx', 'cy', 'r') if kind == 'radial' else ('x1', 'y1', 'x2', 'y2')
            grad = ''.join(f' {k}="{num(v)}"' for k, v in zip(keys, geo))
            s = ''.join('<stop offset="{}" stop-color="{}" stop-opacity="{:.3f}"/>'.format(o, *svg_color(c))
                        for o, c in stops)
            defs.append(f'<{kind}Gradient id="{uid}g{i}" gradientUnits="userSpaceOnUse"{grad}>{s}</{kind}Gradient>')
            a = a.replace('fill="none"', f'fill="url(#{uid}g{i})"')
        body.append(f'<path {a}/>')
    t = f'translate({num(side / 2 - CENTER[0])} {num(side / 2 - CENTER[1])})'
    return f'<defs>{"".join(defs)}</defs><g transform="{t}">{"".join(body)}</g>'


def svg(inner, w, h, view):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="{view}">{inner}</svg>')


def screenshot(html, out, w, h, scale=1):
    page = PREVIEW / (out.stem + '.html')
    page.write_text(f'<!doctype html><html><body style="margin:0">{html}</body></html>')
    with tempfile.TemporaryDirectory() as profile:
        subprocess.run(['google-chrome', '--headless=new', '--disable-gpu', '--hide-scrollbars',
                        f'--user-data-dir={profile}', f'--force-device-scale-factor={scale}',
                        f'--window-size={w},{h}', '--default-background-color=00000000',
                        f'--screenshot={out}', page.as_uri()],
                       check=True, capture_output=True)


def previews(branding_png):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    ref = 1000 / 0.86  # square that holds the glow
    navy = f'<rect x="0" y="0" width="{num(ref)}" height="{num(ref)}" fill="{NAVY}"/>'
    row = ''
    for size in (425, 850):  # splash size on a 2.625x phone, then 2x
        for glow in ('blur', 'gradient'):
            row += svg(navy + mark_svg(glow, ref, uid=f'{glow}{size}'), size, size, f'0 0 {num(ref)} {num(ref)}')
        row += '<br>'
    screenshot(row, PREVIEW / 'glow.png', 1700, 1275)

    # Launcher: the visible 72 dp of the 108 dp layers, masked, with the 66 dp safe zone.
    side = WIDTH * 108 / 47
    unit = side / 108
    vis = 72 * unit
    off = (side - vis) / 2
    c, r = side / 2, 36 * unit
    masks = {'circle': circle(c, c, r), 'squircle': squircle(c, c, r)}
    for name, mask in masks.items():
        inner = (f'<clipPath id="k"><path d="{mask}"/></clipPath><g clip-path="url(#k)">'
                 f'<rect width="{num(side)}" height="{num(side)}" fill="{NAVY}"/>{mark_svg("gradient", side)}</g>'
                 f'<circle cx="{num(side / 2)}" cy="{num(side / 2)}" r="{num(33 * unit)}" fill="none" '
                 f'stroke="#FF3B30" stroke-width="{num(0.25 * unit)}"/>')
        screenshot(svg(inner, 576, 576, f'{num(off)} {num(off)} {num(vis)} {num(vis)}'),
                   PREVIEW / f'icon-{name}.png', 576, 576)

    side = WIDTH * 288 / 136
    data = base64.b64encode(branding_png).decode()
    html = (f'<div style="position:relative;width:412px;height:915px;background:{NAVY}">'
            f'<div style="position:absolute;left:62px;top:313.5px">'
            f'{svg(mark_svg("gradient", side), 288, 288, f"0 0 {num(side)} {num(side)}")}</div>'
            f'<img src="data:image/png;base64,{data}" style="position:absolute;left:106px;bottom:60px;'
            f'width:200px;height:80px"></div>')
    screenshot(html, PREVIEW / 'splash.png', 412, 915, 2.625)


# --- Wordmark ---

def wordmark_from(logo):
    """Spec 8.4: color-to-alpha against white, noise cut, tight crop; white with alpha."""
    lum = Image.open(logo).convert('L').crop((480, 1380, 1570, 1790))
    alpha = lum.point(lambda l: 0 if (a := round((255 - l) * 255 / (255 - 41))) < 10 else min(a, 255))
    alpha = alpha.crop(alpha.getbbox())
    out = Image.new('RGBA', alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def branding(alpha, w, h):
    """Wordmark in paper color, 136/200 of the frame width, centered on transparent."""
    mw = round(w * 136 / 200)
    mh = round(mw * alpha.height / alpha.width)
    mark = Image.new('RGBA', (mw, mh), PAPER)
    mark.putalpha(alpha.resize((mw, mh), Image.LANCZOS))
    frame = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    frame.paste(mark, ((w - mw) // 2, (h - mh) // 2))
    return frame


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--logo', type=Path, help='logo.jpeg; rebuilds assets/brand/wordmark.png')
    args = p.parse_args()

    if args.logo:
        WORDMARK.parent.mkdir(parents=True, exist_ok=True)
        wordmark_from(args.logo).save(WORDMARK)
    alpha = Image.open(WORDMARK).getchannel('A')

    drawable = RES / 'drawable'
    drawable.mkdir(parents=True, exist_ok=True)
    (drawable / 'ic_launcher_foreground.xml').write_text(vector_xml(108, 47))
    (drawable / 'ic_launcher_monochrome.xml').write_text(vector_xml(108, 47, mono=True))
    (drawable / 'splash_mark.xml').write_text(vector_xml(288, 136))
    (drawable / 'splash_icon.xml').write_text(SPLASH_ICON)
    for density, scale in (('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)):
        d = RES / f'drawable-{density}'
        d.mkdir(exist_ok=True)
        branding(alpha, 200 * scale, 80 * scale).save(d / 'splash_branding.png', optimize=True)

    ref = 1000 / 0.86
    (ROOT / 'tool/brand').mkdir(exist_ok=True)
    (ROOT / 'tool/brand/reference.svg').write_text(
        svg(mark_svg('blur', ref), 1024, 1024, f'0 0 {num(ref)} {num(ref)}') + '\n')

    if shutil.which('google-chrome'):
        buf = io.BytesIO()
        branding(alpha, 600, 240).save(buf, 'PNG')
        previews(buf.getvalue())
    else:
        print('google-chrome not found; previews skipped')


if __name__ == '__main__':
    main()
