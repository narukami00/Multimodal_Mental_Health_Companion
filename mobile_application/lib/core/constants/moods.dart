/// The mood words offered on a check-in.
///
/// One tap is a complete check-in: these are deliberately few, plain, and not
/// clinical. Shared so the text check-in and the one-word path cannot drift
/// apart.
abstract final class Moods {
  static const values = ['Steady', 'Bright', 'Tender', 'Wobbly', 'Quiet'];
}
