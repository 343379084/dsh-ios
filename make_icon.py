"""生成 iOS App 图标 1024x1024（无 alpha，RGB）。

设计：DeepSeek 品牌蓝径向渐变底 + 白色圆角"终端窗口" + 提示符 > 和光标块。
iOS 会自动裁圆角，所以这里画满方形。
"""
import os
from PIL import Image, ImageDraw

S = 1024
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "DSHMobile", "Assets.xcassets", "AppIcon.appiconset")

# ---------- 背景：对角线渐变 #4D6BFE -> #2A3FD0，带一点柔和高光 ----------
top = (77, 107, 254)      # #4D6BFE
bottom = (38, 55, 180)

img = Image.new("RGB", (S, S), top)
px = img.load()
for y in range(S):
    t = y / (S - 1)
    # 轻微 gamma 让上亮下暗更自然
    tt = t ** 0.85
    r = int(top[0] + (bottom[0] - top[0]) * tt)
    g = int(top[1] + (bottom[1] - top[1]) * tt)
    b = int(top[2] + (bottom[2] - top[2]) * tt)
    for x in range(S):
        # 左上角高光
        d = ((x - S * 0.18) ** 2 + (y - S * 0.12) ** 2) ** 0.5
        boost = max(0.0, 1.0 - d / (S * 0.75)) ** 2 * 26
        px[x, y] = (min(255, int(r + boost)),
                    min(255, int(g + boost)),
                    min(255, int(b + boost * 0.9)))

d = ImageDraw.Draw(img, "RGBA")

# ---------- 白色终端窗口 ----------
# 外框：62,272 -> 962,752，圆角 64
win = [62, 268, 962, 756]
radius = 68

# 柔和投影
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle([win[0] - 6, win[1] + 16, win[2] + 6, win[3] + 26],
                     radius=radius, fill=(12, 20, 60, 90))
shadow = shadow.filter(__import__("PIL.ImageFilter", fromlist=["ImageFilter"]).GaussianBlur(22))
img.paste(Image.alpha_composite(img.convert("RGBA"), shadow).convert("RGB"), (0, 0))
d = ImageDraw.Draw(img, "RGBA")

# 窗口主体：白到浅灰的竖向渐变
win_img = Image.new("RGB", (win[2] - win[0], win[3] - win[1]), (255, 255, 255))
wp = win_img.load()
wh = win_img.height
for y in range(wh):
    t = y / max(1, wh - 1)
    v = int(255 - 14 * t)
    for x in range(win_img.width):
        wp[x, y] = (v, v, min(255, v + 2))

mask = Image.new("L", win_img.size, 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([0, 0, win_img.width - 1, win_img.height - 1], radius=radius, fill=255)
img.paste(win_img, (win[0], win[1]), mask)

# ---------- 提示符 > ----------
accent = (77, 107, 254)
cx, cy = 300, 512
arm = 92          # 臂长
thick = 34        # 笔画粗细
# 用两条粗线段拼一个 >
p1 = [(cx - 40, cy - arm), (cx + 46, cy), (cx - 40, cy + arm)]
for i in range(len(p1) - 1):
    d.line([p1[i], p1[i + 1]], fill=accent, width=thick)
# 端点补圆，避免方头
for pt in p1:
    r = thick // 2
    d.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=accent)

# ---------- 光标块 █ ----------
bx0, by0, bx1, by1 = 392, 452, 560, 572
d.rounded_rectangle([bx0, by0, bx1, by1], radius=16, fill=(77, 107, 254, 235))

# 光标块底部一条更亮的边，制造"发光"感
d.rounded_rectangle([bx0, by1 - 10, bx1, by1], radius=6, fill=(120, 148, 255, 255))

# ---------- 顶部三条窗口按钮 ----------
for i, col in enumerate([(255, 95, 92), (255, 189, 46), (39, 201, 63)]):
    cx0 = win[0] + 62 + i * 46
    cy0 = win[1] + 54
    d.ellipse([cx0 - 11, cy0 - 11, cx0 + 11, cy0 + 11], fill=col)

# ---------- 底部三条"代码行"示意 ----------
lines = [(200, 96, 0.55), (250, 62, 0.40), (176, 72, 0.30)]
base_y = 640
for w, _, alpha in lines:
    d.rounded_rectangle([640, base_y, 640 + w, base_y + 16], radius=8,
                        fill=(30, 41, 90, int(255 * alpha)))
    base_y += 30

# ---------- 输出 ----------
os.makedirs(OUT_DIR, exist_ok=True)
out = os.path.join(OUT_DIR, "AppIcon-1024.png")
img.convert("RGB").save(out, "PNG", optimize=True)

# 附带一张用于文档预览
prev = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AppIcon-1024.png")
img.convert("RGB").resize((256, 256), Image.LANCZOS).save(prev, "PNG")

from PIL import Image as I
chk = I.open(out)
print(f"OK  {out}")
print(f"size={chk.size} mode={chk.mode} bytes={os.path.getsize(out)}")
