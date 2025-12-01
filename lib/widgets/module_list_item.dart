// File: lib/widgets/module_list_item.dart
import 'package:agent_windows/models/module_info.dart';
import 'package:agent_windows/widgets/app_card.dart';
import 'package:flutter/material.dart';

class ModuleListItem extends StatelessWidget {
  final ModuleInfo module;
  final bool isSelected;
  final VoidCallback onTap;
  final String? searchQuery;

  const ModuleListItem({
    super.key,
    required this.module,
    required this.isSelected,
    required this.onTap,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use a neutral color for selection in minimalist design, or the module color subtly
    final baseColor = isSelected ? const Color(0xFF2563EB) : const Color(0xFF71717A);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      backgroundColor: isSelected ? const Color(0xFF2563EB).withOpacity(0.1) : null,
      border: isSelected 
          ? Border.all(color: const Color(0xFF2563EB), width: 1)
          : null,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF27272A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              module.icon, 
              color: isSelected ? Colors.white : const Color(0xFFA1A1AA), 
              size: 24
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHighlightedText(
                  module.name,
                  searchQuery,
                  theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFAFAFA),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF27272A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF3F3F46)),
                      ),
                      child: Text(
                        module.type.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (module.description.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildHighlightedText(
                          module.description,
                          searchQuery,
                          theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF71717A),
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isSelected)
            const Icon(Icons.check_circle, color: Color(0xFF2563EB), size: 20)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF27272A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.devices, size: 12, color: Color(0xFFA1A1AA)),
                  const SizedBox(width: 4),
                  Text(
                    '${module.assetCount}',
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(
      String text, String? query, TextStyle? style,
      {int maxLines = 1}) {
    if (query == null || query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final spans = <TextSpan>[];
    int start = 0;
    int index = lowerText.indexOf(lowerQuery);

    while (index != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: style?.copyWith(
          backgroundColor: const Color(0xFFFEF08A).withOpacity(0.2), // Yellow 200
          color: const Color(0xFFFEF08A),
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}