/// Only this coarse range is stored locally; no date of birth is collected.
enum AdAgeRange {
  under13('under_13', 'Under 13'),
  teens('13_to_15', '13–15'),
  older('16_plus', '16 or older');

  const AdAgeRange(this.storageValue, this.label);

  final String storageValue;
  final String label;

  // Until every mediated network supports restricted requests, younger players
  // play without ads. Unknown ages must also never initialize mediation.
  bool get allowsAds => this == older;
  bool get inMobiAgeRestricted => !allowsAds;

  static AdAgeRange? parse(String? value) {
    for (final range in values) {
      if (range.storageValue == value) return range;
    }
    return null;
  }
}
