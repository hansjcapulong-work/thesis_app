import 'package:flutter/material.dart';

/// One selectable avatar. Every avatar GLB shares the same 41-bone rig and
/// carries the same 182 `Anim_*` sign clips, so [assetPath] is the only thing
/// that differs when the user switches -- the sign data (ASLWord.signAnimation)
/// works unchanged on any of them.
class AvatarOption {
  final String id;
  final String label;
  final String assetPath;

  /// Portrait shown in the Settings picker (see assets/avatar_previews/).
  final String previewAsset;
  final IconData icon;
  final Color accent;

  const AvatarOption({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.previewAsset,
    required this.icon,
    required this.accent,
  });
}

const String kDefaultAvatarId = 'male1';

/// Must match the files declared under `assets:` in pubspec.yaml.
const List<AvatarOption> kAvatarOptions = [
  AvatarOption(
    id: 'male1',
    label: 'Male 1',
    assetPath: 'assets/model/Male1.glb',
    previewAsset: 'assets/avatar_previews/male1.png',
    icon: Icons.man,
    accent: Color(0xFF6D4C41),
  ),
  AvatarOption(
    id: 'male2',
    label: 'Male 2',
    assetPath: 'assets/model/Male2.glb',
    previewAsset: 'assets/avatar_previews/male2.png',
    icon: Icons.man_2,
    accent: Color(0xFF3F6FA8),
  ),
  AvatarOption(
    id: 'female1',
    label: 'Female 1',
    assetPath: 'assets/model/Female1.glb',
    previewAsset: 'assets/avatar_previews/female1.png',
    icon: Icons.woman,
    accent: Color(0xFF8E3B6E),
  ),
  AvatarOption(
    id: 'female2',
    label: 'Female 2',
    assetPath: 'assets/model/Female2.glb',
    previewAsset: 'assets/avatar_previews/female2.png',
    icon: Icons.woman_2,
    accent: Color(0xFFB5651D),
  ),
];

/// Looks an avatar up by id, falling back to the default so a stale or
/// unknown saved value can never leave the viewer without a model.
AvatarOption avatarById(String? id) {
  return kAvatarOptions.firstWhere(
    (a) => a.id == id,
    orElse: () => kAvatarOptions.firstWhere((a) => a.id == kDefaultAvatarId),
  );
}
