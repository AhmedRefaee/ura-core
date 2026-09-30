import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/logging/app_logger.dart';

/// Tappable widget showing a location pin + "عرض الموقع" text,
/// opening Google Maps to the specified coordinates.
class LocationLink extends StatelessWidget {
  final double lat;
  final double lng;

  const LocationLink({
    super.key,
    required this.lat,
    required this.lng,
  });

  Future<void> _openMaps() async {
    final query = '$lat,$lng';
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        logger.e('LocationLink: cannot launch $url');
      }
    } catch (e, st) {
      logger.e('LocationLink: launch failed', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openMaps,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: 18, color: Theme.of(context).primaryColor),
          const SizedBox(width: 6),
          Text(
            'عرض الموقع',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
