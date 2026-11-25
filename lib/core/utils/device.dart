import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'context_ext.dart';

/// Phone calls, sharing and photo picking.
class Device {
  Device._();

  static Future<void> call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {}
    if (context.mounted) context.showSnack('Calling is not available on this device ($phone)');
  }

  static Future<void> share(BuildContext context, String text, {String? subject}) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    } catch (_) {
      if (context.mounted) context.showSnack('Sharing is not available on this device');
    }
  }

  /// Lets the user take or choose a photo. Returns null when cancelled.
  static Future<XFile?> pickImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    try {
      return await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    } catch (_) {
      if (context.mounted) context.showSnack('Could not access the ${source == ImageSource.camera ? 'camera' : 'gallery'}');
      return null;
    }
  }
}
