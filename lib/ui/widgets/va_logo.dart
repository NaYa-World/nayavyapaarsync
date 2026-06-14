import 'package:flutter/material.dart';

class VALogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool isDark;

  const VALogo({
    super.key,
    this.size = 80,
    this.color,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final logoBgColor = isDark ? Colors.white : Colors.white.withValues(alpha: 0.18);
    final textColor = color ?? (isDark ? const Color(0xFF0F5132) : Colors.white);
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: logoBgColor,
        shape: BoxShape.circle,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
        border: Border.all(
          color: isDark ? const Color(0xFF0F5132).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.25),
          width: size * 0.03,
        ),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Styled VA Text
          Text(
            'VA',
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w900,
              color: textColor,
              letterSpacing: -size * 0.03,
              height: 1.0,
            ),
          ),
          // Small horizontal decorative line underneath VA
          Positioned(
            bottom: size * 0.22,
            child: Container(
              width: size * 0.35,
              height: size * 0.035,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(size * 0.01),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
