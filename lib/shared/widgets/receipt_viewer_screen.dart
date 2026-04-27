import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ReceiptViewerScreen extends StatefulWidget {
  final String url;
  const ReceiptViewerScreen({super.key, required this.url});

  @override
  State<ReceiptViewerScreen> createState() => _ReceiptViewerScreenState();
}

class _ReceiptViewerScreenState extends State<ReceiptViewerScreen> {
  bool _isSharing = false;

  Future<void> _shareOrDownload() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(widget.url));
      final response = await request.close();
      final bytes = await consolidateHttpClientResponseBytes(response);

      final dir = await getTemporaryDirectory();
      final filename = 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'إيصال',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تنزيل الإيصال')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('الإيصال', style: TextStyle(color: Colors.white)),
        actions: [
          if (_isSharing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              tooltip: 'مشاركة / تنزيل',
              onPressed: _shareOrDownload,
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            placeholder: (_, __) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}
