import 'dart:io';

import 'package:material_ui/material_ui.dart';

class BusinessIdentityHeader extends StatelessWidget {
  const BusinessIdentityHeader({super.key, required this.profile});

  final Map<String, String> profile;

  @override
  Widget build(BuildContext context) {
    final name = (profile['business_name'] ?? '').trim();
    final address = (profile['business_address'] ?? '').trim();
    final phone = (profile['business_phone'] ?? '').trim();
    final whatsapp = (profile['business_whatsapp'] ?? '').trim();
    final email = (profile['business_email'] ?? '').trim();
    final logoPath = (profile['business_logo_path'] ?? '').trim();
    final contact = [phone, whatsapp].where((value) => value.isNotEmpty).toSet().join(' • ');
    final details = [address, contact, email].where((value) => value.isNotEmpty).toList();
    if (name.isEmpty && details.isEmpty && logoPath.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasLogo = logoPath.isNotEmpty && File(logoPath).existsSync();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasLogo) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(logoPath),
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    for (final detail in details)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}
