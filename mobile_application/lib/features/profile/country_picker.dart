import 'package:flutter/material.dart';

import '../../core/models/country_resources.dart';
import '../../core/theme/app_theme.dart';
import 'profile_controller.dart';

/// Lets the person say where they are based, which decides the local emergency
/// number and listening line shown in Support. Shared by onboarding and
/// Settings; the choice is saved as soon as it is made.
class CountryPicker extends StatelessWidget {
  const CountryPicker({required this.controller, super.key});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.profile.countryCode;
        return Column(
          children: [
            for (final country in CountryResources.all) ...[
              _CountryTile(
                key: ValueKey('country-${country.code}'),
                country: country,
                selected: country.code == selected,
                onTap: () => controller.setCountry(country.code),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.country,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CountryResources country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = country.emergencyNumber == null
        ? 'Support will point to your local emergency number'
        : 'Emergency number ${country.emergencyNumber}';
    return Semantics(
      button: true,
      selected: selected,
      label: '${country.name}. $detail',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFFF1D6) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFB534)
                    : const Color(0xFFF2ECDD),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.amber : AppColors.mutedInk,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        country.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
