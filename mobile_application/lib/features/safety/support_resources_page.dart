import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/support_resource.dart';
import '../../core/theme/app_theme.dart';
import 'safety_controller.dart';
import 'support_resource_catalog.dart';

class SupportResourcesPage extends StatelessWidget {
  const SupportResourcesPage({
    required this.safetyController,
    this.assessment,
    this.regionCode = 'GLOBAL',
    super.key,
  });

  final SafetyController safetyController;
  final SafetyAssessment? assessment;
  final String regionCode;

  @override
  Widget build(BuildContext context) {
    final resources = SupportResourceCatalog.forRegion(regionCode);
    final isUrgent = assessment?.level == SafetyLevel.urgentSupport;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support resources'),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          children: [
            _SupportHero(isUrgent: isUrgent),
            const SizedBox(height: 20),
            Text('A few next steps', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final resource in resources) ...[
              _ResourceCard(resource: resource),
              const SizedBox(height: 10),
            ],
            if (SupportResourceCatalog.hasUnverifiedEntries(regionCode)) ...[
              const SizedBox(height: 8),
              Card(
                color: AppColors.amber.withValues(alpha: 0.13),
                child: const Padding(
                  padding: EdgeInsets.all(15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.deepAmber),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Regional contact details are not verified for external use yet. The project team must review local resources before launch.',
                          style: TextStyle(
                            color: AppColors.deepAmber,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () async {
                await safetyController.markSupportShown();
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Return to reflection'),
            ),
            const SizedBox(height: 8),
            const Text(
              'You remain in control. Solace does not notify anyone automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mutedInk,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportHero extends StatelessWidget {
  const _SupportHero({required this.isUrgent});

  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    final title = isUrgent
        ? 'You deserve support\nfrom a person right now.'
        : 'You do not have to\nhold this alone.';
    final body = isUrgent
        ? 'If you may act on thoughts of harm or cannot stay safe, move toward immediate human support now.'
        : 'It sounds like today may be carrying more than usual. These options are here without pressure or judgment.';

    return Card(
      color: isUrgent ? AppColors.coral : AppColors.amber,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isUrgent ? Icons.favorite_rounded : Icons.wb_sunny_rounded,
              color: isUrgent ? Colors.white : AppColors.deepAmber,
              size: 31,
            ),
            const SizedBox(height: 17),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: isUrgent ? Colors.white : AppColors.deepAmber,
                    height: 1.12,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isUrgent
                        ? Colors.white.withValues(alpha: 0.88)
                        : AppColors.deepAmber.withValues(alpha: 0.78),
                    height: 1.45,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.resource});

  final SupportResource resource;

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = switch (resource.kind) {
      SupportResourceKind.trustedPerson => (Icons.people_outline_rounded, AppColors.amber),
      SupportResourceKind.localEmergency => (Icons.location_on_outlined, AppColors.coral),
      SupportResourceKind.professionalSupport => (Icons.medical_services_outlined, AppColors.amber),
    };

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(icon, color: accent),
          ),
        ),
        title: Text(resource.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(resource.description),
        ),
        isThreeLine: true,
        trailing: resource.isVerified
            ? const Icon(Icons.check_circle_outline_rounded, color: AppColors.amber)
            : const Icon(Icons.pending_outlined, color: AppColors.coral),
      ),
    );
  }
}
