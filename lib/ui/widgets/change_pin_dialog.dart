// lib/ui/widgets/change_pin_dialog.dart — Shared PIN Change Dialog
//
// Extracted from auth_screen.dart for reuse in both lock screen and settings.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';

/// Show the "Change PIN" dialog. Returns true if PIN was changed.
Future<bool?> showChangePinDialog(BuildContext context, AuthService authService) {
  final oldPinController = TextEditingController();
  final newPinController = TextEditingController();
  final confirmPinController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Change PIN'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: oldPinController,
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                hintText: 'Enter current 4-digit PIN',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              maxLength: 4,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.length != 4) return 'Enter 4 digits';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: newPinController,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                hintText: 'Enter new 4-digit PIN',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              maxLength: 4,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.length != 4) return 'Enter 4 digits';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirmPinController,
              decoration: const InputDecoration(
                labelText: 'Confirm New PIN',
                hintText: 'Re-enter new PIN',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 4,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v != newPinController.text) return 'PINs do not match';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;

            final oldPinValid = await authService.verifyPin(oldPinController.text);
            if (!oldPinValid && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Current PIN is incorrect')),
              );
              return;
            }

            await authService.setPin(newPinController.text);
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
          child: const Text('Change PIN'),
        ),
      ],
    ),
  );
}
