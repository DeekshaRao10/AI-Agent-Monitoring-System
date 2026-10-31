import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class MedicalCard extends StatelessWidget {
  final String bloodGroup;
  final String medicalConditions;
  final String doctorPhone;
  final String address;

  const MedicalCard({
    super.key,
    required this.bloodGroup,
    required this.medicalConditions,
    required this.doctorPhone,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Medical Information",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),

            const SizedBox(height: 20),

            _infoTile(
              icon: Icons.bloodtype,
              title: "Blood Group",
              value: bloodGroup,
            ),

            const Divider(),

            _infoTile(
              icon: Icons.medical_services,
              title: "Medical Conditions",
              value: medicalConditions,
            ),

            const Divider(),

            _infoTile(
              icon: Icons.phone,
              title: "Doctor Phone",
              value: doctorPhone,
            ),

            const Divider(),

            _infoTile(
              icon: Icons.home,
              title: "Address",
              value: address,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: AppColors.primary,
      ),
      title: Text(title),
      subtitle: Text(
        value.isEmpty ? "Not Available" : value,
      ),
    );
  }
}