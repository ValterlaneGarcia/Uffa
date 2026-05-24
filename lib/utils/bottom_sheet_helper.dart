import 'package:flutter/material.dart';

import 'app_theme.dart';

extension BottomSheetHelper on BuildContext {
  Future<T?> showAppBottomSheet<T>({
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    double radius = 24,
  }) {
    return showModalBottomSheet<T>(
      context: this,
      backgroundColor: appSurface,
      isScrollControlled: isScrollControlled,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      ),
      builder: builder,
    );
  }
}
