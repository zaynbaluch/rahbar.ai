import '../onboarding/onboarding_store.dart';

typedef OfflineAiStateReader = Future<OnboardingState> Function();

class OfflineAiDisabledException implements Exception {
  const OfflineAiDisabledException();

  @override
  String toString() => 'Offline AI is turned off in teacher setup.';
}

/// Central policy for optional local-model features.
class OfflineAiPolicy {
  OfflineAiPolicy({
    OnboardingStore? store,
    OfflineAiStateReader? readState,
  }) : _readState = readState ?? (store ?? OnboardingStore()).read;

  final OfflineAiStateReader _readState;

  Future<bool> isEnabled() async => (await _readState()).offlineAiEnabled;

  Future<void> requireEnabled() async {
    if (!await isEnabled()) throw const OfflineAiDisabledException();
  }
}
