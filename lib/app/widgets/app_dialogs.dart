import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_message.dart';

abstract final class AppDialogs {
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String initialValue = '',
    bool multiline = false,
    bool obscureText = false,
    String? hint,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: multiline ? 640 : 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              obscureText: obscureText,
              enableSuggestions: !obscureText,
              autocorrect: !obscureText,
              minLines: multiline ? 10 : 1,
              maxLines: multiline ? 20 : 1,
              style: multiline
                  ? const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13)
                  : null,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: multiline
                  ? null
                  : (value) => Navigator.pop(context, value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text('save'.tr),
            ),
          ],
        ),
      );
    } finally {
      // The route owns its text field until its closing animation completes.
      await Future<void>.delayed(
        const Duration(milliseconds: 400),
        controller.dispose,
      );
    }
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('confirm'.tr),
            ),
          ],
        ),
      ) ??
      false;
}

void showAppError(BuildContext context, Object error) {
  AppMessage.error(context, error);
}
