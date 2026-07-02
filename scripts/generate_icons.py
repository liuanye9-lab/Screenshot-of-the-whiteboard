from PIL import Image, ImageDraw
import os

ICONSET = "/Users/lay/Library/Mobile Documents/com~apple~CloudDocs/白板截图插件/SnapLeaf/Sources/Resources/AppIcon.iconset"
os.makedirs(ICONSET, exist_ok=True)

SIZES = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

def lerp(a, b, t):
    return int(a + (b - a) * t)

def draw_camera(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Gradient background: 1-pixel wide column resized
    gradient = Image.new("RGB", (1, size), 0)
    pixels = gradient.load()
    top = (56, 189, 248)
    bot = (37, 99, 235)
    for y in range(size):
        t = y / size
        pixels[0, y] = (
            lerp(top[0], bot[0], t),
            lerp(top[1], bot[1], t),
            lerp(top[2], bot[2], t),
        )
    gradient = gradient.resize((size, size), Image.BILINEAR)
    img.paste(gradient)

    # Rounded rectangle mask
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    rx = int(size * 0.211)
    mdraw.rounded_rectangle([0, 0, size, size], radius=rx, fill=255)
    img.putalpha(mask)

    draw = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    sw = max(1, int(size * 0.047))

    # Camera body
    bx = int(size * 0.25)
    by = int(size * 0.344)
    bw = int(size * 0.5)
    bh = int(size * 0.344)
    br = int(size * 0.055)
    draw.rounded_rectangle([bx, by, bx + bw, by + bh], radius=br, outline=white, width=sw)

    # Lens
    cx, cy = size // 2, int(size * 0.516)
    lr = int(size * 0.102)
    draw.ellipse([cx - lr, cy - lr, cx + lr, cy + lr], outline=white, width=sw)

    # Viewfinder bump
    vx = int(size * 0.383)
    vy = int(size * 0.25)
    vw = int(size * 0.234)
    vh = int(size * 0.094)
    vr = int(size * 0.031)
    draw.rounded_rectangle([vx, vy, vx + vw, vy + vh], radius=vr, outline=white, width=sw)

    # Flash dot
    fx = int(size * 0.688)
    fy = int(size * 0.422)
    fr = max(1, int(size * 0.023))
    draw.ellipse([fx - fr, fy - fr, fx + fr, fy + fr], fill=white)

    return img

for name, size in SIZES:
    img = draw_camera(size)
    img.save(os.path.join(ICONSET, f"{name}.png"), "PNG")
    print(f"Generated {name}.png ({size}x{size})")

print("Done.")
