#!/usr/bin/env python3
"""Sinh icon app cho cả 3 nền tảng từ một bản vẽ duy nhất.

    python3 tools/gen-icons.py

Cần Pillow (`pip3 install Pillow`). Chạy lại là ghi đè — idempotent.

Vẽ gì: nền bo góc màu hổ phách (accent #E8A838 của PaperColors) + tờ note giấy
kem gập góc dưới-phải, trên có 2 dòng kẻ và một dấu check. Cùng ngôn ngữ hình
với icon tray ở assets/tray/ để menu bar và Dock trông cùng một app.

Vì sao vẽ bằng code chứ không nhét file PNG: cần 20+ biến thể kích thước cho
macOS/Windows/Android, mỗi lần sửa màu mà chỉnh tay 20 file là sai lệch ngay.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── Bảng màu: khớp PaperColors trong lib/app/theme.dart ──────────────────────
AMBER_TOP = (245, 196, 95)     # sáng hơn accent một chút cho gradient
AMBER_BOT = (222, 154, 36)     # đậm hơn accent
PAPER = (255, 253, 243)        # surface
FOLD = (233, 221, 189)         # line — mặt sau của góc gập
INK = (138, 124, 99)           # inkSoft, hơi đậm để nét kẻ còn thấy ở 16px
CHECK = (95, 145, 82)          # done, đậm hơn để tương phản trên giấy kem

# Bản vẽ gốc ở hệ 1024; badge tham chiếu là ô 824x824 đặt giữa (inset 100).
DESIGN = 1024
REF_INSET = 100.0
REF_SIZE = DESIGN - 2 * REF_INSET

SS = 4  # supersample: vẽ ở 4x rồi thu nhỏ bằng LANCZOS cho mượt


def _map(box):
    """Trả hàm đổi toạ độ hệ-1024 sang badge thực tế (đã nhân SS)."""
    left, top, size = box

    def f(*pts):
        out = []
        for p in pts:
            r = (p - REF_INSET) / REF_SIZE
            out.append((left + r * size) * SS)
        return out[0] if len(out) == 1 else out

    def s(v):  # đổi độ dài
        return v / REF_SIZE * size * SS

    return f, s


def _gradient(size, top, bot):
    """Gradient dọc, vẽ bằng 1px/dòng rồi resize — nhanh và đủ mượt."""
    strip = Image.new('RGB', (1, size))
    d = ImageDraw.Draw(strip)
    for y in range(size):
        t = y / max(size - 1, 1)
        d.point((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bot)))
    return strip.resize((size, size), Image.BILINEAR)


def _round_caps(d, pts, w, color):
    """PIL không có round-cap: tự úp hình tròn vào từng đầu/khớp nối."""
    r = w / 2
    for x, y in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def draw_icon(px, inset_ratio, radius_ratio, shadow=False, content_only=False,
              background_only=False, content_scale=1.0):
    """Vẽ một icon vuông px*px.

    inset_ratio    lề quanh badge (0 = tràn viền)
    radius_ratio   bán kính bo góc, theo cạnh badge
    shadow         bóng đổ nhẹ kiểu macOS
    content_only   chỉ vẽ tờ note (cho foreground của adaptive icon Android)
    background_only chỉ vẽ nền (cho background của adaptive icon Android)
    content_scale  thu nhỏ tờ note quanh tâm (adaptive icon cần safe zone)
    """
    S = px * SS
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))

    inset = S * inset_ratio
    bsize = S - 2 * inset
    radius = bsize * radius_ratio
    box = [inset / SS, inset / SS, bsize / SS]  # hệ chưa nhân SS cho _map
    fmap, flen = _map(box)

    if not content_only:
        if shadow:
            sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
            ImageDraw.Draw(sh).rounded_rectangle(
                [inset, inset + bsize * 0.012, inset + bsize, inset + bsize + bsize * 0.012],
                radius=radius, fill=(120, 78, 12, 90))
            sh = sh.filter(ImageFilter.GaussianBlur(bsize * 0.022))
            img.alpha_composite(sh)

        badge = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        mask = Image.new('L', (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [inset, inset, inset + bsize, inset + bsize], radius=radius, fill=255)
        grad = _gradient(S, AMBER_TOP, AMBER_BOT).convert('RGBA')
        badge.paste(grad, (0, 0), mask)
        img.alpha_composite(badge)

    # ── Tờ note ──────────────────────────────────────────────────────────────
    # Thu nhỏ quanh tâm khi cần safe zone: đổi hệ toạ độ trước khi vẽ.
    def C(v):
        c = DESIGN / 2
        return fmap(c + (v - c) * content_scale)

    def L(v):
        return flen(v * content_scale)

    nl, nt, nr, nb = C(232), C(232), C(792), C(792)
    nrad = L(30)
    cut = L(150)

    note = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    nd = ImageDraw.Draw(note)
    nd.rounded_rectangle([nl, nt, nr, nb], radius=nrad, fill=PAPER + (255,))
    # Cắt góc dưới-phải cho ra dáng giấy gập, rồi vẽ mặt sau đậm hơn.
    nd.polygon([(nr - cut, nb), (nr, nb - cut), (nr, nb)], fill=(0, 0, 0, 0))
    nd.polygon([(nr - cut, nb), (nr, nb - cut), (nr - cut, nb - cut)],
               fill=FOLD + (255,))

    lw = L(42)
    for y, x2 in ((340, 600), (432, 520)):
        y, x1, x2 = C(y), C(296), C(x2)
        nd.line([(x1, y), (x2, y)], fill=INK + (255,), width=round(lw))
        _round_caps(nd, [(x1, y), (x2, y)], lw, INK + (255,))

    cw = L(56)
    p = [(C(300), C(585)), (C(392), C(676)), (C(680), C(388))]
    nd.line(p, fill=CHECK + (255,), width=round(cw), joint='curve')
    _round_caps(nd, p, cw, CHECK + (255,))

    if not background_only:
        img.alpha_composite(note)
    return img.resize((px, px), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f'   {os.path.relpath(path, ROOT)}  {img.size[0]}px')


def main():
    # ── macOS: lề 100/1024 + bóng, đúng khung icon của Apple ─────────────────
    print('macOS  macos/Runner/Assets.xcassets/AppIcon.appiconset/')
    mac = os.path.join(ROOT, 'macos/Runner/Assets.xcassets/AppIcon.appiconset')
    for px in (16, 32, 64, 128, 256, 512, 1024):
        # Bóng đổ ở 16/32px chỉ làm nhoè: cỡ đó bóng chiếm cả pixel viền nên
        # nét kẻ với dấu check mất tương phản. Cỡ nhỏ vẽ phẳng cho rõ.
        save(draw_icon(px, 100 / 1024, 185 / 824, shadow=px >= 64),
             os.path.join(mac, f'app_icon_{px}.png'))

    # ── Windows: tràn hơn, bo ít hơn; .ico đa kích thước ─────────────────────
    print('Windows  windows/runner/resources/app_icon.ico')
    ico = draw_icon(256, 32 / 1024, 200 / 960)
    ico_path = os.path.join(ROOT, 'windows/runner/resources/app_icon.ico')
    ico.save(ico_path, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print(f'   {os.path.relpath(ico_path, ROOT)}  16→256px')

    # ── Android legacy: mipmap-*/ic_launcher.png ─────────────────────────────
    print('Android  android/app/src/main/res/')
    res = os.path.join(ROOT, 'android/app/src/main/res')
    for d, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                  ('xxhdpi', 144), ('xxxhdpi', 192)):
        save(draw_icon(px, 32 / 1024, 200 / 960),
             os.path.join(res, f'mipmap-{d}/ic_launcher.png'))

    # ── Android adaptive (API 26+): nền + foreground riêng ───────────────────
    # Foreground phải nằm trong safe zone 66/108 vì launcher cắt theo mask tròn
    # / squircle tuỳ máy; để nguyên cỡ là bị cắt mất góc gập.
    for d, px in (('mdpi', 108), ('hdpi', 162), ('xhdpi', 216),
                  ('xxhdpi', 324), ('xxxhdpi', 432)):
        save(draw_icon(px, 0, 0, content_only=True, content_scale=66 / 108 * 1.06),
             os.path.join(res, f'mipmap-{d}/ic_launcher_foreground.png'))
        save(draw_icon(px, 0, 0, background_only=True),
             os.path.join(res, f'mipmap-{d}/ic_launcher_background.png'))
    print('OK')


if __name__ == '__main__':
    main()
