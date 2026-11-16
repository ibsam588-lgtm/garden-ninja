import 'package:flutter/material.dart';
import 'package:garden_ninja/src/ads/ad_age_range.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves age before creating the game, which owns all ad initialization.
class AdAgeGate extends StatefulWidget {
  const AdAgeGate({
    required this.enabled,
    required this.onResolved,
    required this.child,
    super.key,
  });

  static const preferenceKey = 'garden_ninja_ad_age_range_v1';
  final bool enabled;
  final ValueChanged<AdAgeRange> onResolved;
  final Widget child;

  @override
  State<AdAgeGate> createState() => _AdAgeGateState();
}

class _AdAgeGateState extends State<AdAgeGate> {
  bool _loading = true;
  bool _resolved = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _load();
  }

  Future<void> _load() async {
    AdAgeRange? range;
    try {
      final prefs = await SharedPreferences.getInstance();
      range = AdAgeRange.parse(prefs.getString(AdAgeGate.preferenceKey));
    } catch (_) {
      // An unavailable or malformed preference never defaults to an older age.
    }
    if (!mounted) return;
    if (range != null) widget.onResolved(range);
    setState(() {
      _loading = false;
      _resolved = range != null;
    });
  }

  Future<void> _select(AdAgeRange range) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(AdAgeGate.preferenceKey, range.storageValue)) {
        throw StateError('Age range could not be saved');
      }
      if (!mounted) return;
      widget.onResolved(range);
      setState(() => _resolved = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your choice. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _resolved) return widget.child;
    return Scaffold(
      backgroundColor: const Color(0xFF173724),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.eco_rounded,
                          size: 52,
                          color: Color(0xFFDFFF8A),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Before you play',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Choose your age range.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This helps us set your privacy choices. Your age '
                          'range stays on this device. We do not ask for your birthday.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFD6E6D7),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        for (final range in AdAgeRange.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: OutlinedButton(
                              key: ValueKey('age-${range.storageValue}'),
                              onPressed: _saving ? null : () => _select(range),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFF8DBB80),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                              ),
                              child: Text(
                                range.label,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        if (_saving)
                          const Center(child: CircularProgressIndicator()),
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
