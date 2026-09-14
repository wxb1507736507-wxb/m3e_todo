import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/utils/color_utils.dart';

/// Opens the free colour picker, returning the chosen ARGB32 colour.
///
/// [initial] seeds the sliders; passing `null` starts from a mid blue, because
/// starting from black would make the hue slider look broken (every hue at zero
/// value is black).
Future<int?> pickCustomColor(BuildContext context, {int? initial}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute<int>(
      fullscreenDialog: true,
      builder: (_) => ColorPickerPage(initial: initial),
    ),
  );
}

/// Free-form colour picker: hue, saturation and brightness, plus a hex field.
///
/// HSV rather than RGB sliders because that is the space people can steer: one
/// control chooses the colour, two choose how strong and how bright it is. RGB
/// asks the user to solve for a colour they already have in mind.
///
/// Every control writes to the same state and every other control re-derives
/// from it, so the sliders, the hex field and the preview can never disagree.
class ColorPickerPage extends StatefulWidget {
  const ColorPickerPage({this.initial, super.key});

  final int? initial;

  @override
  State<ColorPickerPage> createState() => _ColorPickerPageState();
}

class _ColorPickerPageState extends State<ColorPickerPage> {
  static const int _fallback = 0xFF1E88E5;

  late HsvColor _hsv;
  late final TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    final int start = widget.initial ?? _fallback;
    _hsv = hsvFromArgb(start);
    _hexController = TextEditingController(text: hexFromArgb(start));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  int get _argb => argbFromHsv(_hsv);

  void _setHsv(HsvColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexError = null;
      // Keep the text field in step, but only while the user is not editing it:
      // rewriting a field mid-typing would fight the cursor.
      if (!_hexController.selection.isValid ||
          _hexController.text == hexFromArgb(argbFromHsv(hsv))) {
        _hexController.text = hexFromArgb(argbFromHsv(hsv));
      }
    });
  }

  void _setArgb(int argb) {
    final HsvColor hsv = hsvFromArgb(argb);
    setState(() {
      // Keep the hue when the colour has none (black, white, grey): the sliders
      // would otherwise jump to 0° and the user would lose the hue they had.
      _hsv = HsvColor(
        hue: hsv.saturation == 0 ? _hsv.hue : hsv.hue,
        saturation: hsv.saturation,
        value: hsv.value,
      );
      _hexController.text = hexFromArgb(argb);
      _hexError = null;
    });
  }

  void _onHexChanged(String text) {
    final int? parsed = argbFromHex(text);
    if (parsed == null) {
      setState(() => _hexError = AppStrings.colorHexInvalid);
      return;
    }
    _setArgb(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final int argb = _argb;
    final Color selected = Color(argb);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.colorPickerTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: AppStrings.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(argb),
            child: const Text(AppStrings.cropApply),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: <Widget>[
          // Preview: the colour at the size it will actually be used, with the
          // hex written *in* it so contrast is judged the way the user will see
          // it rather than in the abstract.
          Container(
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected,
              borderRadius: AppShapes.radius(AppShapes.large),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              hexFromArgb(argb),
              style: text.titleMedium?.copyWith(
                color: Color(readableOn(argb)),
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 20),

          _GradientSlider(
            label: AppStrings.colorHue,
            value: _hsv.hue,
            max: 360,
            gradient: const <Color>[
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
            onChanged: (double value) =>
                _setHsv(HsvColor(hue: value, saturation: _hsv.saturation, value: _hsv.value)),
          ),
          _GradientSlider(
            label: AppStrings.colorSaturation,
            value: _hsv.saturation,
            max: 1,
            gradient: <Color>[
              Color(argbFromHsv(HsvColor(hue: _hsv.hue, saturation: 0, value: _hsv.value))),
              Color(argbFromHsv(HsvColor(hue: _hsv.hue, saturation: 1, value: _hsv.value))),
            ],
            onChanged: (double value) =>
                _setHsv(HsvColor(hue: _hsv.hue, saturation: value, value: _hsv.value)),
          ),
          _GradientSlider(
            label: AppStrings.colorBrightness,
            value: _hsv.value,
            max: 1,
            gradient: <Color>[
              const Color(0xFF000000),
              Color(argbFromHsv(HsvColor(hue: _hsv.hue, saturation: _hsv.saturation, value: 1))),
            ],
            onChanged: (double value) =>
                _setHsv(HsvColor(hue: _hsv.hue, saturation: _hsv.saturation, value: value)),
          ),

          const SizedBox(height: 8),
          TextField(
            controller: _hexController,
            onChanged: _onHexChanged,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: AppStrings.colorHexLabel,
              hintText: '#1E88E5',
              errorText: _hexError,
              prefixIcon: const Icon(Icons.tag),
            ),
          ),

          const SizedBox(height: 24),
          Text(AppStrings.colorCommon, style: text.labelLarge),
          const SizedBox(height: 10),
          _SwatchWrap(
            entries: kCommonColors,
            selected: argb,
            onTap: (int value) => _setArgb(value),
          ),
          const SizedBox(height: 18),
          Text(AppStrings.colorSoft, style: text.labelLarge),
          const SizedBox(height: 10),
          _SwatchWrap(
            entries: kSoftColors,
            selected: argb,
            onTap: (int value) => _setArgb(value),
          ),
        ],
      ),
    );
  }
}

/// A slider drawn over its own gradient, so the control previews what it does.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final List<Color> gradient;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label  ${(max == 1 ? value * 100 : value).round()}${max == 1 ? '%' : '°'}',
            style: text.labelLarge),
        Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(colors: gradient),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                overlayColor: Colors.black12,
              ),
              child: Slider(
                value: value.clamp(0, max),
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A wrapping row of colour swatches with the selected one ringed.
class _SwatchWrap extends StatelessWidget {
  const _SwatchWrap({
    required this.entries,
    required this.selected,
    required this.onTap,
  });

  final List<AppPaletteColor> entries;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (final AppPaletteColor entry in entries)
          Semantics(
            button: true,
            selected: entry.argb == selected,
            label: entry.label,
            child: Tooltip(
              message: entry.label,
              child: InkWell(
                onTap: () => onTap(entry.argb),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(entry.argb),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: entry.argb == selected
                          ? colors.primary
                          : colors.outlineVariant,
                      width: entry.argb == selected ? 3 : 1,
                    ),
                  ),
                  child: entry.argb == selected
                      ? Icon(Icons.check,
                          size: 18, color: Color(readableOn(entry.argb)))
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
