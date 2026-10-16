import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:ffi/ffi.dart';

/// Paints the Windows title bar in the app's colours (Windows 11; older versions keep the normal bar).
class TitleBar {
  static int _lastKey = -1;

  static void apply(Color background, Color text, {required bool light}) {
    if (!Platform.isWindows) return;
    final key = Object.hash(background.toARGB32(), text.toARGB32(), light);
    if (key == _lastKey) return;
    try {
      final user = DynamicLibrary.open('user32.dll');
      final dwm = DynamicLibrary.open('dwmapi.dll');
      final findWindow = user.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      final setAttr = dwm.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer<Uint32>, Uint32),
          int Function(int, int, Pointer<Uint32>, int)>('DwmSetWindowAttribute');
      final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = findWindow(cls, nullptr);
      calloc.free(cls);
      if (hwnd == 0) {
        Future<void>.delayed(const Duration(seconds: 1), () => apply(background, text, light: light));
        return;
      }
      final v = calloc<Uint32>();
      void set(int attr, int value) {
        v.value = value;
        setAttr(hwnd, attr, v, 4);
      }

      int colorRef(Color c) => ((c.b * 255).round() << 16) | ((c.g * 255).round() << 8) | (c.r * 255).round();
      set(20, light ? 0 : 1); // DWMWA_USE_IMMERSIVE_DARK_MODE, so the buttons match
      set(35, colorRef(background)); // DWMWA_CAPTION_COLOR
      set(36, colorRef(text)); // DWMWA_TEXT_COLOR
      set(34, colorRef(background)); // DWMWA_BORDER_COLOR
      calloc.free(v);
      _lastKey = key;
    } catch (_) {}
  }
}
