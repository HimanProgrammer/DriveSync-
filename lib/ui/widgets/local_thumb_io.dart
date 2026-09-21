import 'dart:io';

import 'package:flutter/widgets.dart';

Widget createLocalThumb(String path, double size, Widget fallback) =>
    Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      // Decode at thumbnail size so a folder of 20 MB photos stays light.
      cacheWidth: (size * 2).round(),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
