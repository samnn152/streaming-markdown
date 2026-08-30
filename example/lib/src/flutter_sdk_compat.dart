import 'package:flutter/material.dart';

/// Uses Material 3 surface-container colors when the running Flutter SDK
/// exposes them, with equivalent tonal fallbacks for Flutter 3.10.
Color flutterSurfaceContainerHighest(ColorScheme colors) {
  try {
    return (colors as dynamic).surfaceContainerHighest as Color;
  } on NoSuchMethodError {
    return Color.alphaBlend(colors.onSurface.withAlpha(20), colors.surface);
  }
}

/// Uses the low Material 3 surface-container tone with a Flutter 3.10 fallback.
Color flutterSurfaceContainerLow(ColorScheme colors) {
  try {
    return (colors as dynamic).surfaceContainerLow as Color;
  } on NoSuchMethodError {
    return Color.alphaBlend(colors.onSurface.withAlpha(8), colors.surface);
  }
}
