import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_spacing.dart';
import '../utils/context_ext.dart';
import '../utils/device.dart';

/// Thumbnail of a picked file (works on mobile and web).
class PickedThumb extends StatelessWidget {
  const PickedThumb({super.key, required this.file, this.size = 72, this.onRemove});

  final XFile file;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: AppRadius.fieldRadius,
          child: FutureBuilder<Uint8List>(
            future: file.readAsBytes(),
            builder: (_, snap) => snap.hasData
                ? Image.memory(snap.data!, width: size, height: size, fit: BoxFit.cover)
                : Container(width: size, height: size, color: context.palette.surfaceAlt),
          ),
        ),
        if (onRemove != null)
          PositionedDirectional(
            top: 2,
            end: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54,
                  child: Icon(Icons.close_rounded, size: 14, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

/// Row of picked photos with an "add" tile.
class PhotoPickerRow extends StatelessWidget {
  const PhotoPickerRow({super.key, required this.photos, required this.onChanged, this.max = 3});

  final List<XFile> photos;
  final ValueChanged<List<XFile>> onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final p in photos) PickedThumb(file: p, onRemove: () => onChanged([...photos]..remove(p))),
        if (photos.length < max)
          InkWell(
            onTap: () async {
              final picked = await Device.pickImage(context);
              if (picked != null) onChanged([...photos, picked]);
            },
            borderRadius: AppRadius.fieldRadius,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(border: Border.all(color: context.palette.border), borderRadius: AppRadius.fieldRadius),
              child: Icon(Icons.add_a_photo_outlined, color: context.palette.textMuted),
            ),
          ),
      ],
    );
  }
}
