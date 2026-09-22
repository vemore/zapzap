import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/create_party_provider.dart';
import '../utils/app_theme.dart';

/// A bot difficulty, localised; an unknown one (`ml`, `drl`) shows the
/// backend's own word.
String botDifficultyLabel(AppLocalizations l10n, String difficulty) =>
    switch (difficulty) {
      'easy' => l10n.botDifficultyEasy,
      'medium' => l10n.botDifficultyMedium,
      'hard' => l10n.botDifficultyHard,
      'hard_vince' => l10n.botDifficultyHardVince,
      'llm' => l10n.botDifficultyLlm,
      'thibot' => l10n.botDifficultyThibot,
      _ => difficulty,
    };

/// One configurable seat of a party being created: a human, or a bot of a
/// difficulty. A difficulty whose bots are all seated elsewhere is shown
/// disabled ("none available"), as in React (`CreateParty.jsx:235-273`).
class PlayerSlotSelector extends StatelessWidget {
  const PlayerSlotSelector({
    super.key,
    required this.index,
    required this.slot,
    required this.availableBots,
    required this.enabled,
    required this.onHuman,
    required this.onBot,
  });

  /// The seat's place among the configurable ones (0 is the second player).
  final int index;
  final PlayerSlot slot;

  /// How many bots of a difficulty this seat could take.
  final int Function(String difficulty) availableBots;

  final bool enabled;
  final VoidCallback onHuman;
  final void Function(String difficulty) onBot;

  static const _humanValue = 'human';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: Key('slot-$index'),
      color: AppColors.slate700,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(
              slot.isBot ? Icons.smart_toy : Icons.person,
              size: 18,
              color: slot.isBot ? AppColors.amber400 : AppColors.slate400,
            ),
            const SizedBox(width: 8),
            Text(l10n.createPartySlotLabel(index + 2)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                key: Key('slot-$index-type'),
                value: slot.isBot ? 'bot-${slot.difficulty}' : _humanValue,
                underline: const SizedBox.shrink(),
                isExpanded: true,
                alignment: Alignment.centerRight,
                onChanged: enabled
                    ? (value) {
                        if (value == null || value == _humanValue) {
                          onHuman();
                        } else {
                          onBot(value.substring('bot-'.length));
                        }
                      }
                    : null,
                items: [
                  DropdownMenuItem(
                    value: _humanValue,
                    child: Text(
                      l10n.createPartySlotHuman,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final difficulty in botDifficulties)
                    DropdownMenuItem(
                      value: 'bot-$difficulty',
                      enabled: availableBots(difficulty) > 0,
                      child: Text(
                        availableBots(difficulty) > 0
                            ? l10n.createPartySlotBot(
                                botDifficultyLabel(l10n, difficulty),
                              )
                            : l10n.createPartySlotBotUnavailable(
                                botDifficultyLabel(l10n, difficulty),
                              ),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: availableBots(difficulty) > 0
                              ? null
                              : AppColors.slate600,
                        ),
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
