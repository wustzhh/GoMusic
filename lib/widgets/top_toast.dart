import 'dart:async';

import 'package:flutter/material.dart';

/// 顶部提示条：从顶部滑入，1.5秒后自动消失，不遮挡内容
void showTopToast(BuildContext context, String msg) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: MediaQuery.of(ctx).padding.top + 8,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(msg, style: const TextStyle(fontSize: 13, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(milliseconds: 1500), () {
    try {
      entry.remove();
    } catch (_) {}
  });
}
