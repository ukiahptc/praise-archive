import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/key_utils.dart';

/// 작은 키 배지 (목록에서 사용)
class KeyChipMini extends StatelessWidget {
  final String musicKey;
  final bool highlighted;
  const KeyChipMini({
    super.key,
    required this.musicKey,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.brass : AppColors.brassSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        prettyKey(musicKey),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: highlighted ? Colors.white : AppColors.brassDeep,
        ),
      ),
    );
  }
}
