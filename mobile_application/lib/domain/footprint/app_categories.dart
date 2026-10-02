import '../../core/models/app_description.dart';
import '../../core/models/usage_event.dart';
import 'usage_day_reducer.dart';

/// The categories foreground time is grouped into. A short, fixed list: a long
/// one would turn "how the day was spent" into a ledger of the person's apps.
abstract final class AppCategory {
  static const social = 'social';
  static const messaging = 'messaging';
  static const video = 'video';
  static const games = 'games';
  static const productivity = 'productivity';
  static const other = 'other';

  static const all = [social, messaging, video, games, productivity, other];
}

/// Messaging apps, which Android files under "social" or nothing at all, so they
/// would otherwise be indistinguishable from feeds. Matched on package prefix.
///
/// Deliberately a small list of widely used apps rather than an attempt at
/// completeness: anything missing is grouped by the platform's category, or as
/// "other", which is a milder error than a wrong guess.
const _messagingPackages = [
  'com.whatsapp',
  'org.telegram.messenger',
  'org.thoughtcrime.securesms',
  'com.facebook.orca',
  'com.viber.voip',
  'com.imo.android',
  'com.google.android.apps.messaging',
  'com.samsung.android.messaging',
  'com.android.mms',
  'com.discord',
  'jp.naver.line.android',
  'com.snapchat.android',
  'com.skype.raider',
  'com.google.android.apps.dynamite',
];

/// Well-known feeds and video apps, matched on package prefix. They take
/// priority over the platform's label because app authors choose that label
/// themselves and it is often missing or generous: on a real device only about
/// half of the apps in use declared a category at all, and many declared
/// "productivity".
const _socialPackages = [
  'com.facebook.katana',
  'com.facebook.lite',
  'com.instagram.android',
  'com.twitter.android',
  'com.reddit.frontpage',
  'com.pinterest',
  'com.linkedin.android',
  'com.tumblr',
  'com.bumble.app',
  'com.tinder',
];

const _videoPackages = [
  'com.google.android.youtube',
  'com.zhiliaoapp.musically',
  'com.ss.android.ugc.trill',
  'com.netflix.mediaclient',
  'tv.twitch.android.app',
  'com.amazon.avod.thirdpartyclient',
  'com.disney.disneyplus',
  'com.hotstar',
  'in.startv.hotstar',
];

/// Builds the resolver the reducer uses, from what the platform said about each
/// app. An app with no description, or one Android hid, is "other".
///
/// Apps flagged to ignore (launcher, system UI, Solace itself) return null and
/// stay out of the totals.
CategoryResolver categoryResolverFor(Map<String, AppDescription> described) {
  return (package) {
    final description = described[package];
    if (description?.ignore == true) return null;
    if (_messagingPackages.any(package.startsWith)) {
      return AppCategory.messaging;
    }
    if (_socialPackages.any(package.startsWith)) return AppCategory.social;
    if (_videoPackages.any(package.startsWith)) return AppCategory.video;
    final platform = description?.category;
    if (platform != null && AppCategory.all.contains(platform)) {
      return platform;
    }
    return AppCategory.other;
  };
}

/// The packages in [events] that need describing, so the platform is asked once
/// per app rather than once per event.
Set<String> packagesIn(Iterable<UsageEvent> events) => {
  for (final event in events)
    if (event.package != null && event.package!.isNotEmpty) event.package!,
};
