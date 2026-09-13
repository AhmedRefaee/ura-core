import 'package:geolocator/geolocator.dart';
import '../logging/app_logger.dart';

class LocationFix {
  final double lat;
  final double lng;

  const LocationFix(this.lat, this.lng);
}

/// Abstract interface for capturing device location.
/// Never throws, never blocks indefinitely. Returns null when a fix can't
/// be obtained; the failure reason is logged internally, not surfaced to
/// the caller, so the action always proceeds (non-blocking / best-effort).
abstract class LocationCapture {
  const LocationCapture();

  /// Attempt to capture the device's current GPS location.
  /// Returns a LocationFix if successful, or null if location is unavailable
  /// (permission denied, service disabled, timeout, or any other error).
  /// The reason is logged.
  Future<LocationFix?> capture();
}

class GeolocatorLocationCapture implements LocationCapture {
  const GeolocatorLocationCapture();

  @override
  Future<LocationFix?> capture() async {
    try {
      // Check if location services are enabled at the OS level.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logger.w('GeolocatorLocationCapture: location services disabled');
        return null;
      }

      // Check current permission status and request if needed.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // First time: ask the user.
        permission = await Geolocator.requestPermission();
      }

      // If still denied or permanently denied, can't proceed.
      if (permission == LocationPermission.denied) {
        logger.w('GeolocatorLocationCapture: permission denied (once)');
        return null;
      }
      if (permission == LocationPermission.deniedForever) {
        logger.w('GeolocatorLocationCapture: permission denied forever');
        return null;
      }

      // Attempt to get a position with high accuracy, bounded by timeout.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      return LocationFix(position.latitude, position.longitude);
    } catch (e, st) {
      logger.e(
        'GeolocatorLocationCapture: capture failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}

/// Fake location capture for testing. Returns a fixed result or null.
class FakeLocationCapture implements LocationCapture {
  final LocationFix? _fixed;
  final List<LocationFix?> _script;
  int _scriptIndex = 0;

  /// Always return [fixed] on every call.
  FakeLocationCapture.fixed(this._fixed) : _script = [];

  /// Return results from [script] in order, cycling back to the start.
  FakeLocationCapture.script(this._script) : _fixed = null;

  @override
  Future<LocationFix?> capture() async {
    if (_fixed != null) return _fixed;
    if (_script.isEmpty) return null;
    final result = _script[_scriptIndex];
    _scriptIndex = (_scriptIndex + 1) % _script.length;
    return result;
  }
}
