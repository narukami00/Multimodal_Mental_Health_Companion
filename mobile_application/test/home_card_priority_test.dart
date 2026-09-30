import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/home/home_card_priority.dart';

void main() {
  group('primary card', () {
    test('follows the product specification', () {
      expect(
        HomeCardPriority.select(const HomeState(safetyFlagActive: true)),
        HomeCardType.support,
      );
      expect(
        HomeCardPriority.select(const HomeState()),
        HomeCardType.checkIn,
      );
      expect(
        HomeCardPriority.select(
          const HomeState(checkInEnabled: false, onboardingComplete: false),
        ),
        HomeCardType.onboarding,
      );
      expect(
        HomeCardPriority.select(const HomeState(checkInCompletedToday: true)),
        HomeCardType.defaultAction,
      );
    });

    test('someone who already checked in is not asked again', () {
      // The card used to be built without the real check-in state, so it asked
      // forever no matter how many times the user had already checked in.
      expect(
        HomeCardPriority.select(
          const HomeState(checkInCompletedToday: true),
        ),
        isNot(HomeCardType.checkIn),
      );
    });

    test('a due suggestion does not displace the primary card', () {
      // The suggestion has its own place below, so it no longer competes for
      // the top slot.
      expect(
        HomeCardPriority.select(
          const HomeState(checkInCompletedToday: true, suggestionDue: true),
        ),
        HomeCardType.defaultAction,
      );
    });
  });

  group('standing suggestion card', () {
    test('appears only when one is due', () {
      expect(
        HomeCardPriority.showSuggestion(
          const HomeState(suggestionDue: true, checkInCompletedToday: true),
        ),
        isTrue,
      );
      expect(HomeCardPriority.showSuggestion(const HomeState()), isFalse);
    });

    test('never appears alongside support resources', () {
      // When someone has raised a safety flag, an activity suggestion is not
      // what should be on screen.
      expect(
        HomeCardPriority.showSuggestion(
          const HomeState(safetyFlagActive: true, suggestionDue: true),
        ),
        isFalse,
      );
    });
  });
}
