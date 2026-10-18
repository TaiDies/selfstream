import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import 'palette.dart';
import 'widgets.dart';

/// Puts the user's picture behind the whole app (only for the "Colors + picture" theme).
class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final file = s.customPicture.isEmpty ? null : File(s.customPicture);
    if (s.themeId != 'picture' || file == null || !file.existsSync()) return child;
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: palette.light ? Colors.white : Colors.black),
      Image.file(file, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      ColoredBox(color: palette.bg.withValues(alpha: s.customDim)),
      child,
    ]);
  }
}

const List<Color> _swatches = [
  Color(0xFF1ED760), Color(0xFF5AA9FF), Color(0xFFB388FF), Color(0xFFFF8A3D), Color(0xFFFF5C8A), Color(0xFFFFD54F),
  Color(0xFF26C6DA), Color(0xFFEF5350), Color(0xFF9CCC65), Color(0xFFEC407A), Color(0xFF7E57C2), Color(0xFFFFFFFF),
];

/// Pick a colour (and optionally a picture) for the app. Changes show straight away.
class ThemeEditorScreen extends StatefulWidget {
  const ThemeEditorScreen({super.key});
  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  bool _busy = false;

  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildAll(context);
    });
  }

  void _mode(Settings s, String id) {
    s.themeId = id;
    _refresh();
  }

  void _accent(Settings s, Color c) {
    s.customAccent = c.toARGB32();
    if (s.themeId != 'custom' && s.themeId != 'picture') s.themeId = 'custom';
    _refresh();
  }

  Future<void> _pick(Settings s) async {
    setState(() => _busy = true);
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.image);
      final src = r?.files.single.path;
      if (src == null) return;
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}theme');
      await dir.create(recursive: true);
      final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '.jpg';
      final dest = File('${dir.path}${Platform.pathSeparator}background-${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(src).copy(dest.path);
      final old = s.customPicture;
      final color = await dominantColor(dest);
      if (color != null) s.customAccent = color.toARGB32();
      s.customPicture = dest.path;
      s.themeId = 'picture';
      if (old.isNotEmpty) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
      _refresh();
    } catch (e) {
      if (mounted) context.toast('Could not use that picture: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useColorsFromPicture(Settings s) async {
    final f = File(s.customPicture);
    if (!f.existsSync()) return;
    final c = await dominantColor(f);
    if (c == null || !mounted) return;
    s.customAccent = c.toARGB32();
    _refresh();
  }

  void _removePicture(Settings s) {
    final old = s.customPicture;
    s.customPicture = '';
    s.themeId = 'custom';
    if (old.isNotEmpty) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final withPicture = s.themeId == 'picture';
    final accent = Color(s.customAccent);
    final hue = HSVColor.fromColor(accent).hue;
    final pic = s.customPicture.isEmpty ? null : File(s.customPicture);
    final hasPic = pic != null && pic.existsSync();
    return PageFrame(
      title: 'Custom theme',
      miniPlayer: false,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'custom', icon: Icon(Icons.palette_outlined), label: Text('Colors')),
            ButtonSegment(value: 'picture', icon: Icon(Icons.image_outlined), label: Text('Colors + picture')),
          ],
          selected: {withPicture ? 'picture' : 'custom'},
          onSelectionChanged: (v) => _mode(s, v.first),
        ),
        const SizedBox(height: 20),
        Text('Color', style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in _swatches)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _accent(s, c),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: s.customAccent == c.toARGB32() ? kText : Colors.transparent, width: 2),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            trackShape: const _HueTrack(),
            thumbColor: kText,
          ),
          child: Slider(value: hue.clamp(0, 360), max: 360, onChanged: (v) => _accent(s, HSVColor.fromAHSV(1, v, 0.75, 0.95).toColor())),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Light mode'),
          subtitle: Text(withPicture ? 'Light panels over your picture' : 'Light background instead of dark'),
          value: s.customLight,
          onChanged: (v) {
            s.customLight = v;
            if (s.themeId != 'custom' && s.themeId != 'picture') s.themeId = 'custom';
            _refresh();
          },
        ),
        if (withPicture) ...[
          const Divider(height: 32),
          Text('Picture', style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (hasPic)
            ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 150, width: double.infinity, child: Image.file(pic, fit: BoxFit.cover)))
          else
            Container(
              height: 110,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12)),
              child: Text('No picture yet. Colors are used until you add one.', style: TextStyle(color: kMuted)),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _busy ? null : () => _pick(s), icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(hasPic ? 'Change picture' : 'Choose picture')),
            if (hasPic) OutlinedButton.icon(onPressed: () => _useColorsFromPicture(s), icon: const Icon(Icons.colorize), label: const Text('Colors from picture')),
            if (hasPic) TextButton(onPressed: () => _removePicture(s), child: const Text('Remove')),
          ]),
          const SizedBox(height: 16),
          Text('Darken picture', style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
          Slider(
            value: s.customDim,
            min: 0.3,
            max: 0.9,
            onChanged: (v) {
              s.customDim = v;
            },
          ),
          Text('The picture stays on this device. Darker is easier to read.', style: TextStyle(color: kMuted, fontSize: 12)),
        ],
      ]),
    );
  }
}

/// A rainbow bar for the colour slider.
class _HueTrack extends SliderTrackShape {
  const _HueTrack();

  @override
  Rect getPreferredRect({required RenderBox parentBox, Offset offset = Offset.zero, required SliderThemeData sliderTheme, bool isEnabled = false, bool isDiscrete = false}) {
    final h = sliderTheme.trackHeight ?? 10;
    return Rect.fromLTWH(offset.dx + 12, offset.dy + (parentBox.size.height - h) / 2, parentBox.size.width - 24, h);
  }

  @override
  void paint(PaintingContext context, Offset offset,
      {required RenderBox parentBox, required SliderThemeData sliderTheme, required Animation<double> enableAnimation, required Offset thumbCenter, Offset? secondaryOffset,
      bool isEnabled = false, bool isDiscrete = false, required TextDirection textDirection}) {
    final rect = getPreferredRect(parentBox: parentBox, offset: offset, sliderTheme: sliderTheme);
    final shader = LinearGradient(colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 0.75, 0.95).toColor()]).createShader(rect);
    context.canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), Paint()..shader = shader);
  }
}

/// The most noticeable colour in a picture, lightened or darkened so it reads well as an accent.
Future<Color?> dominantColor(File f) async {
  try {
    final Uint8List bytes = await f.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 48);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    // 24 hue buckets, each weighted by how colourful and bright its pixels are
    final weight = List<double>.filled(24, 0);
    final r = List<double>.filled(24, 0), g = List<double>.filled(24, 0), b = List<double>.filled(24, 0);
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      final hsv = HSVColor.fromColor(c);
      final w = hsv.saturation * hsv.value;
      if (w < 0.08) continue;
      final k = (hsv.hue / 15).floor().clamp(0, 23);
      weight[k] += w;
      r[k] += c.r * w;
      g[k] += c.g * w;
      b[k] += c.b * w;
    }
    var best = 0;
    for (var k = 1; k < 24; k++) {
      if (weight[k] > weight[best]) best = k;
    }
    if (weight[best] <= 0) return null;
    final avg = Color.from(alpha: 1, red: r[best] / weight[best], green: g[best] / weight[best], blue: b[best] / weight[best]);
    final hsl = HSLColor.fromColor(avg);
    return hsl.withSaturation(math.max(hsl.saturation, 0.55)).withLightness(hsl.lightness.clamp(0.5, 0.65)).toColor();
  } catch (_) {
    return null;
  }
}
