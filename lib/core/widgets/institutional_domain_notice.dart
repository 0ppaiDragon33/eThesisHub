import 'package:flutter/material.dart';

import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// Shown only while [AppConfig.enforceInstitutionalDomain] is false.
///
/// The domain restriction is the whole self-registration defence the
/// manuscript describes, and it gets relaxed during testing because there
/// are not enough institutional addresses to sign in as all five roles at
/// once. It has been relaxed before and had to be remembered later.
///
/// So it says so on the screen where it has an effect. Nobody demonstrates
/// this system without seeing that registration is currently open, and
/// turning it back on makes this disappear with no other change.
class InstitutionalDomainNotice extends StatelessWidget {
  const InstitutionalDomainNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.enforceInstitutionalDomain) return const SizedBox.shrink();

    return Container(
      key: const Key('domainEnforcementOff'),
      margin: const EdgeInsets.only(bottom: AppTokens.md),
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: AppTokens.awaiting.withValues(alpha: 0.10),
        border: Border.all(color: AppTokens.awaiting.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined,
              size: 20, color: AppTokens.awaiting),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              'Testing mode: registration is open to any email address. '
              'Normally only ${AppConfig.institutionalDomain} accounts may '
              'register.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTokens.awaiting),
            ),
          ),
        ],
      ),
    );
  }
}
