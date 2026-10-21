"""Generate dclash's monochrome geometric cat mark.

The artwork is deliberately drawn with Pillow instead of an image generator so
that every platform receives the same deterministic, two-colour mark. The
macOS asset catalog gets separate aqua and darkAqua variants; Flutter and the
other desktop targets use the light variant as their default icon.
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
SIZE = 1024
# Keep the mark crisp at 16–20 px while giving the internal ribbons a little
# more visual weight than the previous hairline treatment.
STROKE = 40


def _segments(draw: ImageDraw.ImageDraw, color: tuple[int, int, int, int]) -> None:
    """Draw the cat outline and its two crossing face ribbons.

    The ears and jaw form a single angular silhouette. Two open polylines
    cross around the nose to suggest dclash's interleaving routes while keeping
    the small-size mark legible.
    """

    def line(points: list[tuple[int, int]], width: int = STROKE) -> None:
        draw.line(points, fill=color, width=width, joint="curve")

    # Angular head, ears and jaw.
    line(
        [
            (240, 420),
            (250, 210),
            (410, 322),
            (512, 274),
            (614, 322),
            (774, 210),
            (784, 420),
            (756, 574),
            (684, 692),
            (512, 790),
            (340, 692),
            (268, 574),
            (240, 420),
        ]
    )

    # Eyes are open geometric chevrons rather than filled shapes.
    line([(350, 458), (414, 425), (456, 470)], width=32)
    line([(568, 470), (610, 425), (674, 458)], width=32)

    # Two crossing ribbons create the interlaced dclash signature.
    line([(300, 520), (440, 630), (512, 585), (584, 630), (724, 520)], width=34)
    line([(300, 650), (440, 535), (512, 585), (584, 535), (724, 650)], width=34)

    # Small diamond nose and a centred mouth keep the face readable at 16 px.
    line([(512, 525), (538, 548), (512, 571), (486, 548), (512, 525)], width=30)
    line([(512, 571), (512, 610)], width=30)


def _icon(
    background: tuple[int, int, int, int],
    foreground: tuple[int, int, int, int],
) -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), background)
    _segments(ImageDraw.Draw(image), foreground)
    return image


def _write_scaled(image: Image.Image, path: Path, sizes: tuple[int, ...]) -> None:
    for size in sizes:
        image.resize((size, size), Image.Resampling.LANCZOS).save(
            path.with_name(f"{path.stem}_{size}.png")
        )


brand = ROOT / "assets/brand"
brand.mkdir(parents=True, exist_ok=True)

black = (0, 0, 0, 255)
white = (255, 255, 255, 255)
transparent = (0, 0, 0, 0)

# Opaque brand marks used by Flutter, Android and Windows.
light = _icon(white, black)
dark = _icon(black, white)
light.save(brand / "app_icon.png")
dark.save(brand / "app_icon_dark.png")

# Xcode's default Dock icon. Keep the macOS artwork transparent so AppKit does
# not present an opaque white/black tile with a grey edge in the Dock. The
# Flutter, Android and Windows marks above intentionally keep their solid brand
# backgrounds.
app_icon_set = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
app_icon_set.mkdir(parents=True, exist_ok=True)
for old in app_icon_set.glob("app_icon_*.png"):
    old.unlink()
light_dock = _icon(transparent, black)
dark_dock = _icon(transparent, white)
_write_scaled(
    light_dock,
    app_icon_set / "app_icon_aqua.png",
    (16, 32, 64, 128, 256, 512, 1024),
)

# Named image sets are used by the native macOS delegate to change the Dock
# image immediately when the effective system appearance changes.
for name, image, filename in (
    ("DclashLogoAqua.imageset", light_dock, "dclash_logo_aqua.png"),
    ("DclashLogoDarkAqua.imageset", dark_dock, "dclash_logo_darkAqua.png"),
):
    image_set = ROOT / "macos/Runner/Assets.xcassets" / name
    image_set.mkdir(parents=True, exist_ok=True)
    image.save(image_set / filename)
    (image_set / "Contents.json").write_text(
        "{\n"
        '  "images" : [\n'
        f'    {{ "filename" : "{filename}", "idiom" : "universal", "scale" : "1x" }}\n'
        "  ],\n"
        '  "info" : { "author" : "xcode", "version" : 1 }\n'
        "}\n"
    )

# Windows executable icon defaults to the light, high-contrast mark.
light.save(
    ROOT / "windows/runner/resources/app_icon.ico",
    sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)],
)

# Android's launcher resources use the same light mark at each density.
for density, size in {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}.items():
    directory = ROOT / f"android/app/src/main/res/mipmap-{density}"
    directory.mkdir(parents=True, exist_ok=True)
    scaled = light.resize((size, size), Image.Resampling.LANCZOS)
    scaled.save(directory / "ic_launcher.png")
    # The copied reference and Flutter scaffold contain duplicate resource names.
    for duplicate in directory.glob("ic_launcher*.webp"):
        duplicate.unlink()
    scaled.save(directory / "ic_launcher_round.png")

# Menu-bar/tray assets are template-friendly transparent line art. macOS
# applies the foreground colour because DesktopIntegrationService marks it as
# a template image. Crop the generous app-icon padding so the small status
# item uses the available slot for the actual mark.
tray = Image.new("RGBA", (SIZE, SIZE), transparent)
_segments(ImageDraw.Draw(tray), black)
left, top, right, bottom = tray.getbbox()
padding = 96
tray = tray.crop(
    (
        max(0, left - padding),
        max(0, top - padding),
        min(SIZE, right + padding),
        min(SIZE, bottom + padding),
    )
)
tray.resize((48, 48), Image.Resampling.LANCZOS).save(brand / "tray.png")
tray.save(brand / "tray.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64)])
