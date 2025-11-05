// File: lib/widgets/module_list_item.dart
import 'package:agent_windows/models/module_info.dart';
import 'package:flutter/material.dart';

class ModuleListItem extends StatelessWidget {
  final ModuleInfo module;
  final bool isSelected;
  final VoidCallback onTap;
  final String? searchQuery; // NOVO

  const ModuleListItem({
    super.key,
    required this.module,
    required this.isSelected,
    required this.onTap,
    this.searchQuery, // NOVO
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? module.color.withOpacity(0.25) 
              : theme.cardColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? module.color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // MELHORADO: Container ao redor do ícone
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: module.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(module.icon, color: module.color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    module.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // NOVO: Badge com o tipo
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          module.type.toUpperCase(),
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (module.description.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            module.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: module.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices, size: 12, color: module.color),
                  const SizedBox(width: 4),
                  Text(
                    '${module.assetCount}',
                    style: TextStyle(
                      color: module.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}