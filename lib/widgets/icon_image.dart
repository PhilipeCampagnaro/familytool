import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// An icon asset at a bounded decode size. The shop logos are full-size
/// downloads and the picker puts 160 of them on screen at once; without
/// `cacheWidth` every one of them is decoded at its native resolution.
class IconImage extends StatelessWidget {
  final String asset;
  final double size;

  const IconImage({super.key, required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: (size * scale).round(),
      // A logo that was deleted from `assets/` shouldn't take the row with it.
      errorBuilder: (context, _, _) => AppIcon(AppIcons.image, size: size * 0.8, color: AppColors.mutedLight),
    );
  }
}
