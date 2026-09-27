import 'package:shared_preferences/shared_preferences.dart';

/// Whether the example game was offered already: the first opening of the
/// app offers it once (`TutorialOffer`), whatever the answer.
abstract class TutorialOfferStore {
  Future<bool> wasOffered();
  Future<void> markOffered();
}

/// The device's: a `tutorialOffered` flag in `shared_preferences` (the
/// browser's localStorage on the web).
class PreferencesTutorialOfferStore implements TutorialOfferStore {
  static const key = 'tutorialOffered';

  @override
  Future<bool> wasOffered() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  @override
  Future<void> markOffered() async =>
      (await SharedPreferences.getInstance()).setBool(key, true);
}
