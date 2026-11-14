"""Export editable vector achievement badges and Apple's 512px PNG assets.

Requires Pillow for antialiased raster export; the SVG sources remain editable.
"""
from pathlib import Path
from math import cos, sin, pi
from PIL import Image, ImageDraw

OUT = Path(__file__).parent / 'artwork'
OUT.mkdir(exist_ok=True)
GOLD = '#e8b94d'
CREAM = '#fff4d5'
GREEN = '#173f2d'
LEAF = '#8bd263'


def badge(name, draw_icon):
    scale = 4
    image = Image.new('RGB', (512 * scale, 512 * scale), '#102c22')
    drawing = ImageDraw.Draw(image)
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">',
           '<rect width="512" height="512" fill="#102c22"/>']

    def ellipse(box, color):
        x, y, r, b = box
        drawing.ellipse(tuple(int(v * scale) for v in box), fill=color)
        svg.append(f'<ellipse cx="{(x+r)/2}" cy="{(y+b)/2}" rx="{(r-x)/2}" ry="{(b-y)/2}" fill="{color}"/>')

    def polygon(points, color):
        drawing.polygon([(int(x*scale), int(y*scale)) for x, y in points], fill=color)
        svg.append(f'<polygon points="{" ".join(f"{x},{y}" for x,y in points)}" fill="{color}"/>')

    def rect(box, color):
        x, y, r, b = box
        drawing.rectangle(tuple(int(v*scale) for v in box), fill=color)
        svg.append(f'<rect x="{x}" y="{y}" width="{r-x}" height="{b-y}" fill="{color}"/>')

    def line(points, color, width):
        drawing.line([(int(x*scale), int(y*scale)) for x,y in points], fill=color, width=width*scale, joint='curve')
        svg.append(f'<polyline points="{" ".join(f"{x},{y}" for x,y in points)}" stroke="{color}" stroke-width="{width}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')

    ellipse((35,35,477,477), GOLD)
    ellipse((45,45,467,467), '#875f26')
    ellipse((54,54,458,458), GOLD)
    ellipse((66,66,446,446), GREEN)
    for i in range(36):
        angle = i * 2*pi/36
        x, y = 256+174*cos(angle), 256+174*sin(angle)
        ellipse((x-2,y-2,x+2,y+2), '#52754a')
    draw_icon(ellipse, polygon, rect, line)
    svg.append('</svg>')
    (OUT / (name+'.svg')).write_text('\n'.join(svg))
    image.resize((512,512), Image.Resampling.LANCZOS).save(OUT / (name+'.png'))


def scissors(e,p,r,l):
    l([(204,298),(331,164)],CREAM,22)
    l([(304,298),(182,164)],CREAM,22)
    e((150,278,226,354),GOLD); e((283,278,359,354),GOLD)
    e((169,297,207,335),GREEN); e((302,297,340,335),GREEN)
    e((241,239,271,269),GOLD)
    p([(254,133),(279,114),(289,144),(268,168)],LEAF)


def trophy(e,p,r,l):
    l([(185,185),(139,185),(139,225),(176,254),(202,254)],GOLD,16)
    l([(327,185),(373,185),(373,225),(336,254),(310,254)],GOLD,16)
    p([(177,154),(335,154),(320,246),(289,278),(223,278),(192,246)],CREAM)
    r((246,274,266,332),GOLD); r((208,328,304,349),CREAM)
    p([(256,178),(269,204),(298,208),(277,229),(282,258),(256,244),(230,258),(235,229),(214,208),(243,204)],GOLD)


def sprout(e,p,r,l):
    p([(203,282),(309,282),(296,349),(216,349)],GOLD)
    r((190,270,322,289),CREAM)
    l([(255,274),(255,180)],CREAM,14)
    p([(254,228),(208,225),(170,192),(158,155),(202,160),(239,187)],LEAF)
    p([(260,198),(265,158),(299,126),(344,124),(332,163),(297,192)],GOLD)
    e((241,359,271,365),'#8c6b32')


def basket(e,p,r,l):
    l([(193,219),(205,171),(231,147),(281,147),(307,171),(319,219)],CREAM,16)
    e((177,193,234,250),LEAF); e((226,180,286,245),GOLD); e((278,198,335,252),'#e28655')
    p([(159,237),(353,237),(325,344),(187,344)],GOLD)
    r((155,231,357,251),CREAM)
    for x in [201,237,273,309]:
        l([(x,261),(x,329)],GREEN,9)
    l([(180,292),(332,292)],GREEN,9)


def estate(e,p,r,l):
    p([(150,226),(204,164),(256,203),(308,164),(362,226)],GOLD)
    r((170,222,342,343),CREAM)
    r((232,264,280,344),GREEN)
    for x in [190,299]:
        r((x,248,x+23,277),GOLD)
    r((152,338,360,354),GOLD)
    p([(256,124),(265,143),(286,146),(271,161),(275,182),(256,172),(237,182),(241,161),(226,146),(247,143)],CREAM)


for name, icon in [('first_slice',scissors),('score_10000',trophy),('first_harvest',sprout),('harvest_100',basket),('grand_estate',estate)]:
    badge(name, icon)
print('Exported five vector badges and five 512px RGB PNGs.')
