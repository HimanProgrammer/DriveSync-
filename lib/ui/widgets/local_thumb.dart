import 'package:flutter/widgets.dart';

import 'local_thumb_web.dart' if (dart.library.io) 'local_thumb_io.dart';

/// A small preview of a local image file, or [fallback] if it can't be read.
Widget localThumb(String path, double size, Widget fallback) =>
    createLocalThumb(path, size, fallback);
