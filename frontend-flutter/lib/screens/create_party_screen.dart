import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/create_party_provider.dart';
import '../providers/party_provider.dart';
import '../repositories/party_repository.dart';
import '../router.dart';
import '../utils/app_theme.dart';
import '../utils/navigation.dart';
import '../widgets/error_banner.dart';
import '../widgets/player_slot_selector.dart';
import '../widgets/zapzap_app_bar.dart';

/// The create-party form (`CreateParty.jsx`): a name, the number of seats,
/// the visibility, and one selector per seat — a human, or a bot of a
/// difficulty. The creator always holds the first seat.
class CreatePartyScreen extends StatefulWidget {
  const CreatePartyScreen({super.key});

  @override
  State<CreatePartyScreen> createState() => _CreatePartyScreenState();
}

class _CreatePartyScreenState extends State<CreatePartyScreen> {
  late final CreatePartyProvider _create;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _create = CreatePartyProvider(context.read<PartyRepository>())..loadBots();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _create.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final partyId = await _create.submit(_name.text);
    // The lobby takes the form's place: Back from it returns to the list,
    // not to a form whose party already exists.
    if (partyId != null && mounted) {
      context.pushReplacement(AppRoutes.partyPath(partyId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    // Node refuses a name outside 3-50 characters with a generic 500
    // (`src/use-cases/party/CreateParty.js:47-53`): refuse it here instead.
    final named = name.length >= partyNameMinLength;
    final nameError = name.isEmpty
        ? l10n.createPartyNameRequired
        : name.length < partyNameMinLength
        ? l10n.createPartyNameTooShort(partyNameMinLength)
        : null;
    return Scaffold(
      appBar: ZapZapAppBar(
        title: l10n.createPartyTitle,
        leading: IconButton(
          key: const Key('back-to-parties'),
          tooltip: l10n.lobbyBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(AppRoutes.parties),
        ),
      ),
      body: ListenableBuilder(
        listenable: _create,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('party-name'),
              controller: _name,
              enabled: !_create.busy,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.createPartyNameLabel,
                hintText: l10n.createPartyNameHint,
                border: const OutlineInputBorder(),
                errorText: nameError,
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(partyNameMaxLength),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: const Key('player-count'),
              initialValue: _create.playerCount,
              decoration: InputDecoration(
                labelText: l10n.createPartyPlayerCountLabel,
                helperText: l10n.createPartyPlayerCountHelper(
                  minPartyPlayers,
                  maxPartyPlayers,
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: _create.busy
                  ? null
                  : (value) {
                      if (value != null) _create.setPlayerCount(value);
                    },
              items: [
                for (
                  var count = minPartyPlayers;
                  count <= maxPartyPlayers;
                  count++
                )
                  DropdownMenuItem(value: count, child: Text('$count')),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('visibility'),
              initialValue: _create.visibility,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.createPartyVisibilityLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: _create.busy
                  ? null
                  : (value) {
                      if (value != null) _create.setVisibility(value);
                    },
              items: [
                DropdownMenuItem(
                  value: 'public',
                  child: Text(l10n.createPartyVisibilityPublic),
                ),
                DropdownMenuItem(
                  value: 'private',
                  child: Text(l10n.createPartyVisibilityPrivate),
                ),
              ],
              // The options explain themselves in full in the menu; closed,
              // the field only has one line.
              selectedItemBuilder: (context) => [
                Text(
                  l10n.createPartyVisibilityPublic,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.createPartyVisibilityPrivate,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              l10n.createPartySlotsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              color: AppColors.slate700,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.amber400),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.person, color: AppColors.amber400),
                title: Text(l10n.createPartySlotOwner),
                trailing: Text(
                  l10n.createPartyOwnerBadge,
                  style: const TextStyle(color: AppColors.amber400),
                ),
              ),
            ),
            for (var index = 0; index < _create.slots.length; index++)
              PlayerSlotSelector(
                index: index,
                slot: _create.slots[index],
                enabled: !_create.busy,
                availableBots: (difficulty) =>
                    _create.availableBots(index, difficulty),
                onHuman: () => _create.setSlotHuman(index),
                onBot: (difficulty) => _create.setSlotBot(index, difficulty),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.createPartySummary(_create.humanCount, _create.botCount),
              style: const TextStyle(color: AppColors.slate400),
            ),
            if (_create.error != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(message: partyErrorText(l10n, _create.error!)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('create-submit'),
              onPressed: named && !_create.busy ? _submit : null,
              child: Text(
                _create.busy
                    ? l10n.createPartySubmitting
                    : l10n.createPartySubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
