#!/bin/zsh
set -euo pipefail

CONFIGURATION="release"
SKIP_BUILD="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="QuotaBar"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

generate_app_icon() {
  local iconset_dir
  local temp_dir
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/quotabar-icon.XXXXXX")"
  iconset_dir="$temp_dir/AppIcon.iconset"
  mkdir -p "$iconset_dir"

  /usr/bin/python3 - "$iconset_dir" <<'PY'
import math
import os
import struct
import sys
import zlib

out_dir = sys.argv[1]

files = [
    ("icon_512x512@2x.png", 1024),
]


def clamp(value):
    return max(0, min(255, int(round(value))))


def blend(dst, src):
    sr, sg, sb, sa = src
    if sa <= 0:
        return dst
    dr, dg, db, da = dst
    a = sa / 255.0
    inv = 1.0 - a
    out_a = sa + da * inv
    if out_a <= 0:
        return (0, 0, 0, 0)
    return (
        clamp((sr * sa + dr * da * inv) / out_a),
        clamp((sg * sa + dg * da * inv) / out_a),
        clamp((sb * sa + db * da * inv) / out_a),
        clamp(out_a),
    )


def rounded_rect_alpha(x, y, left, top, right, bottom, radius):
    nearest_x = min(max(x, left + radius), right - radius)
    nearest_y = min(max(y, top + radius), bottom - radius)
    distance = math.hypot(x - nearest_x, y - nearest_y)
    return max(0.0, min(1.0, radius + 0.5 - distance))


def fill_rounded_rect(pixels, size, rect, radius, color):
    left, top, right, bottom = rect
    for y in range(max(0, int(top)), min(size, int(math.ceil(bottom)))):
        for x in range(max(0, int(left)), min(size, int(math.ceil(right)))):
            alpha = rounded_rect_alpha(x + 0.5, y + 0.5, left, top, right, bottom, radius)
            if alpha > 0:
                r, g, b, a = color
                idx = y * size + x
                pixels[idx] = blend(pixels[idx], (r, g, b, clamp(a * alpha)))


def fill_rect(pixels, size, rect, color):
    left, top, right, bottom = rect
    for y in range(max(0, int(top)), min(size, int(math.ceil(bottom)))):
        for x in range(max(0, int(left)), min(size, int(math.ceil(right)))):
            idx = y * size + x
            pixels[idx] = blend(pixels[idx], color)


def render(size):
    if size <= 256:
        scale = 4
    elif size <= 512:
        scale = 2
    else:
        scale = 1
    canvas = size * scale
    pixels = [(0, 0, 0, 0)] * (canvas * canvas)
    s = canvas / 1024.0

    def q(value):
        return value * s

    fill_rounded_rect(
        pixels,
        canvas,
        (q(74), q(74), q(950), q(950)),
        q(220),
        (247, 250, 252, 255),
    )
    fill_rounded_rect(
        pixels,
        canvas,
        (q(74), q(74), q(950), q(950)),
        q(220),
        (30, 41, 59, 18),
    )
    fill_rounded_rect(
        pixels,
        canvas,
        (q(134), q(142), q(890), q(882)),
        q(164),
        (255, 255, 255, 122),
    )
    fill_rounded_rect(
        pixels,
        canvas,
        (q(198), q(220), q(826), q(804)),
        q(58),
        (27, 40, 56, 232),
    )
    fill_rounded_rect(
        pixels,
        canvas,
        (q(248), q(270), q(776), q(350)),
        q(40),
        (248, 250, 252, 232),
    )
    fill_rounded_rect(
        pixels,
        canvas,
        (q(270), q(292), q(424), q(328)),
        q(18),
        (20, 184, 166, 255),
    )
    fill_rounded_rect(
        pixels,
        canvas,
        (q(444), q(292), q(666), q(328)),
        q(18),
        (59, 130, 246, 255),
    )
    fill_rounded_rect(
        pixels,
        canvas,
        (q(690), q(292), q(732), q(328)),
        q(18),
        (245, 158, 11, 255),
    )

    bars = [
        (q(292), q(598), q(382), q(736), (20, 184, 166, 255)),
        (q(422), q(502), q(512), q(736), (34, 197, 94, 255)),
        (q(552), q(420), q(642), q(736), (59, 130, 246, 255)),
        (q(682), q(352), q(772), q(736), (245, 158, 11, 255)),
    ]
    for left, top, right, bottom, color in bars:
        fill_rounded_rect(pixels, canvas, (left, top, right, bottom), q(26), color)

    fill_rect(pixels, canvas, (q(276), q(746), q(788), q(764)), (226, 232, 240, 174))

    if scale == 1:
        return pixels

    downsampled = []
    area = scale * scale
    for y in range(size):
        for x in range(size):
            totals = [0, 0, 0, 0]
            for sy in range(scale):
                row = (y * scale + sy) * canvas
                for sx in range(scale):
                    r, g, b, a = pixels[row + x * scale + sx]
                    totals[0] += r
                    totals[1] += g
                    totals[2] += b
                    totals[3] += a
            downsampled.append(tuple(clamp(value / area) for value in totals))
    return downsampled


def write_png(path, size, pixels):
    raw_rows = []
    for y in range(size):
        row = bytearray([0])
        for r, g, b, a in pixels[y * size:(y + 1) * size]:
            row.extend((r, g, b, a))
        raw_rows.append(bytes(row))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(raw_rows), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


os.makedirs(out_dir, exist_ok=True)
for filename, size in files:
    write_png(os.path.join(out_dir, filename), size, render(size))
PY

  local master_icon="$iconset_dir/icon_512x512@2x.png"
  /usr/bin/sips -z 16 16 "$master_icon" --out "$iconset_dir/icon_16x16.png" >/dev/null
  /usr/bin/sips -z 32 32 "$master_icon" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  /usr/bin/sips -z 32 32 "$master_icon" --out "$iconset_dir/icon_32x32.png" >/dev/null
  /usr/bin/sips -z 64 64 "$master_icon" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  /usr/bin/sips -z 128 128 "$master_icon" --out "$iconset_dir/icon_128x128.png" >/dev/null
  /usr/bin/sips -z 256 256 "$master_icon" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$master_icon" --out "$iconset_dir/icon_256x256.png" >/dev/null
  /usr/bin/sips -z 512 512 "$master_icon" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$master_icon" --out "$iconset_dir/icon_512x512.png" >/dev/null

  /usr/bin/iconutil -c icns "$iconset_dir" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$temp_dir"
}

cd "$ROOT_DIR"
if [[ "$SKIP_BUILD" != "true" ]]; then
  swift build --product "$APP_NAME" --configuration "$CONFIGURATION"
fi

BIN_DIR="$ROOT_DIR/.build/$CONFIGURATION"
if [[ ! -x "$BIN_DIR/$APP_NAME" ]]; then
  HOST_TRIPLE="$(swift -print-target-info | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["triple"])')"
  BIN_DIR="$ROOT_DIR/.build/$HOST_TRIPLE/$CONFIGURATION"
fi
EXECUTABLE="$BIN_DIR/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Built executable not found: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>QuotaBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.quotabar.local</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>QuotaBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 QuotaBar.</string>
</dict>
</plist>
PLIST

generate_app_icon

echo "Created $APP_DIR"
