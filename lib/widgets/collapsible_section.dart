import 'package:flutter/material.dart';
import '../ui_themes/ui_theme_hooks.dart';

class CollapsibleSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final ColorScheme cs;
  final List<Widget> children;
  final bool isExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const CollapsibleSection({
    super.key,
    required this.icon,
    required this.title,
    required this.cs,
    required this.children,
    this.isExpanded = false,
    this.onExpansionChanged,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  final ExpansibleController _controller = ExpansibleController();
  bool _isBuilt = false;

  @override
  void didUpdateWidget(covariant CollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isBuilt && widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.expand();
      } else {
        _controller.collapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBuilt = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: lookPanelElevation(context, isDark ? 0 : 2),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: lookPanelColor(context, widget.cs.surfaceContainerHighest),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(lookRadius(context, 16)),
        side: lookPanelSide(context, isDark ? BorderSide(color: widget.cs.outlineVariant.withValues(alpha: 0.3)) : BorderSide.none),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _controller,
          initiallyExpanded: widget.isExpanded,
          onExpansionChanged: widget.onExpansionChanged,
          leading: Icon(widget.icon, color: widget.cs.primary, size: 22),
          title: Text(widget.title, style: TextStyle(fontWeight: FontWeight.w600)),
          childrenPadding: EdgeInsets.zero,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          children: widget.children,
        ),
      ),
    );
  }
}
