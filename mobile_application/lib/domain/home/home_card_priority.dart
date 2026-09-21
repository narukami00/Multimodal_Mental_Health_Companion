enum HomeCardType {
  support,
  checkIn,
  onboarding,
  suggestion,
  defaultAction,
}

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
  final bool suggestionDue;
}

abstract final class HomeCardPriority {
  static HomeCardType select(HomeState state) {
    if (state.safetyFlagActive) return HomeCardType.support;
    if (state.checkInEnabled && !state.checkInCompletedToday) {
      return HomeCardType.checkIn;
    }
    if (!state.onboardingComplete) return HomeCardType.onboarding;
    if (state.suggestionDue) return HomeCardType.suggestion;
    return HomeCardType.defaultAction;
  }
}
