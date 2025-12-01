import 'package:flutter/material.dart';

class NeonButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final Color color;
  final bool isLoading;

  const NeonButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.color = Colors.blue,
    this.isLoading = false,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final baseColor = isEnabled ? widget.color : Colors.grey;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: _isHovered ? baseColor.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? baseColor : baseColor.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: _isHovered && isEnabled
                ? [
                    BoxShadow(
                      color: baseColor.withOpacity(0.6),
                      blurRadius: 15,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: baseColor.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading) ...[
                 SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(baseColor),
                  ),
                ),
                const SizedBox(width: 12),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, color: baseColor, size: 20),
                const SizedBox(width: 12),
              ],
              Text(
                widget.text,
                style: TextStyle(
                  color: baseColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1.0,
                  shadows: _isHovered && isEnabled
                      ? [
                          Shadow(
                            color: baseColor,
                            blurRadius: 10,
                          )
                        ]
                      : [],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
