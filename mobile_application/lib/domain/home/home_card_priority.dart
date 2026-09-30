enum HomeCardType { support, checkIn, onboarding, defaultAction }

class HomeState {
  const HomeState({
    this.safetyFlagActive = false,
    this.checkInEnabled = true,
    this.checkInCompletedToday = false,
    this.onboardingComplete = true,
    this.suggestionDue = false,
  });

  final bool safetyFlagActive;
  final bool checkInEnabled;
  final bool checkInCompletedToday;
  final bool onboardingComplete;

  /// Whether a gentle idea is due to be offered.
  ///
  /// Separate from the primary card: the suggestion now has its own place
  /// beneath whichever card is on top, rather than competing for that slot.
  final bool suggestionDue;
}

abstract final class HomeCardPriority {
  /// The single card at the top of Home.
  ///
  /// Still exactly one, deliberately. What changed is that the suggestion is no
  /// longer part of this contest — it sits below on its own.
  static HomeCardType select(HomeState state) {
    if (state.safetyFlagActive) return HomeCardType.support;
    if (state.checkInEnabled && !state.checkInCompletedToday) {
      return HomeCardType.checkIn;
    }
    if (!state.onboardingComplete) return HomeCardType.onboarding;
    return HomeCardType.defaultAction;
  }

  /// Whether the standing suggestion card should be shown at all.
  ///
  /// Never alongside support resources: when someone has raised a safety flag,
  /// an activity suggestion is not what they need on screen.
  static bool showSuggestion(HomeState state) {
    return state.suggestionDue && !state.safetyFlagActive;
  }
}
