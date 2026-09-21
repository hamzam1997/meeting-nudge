#!/usr/bin/env python3
"""Draws the app icon. Run `python3 Resources/make-icon.py` after editing,
then rebuild. Kept as source so the icon is reproducible rather than an
opaque binary nobody can change."""
from PIL import Image, ImageDraw

S = 1024
PAD = int(S * 0.09)          # macOS icons sit inside a margin
BLUE, DEEP = (56, 120, 242), (28, 78, 196)
WHITE, INK = (255, 255, 255), (32, 38, 52)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# Rounded square with a soft vertical gradient.
box = (PAD, PAD, S - PAD, S - PAD)
radius = int((S - 2 * PAD) * 0.225)
grad = Image.new("RGBA", (1, S), (0, 0, 0, 0))
for y in range(S):
    t = y / S
    grad.putpixel((0, y), tuple(int(BLUE[i] + (DEEP[i] - BLUE[i]) * t) for i in range(3)) + (255,))
grad = grad.resize((S, S))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
img.paste(grad, (0, 0), mask)

# Calendar page.
cx0, cy0 = int(S * 0.255), int(S * 0.295)
cx1, cy1 = int(S * 0.745), int(S * 0.735)
d.rounded_rectangle((cx0, cy0, cx1, cy1), radius=int(S * 0.045), fill=WHITE)
# Header band and its two rings.
d.rounded_rectangle((cx0, cy0, cx1, cy0 + int(S * 0.105)), radius=int(S * 0.045), fill=INK)
d.rectangle((cx0, cy0 + int(S * 0.06), cx1, cy0 + int(S * 0.105)), fill=INK)
for fx in (0.36, 0.64):
    x = int(S * fx)
    d.rounded_rectangle((x - int(S * 0.018), cy0 - int(S * 0.038),
                         x + int(S * 0.018), cy0 + int(S * 0.032)),
                        radius=int(S * 0.018), fill=WHITE)
# Date grid, fading out where the clock sits.
gx, gy = cx0 + int(S * 0.055), cy0 + int(S * 0.165)
dot, gap = int(S * 0.042), int(S * 0.082)
for r in range(3):
    for c in range(4):
        if r >= 1 and c >= 2:
            continue
        x, y = gx + c * gap, gy + r * gap
        d.rounded_rectangle((x, y, x + dot, y + dot), radius=int(dot * 0.3), fill=(198, 208, 224))

# Clock badge, overlapping the lower right corner.
bx, by, br = int(S * 0.685), int(S * 0.675), int(S * 0.165)
d.ellipse((bx - br - int(S * 0.022), by - br - int(S * 0.022),
           bx + br + int(S * 0.022), by + br + int(S * 0.022)), fill=WHITE)
d.ellipse((bx - br, by - br, bx + br, by + br), fill=DEEP)
w = int(S * 0.021)
d.line((bx, by, bx, by - int(br * 0.55)), fill=WHITE, width=w)          # minute hand
d.line((bx, by, bx + int(br * 0.42), by), fill=WHITE, width=w)          # hour hand
d.ellipse((bx - w, by - w, bx + w, by + w), fill=WHITE)

img.save("Resources/icon-1024.png")
print("wrote Resources/icon-1024.png")
