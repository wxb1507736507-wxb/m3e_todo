/// The named colours offered in the colour pickers.
///
/// A shared list rather than one per field: the tile colour and the text colour
/// are chosen from the same vocabulary, and "the red I picked for the card" and
/// "the red I picked for the text" should be the same red.
///
/// A dozen-odd entries, deliberately: a wall of forty swatches is slower to scan
/// than the free picker that sits next to it, so this covers the colours people
/// reach for by name and leaves everything else to that.
library;

/// A colour the user can pick by name, as an ARGB32 integer.
class AppPaletteColor {
  const AppPaletteColor(this.argb, this.label);

  final int argb;
  final String label;
}

/// Common colours, ordered as a spectrum with the neutrals at the end.
const List<AppPaletteColor> kCommonColors = <AppPaletteColor>[
  AppPaletteColor(0xFFE53935, '红'),
  AppPaletteColor(0xFFF4511E, '朱红'),
  AppPaletteColor(0xFFFB8C00, '橙'),
  AppPaletteColor(0xFFFFB300, '琥珀'),
  AppPaletteColor(0xFFFDD835, '黄'),
  AppPaletteColor(0xFF7CB342, '黄绿'),
  AppPaletteColor(0xFF43A047, '绿'),
  AppPaletteColor(0xFF00897B, '青绿'),
  AppPaletteColor(0xFF00ACC1, '青'),
  AppPaletteColor(0xFF1E88E5, '蓝'),
  AppPaletteColor(0xFF3949AB, '靛蓝'),
  AppPaletteColor(0xFF8E24AA, '紫'),
  AppPaletteColor(0xFFD81B60, '玫红'),
  AppPaletteColor(0xFF6D4C41, '棕'),
  AppPaletteColor(0xFF757575, '灰'),
  AppPaletteColor(0xFF263238, '深灰'),
  AppPaletteColor(0xFF000000, '黑'),
  AppPaletteColor(0xFFFFFFFF, '白'),
];

/// Pastel counterparts of the same hues, for text over a coloured card.
///
/// Light tints rather than the saturated set above: dark text on a dark card is
/// unreadable, and choosing a text colour is a different job from choosing a
/// card colour.
const List<AppPaletteColor> kSoftColors = <AppPaletteColor>[
  AppPaletteColor(0xFFFFCDD2, '浅红'),
  AppPaletteColor(0xFFFFE0B2, '浅橙'),
  AppPaletteColor(0xFFFFF9C4, '浅黄'),
  AppPaletteColor(0xFFDCEDC8, '浅绿'),
  AppPaletteColor(0xFFB2DFDB, '浅青'),
  AppPaletteColor(0xFFBBDEFB, '浅蓝'),
  AppPaletteColor(0xFFD1C4E9, '浅紫'),
  AppPaletteColor(0xFFF8BBD0, '浅粉'),
  AppPaletteColor(0xFFD7CCC8, '浅棕'),
  AppPaletteColor(0xFFCFD8DC, '浅灰'),
  AppPaletteColor(0xFF1B1B1B, '近黑'),
  AppPaletteColor(0xFFFFFFFF, '白'),
];
