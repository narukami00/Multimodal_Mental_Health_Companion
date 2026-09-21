import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/home/home_card_priority.dart';

void main() {
  test('home card priority follows the product specification', () {
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
        const HomeState(
          checkInEnabled: false,
          onboardingComplete: false,
        ),
      ),
      HomeCardType.onboarding,
    );
    expect(
      HomeCardPriority.select(
        const HomeState(
          checkInCompletedToday: true,
          suggestionDue: true,
        ),
      ),
      HomeCardType.suggestion,
    );
    expect(
      HomeCardPriority.select(
        const HomeState(checkInCompletedToday: true),
      ),
      HomeCardType.defaultAction,
    );
  });
}
