import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';
import '../utils/rules.dart';

/// The chips above the hand (J8 of the UX study): the plays [suggestPlays]
/// finds, "Paire de 7 · −14", "Q♠ seule · −12". A tap selects the chip's
/// cards through [onSelect]; they stay a selection like any other, changed
/// card by card. The chip whose cards are exactly the selection is filled.
///
/// Nothing is drawn when the hand makes no play worth offering.
class HandSuggestions extends StatelessWidget {
  const HandSuggestions({
    super.key,
    required this.suggestions,
    required this.selectedCards,
    required this.onSelect,
  });

  final List<PlaySuggestion> suggestions;
  final List<int> selectedCards;
  final ValueChanged<List<int>> onSelect;

  static Key chipKey(int index) => ValueKey('handSuggestion-$index');

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.gameSuggestions,
      // One line that scrolls sideways rather than wraps: on a phone the
      // hand's height is the felt's, and the cards need it more. A chip
      // wider than the line, at a large text size, wraps its own label.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const Key('handSuggestions'),
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, suggestion) in suggestions.indexed) ...[
                if (index > 0) const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: _SuggestionChip(
                    key: chipKey(index),
                    label: l10n.suggestionLabel(suggestion),
                    selected: suggestion.matches(selectedCards),
                    onTap: () => onSelect(suggestion.cards),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One suggestion: amber when its cards are the selection, outlined with
/// amber text otherwise — the look of the mockup.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: selected
          ? BorderSide.none
          : const BorderSide(color: AppColors.slate600),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.amber500 : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          // About 32 dp high, grown to its text at large sizes.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected ? AppColors.slate900 : AppColors.amber400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
