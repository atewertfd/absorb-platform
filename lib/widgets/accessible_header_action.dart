import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard and screen-reader behavior for the compact, custom page actions.
/// The supplied child keeps the page's existing visual design.
class AccessibleHeaderAction extends StatefulWidget {
  const AccessibleHeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  State<AccessibleHeaderAction> createState() => _AccessibleHeaderActionState();
}

class _AccessibleHeaderActionState extends State<AccessibleHeaderAction> {
  bool _showFocus = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _showFocus = value),
      onFocusChange: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        focusable: enabled,
        focused: _focused,
        label: widget.label,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: Tooltip(
          message: widget.label,
          excludeFromSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.onPressed,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: _showFocus && enabled
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
