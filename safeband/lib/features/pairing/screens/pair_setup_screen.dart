import 'package:flutter/material.dart';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/services/local_photo_store.dart';
import '../../bands/screens/dashboard_screen.dart';
import '../../bands/services/band_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/bluetooth_device_manager.dart';
import '../services/wifi_scan_service.dart';


class PairSetupScreen extends StatefulWidget {
  final String deviceId;

  const PairSetupScreen({
    super.key,
    required this.deviceId,
  });

  @override
  State<PairSetupScreen> createState() =>
      _PairSetupScreenState();
}
class _PairSetupScreenState
    extends State<PairSetupScreen> {

  String selectedWearer = "";

  bool showProfileForm = false;

  String? selectedBloodGroup;

  File? profileImage;

  List<String> wifiNetworks = [];

  String? selectedWifi;

  final ImagePicker picker =
      ImagePicker();

  final wifiController =
      TextEditingController();

  final wifiPasswordController =
      TextEditingController();

  final fullNameController =
      TextEditingController();

  final ageController =
      TextEditingController();

  final emailController =
      TextEditingController();

  final userPasswordController =
      TextEditingController();

  final addressController =
      TextEditingController();

  final medicalController =
      TextEditingController();

  final doctorPhoneController =
      TextEditingController();

  final bandNameController =
      TextEditingController();

@override
void initState() {
  super.initState();

  loadWifiNetworks();
}

Future<void> pickProfileImage() async {
  final XFile? image =
      await picker.pickImage(
    source: ImageSource.gallery,
  );
   if (image != null) {
    setState(() {
      profileImage =
          File(image.path);
    });
  }
}
Future<void> loadWifiNetworks() async {

  final device =
      BluetoothDeviceManager
          .connectedDevice;

  if (device == null) return;

  final wifiList =
      await WifiScanService()
          .getWifiList(device);

setState(() {
  wifiNetworks = wifiList
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  if (!wifiNetworks.contains(selectedWifi)) {
    selectedWifi = null;
  }
});
}

Future<void> finishSetup() async {
print("Finish Setup pressed");
  
  if (selectedWifi == null ||
      wifiPasswordController.text.trim().isEmpty ||
      fullNameController.text.trim().isEmpty ||
      ageController.text.trim().isEmpty ||
      addressController.text.trim().isEmpty ||
      selectedBloodGroup == null ||
      medicalController.text.trim().isEmpty ||
      doctorPhoneController.text.trim().isEmpty ||
      bandNameController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Required field is missing"),
      ),
    );
    return;
  }

  // Additional validation for "New Profile"

  if (selectedWearer == "new") {
    if (emailController.text.trim().isEmpty ||
        userPasswordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Wearer email and password are required",
          ),
        ),
      );
      return;
    }
  }

  final device = BluetoothDeviceManager.connectedDevice;

  if (device == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Band not connected"),
      ),
    );
    return;
  }

 try {
  // STEP 1: Create the band and Firebase user first
  String wearerUid;

  if (selectedWearer == "new") {
    debugPrint("Creating band...");

    wearerUid = await BandService().createBand(
      deviceId: widget.deviceId,
      bandName: bandNameController.text.trim(),
      wearerName: fullNameController.text.trim(),
      age: int.parse(ageController.text.trim()),
      address: addressController.text.trim(),
      bloodGroup: selectedBloodGroup!,
      medicalConditions: medicalController.text.trim(),
      doctorPhone: doctorPhoneController.text.trim(),
      wearerEmail: emailController.text.trim(),
      wearerPassword: userPasswordController.text.trim(),
    );
  } else {
    wearerUid = await BandService().createBand(
      deviceId: widget.deviceId,
      bandName: bandNameController.text.trim(),
      wearerName: fullNameController.text.trim(),
      age: int.parse(ageController.text.trim()),
      address: addressController.text.trim(),
      bloodGroup: selectedBloodGroup!,
      medicalConditions: medicalController.text.trim(),
      doctorPhone: doctorPhoneController.text.trim(),
    );
  }

  debugPrint("Band created successfully.");


  if (profileImage != null) {
    try {
      await LocalPhotoStore.savePhoto(wearerUid, profileImage!);
      debugPrint("Profile photo saved for wearerUid=$wearerUid");
    } catch (e) {
      debugPrint("Failed to save profile photo: $e");
      
    }
  }

  // STEP 2: Send WiFi credentials to ESP32
  
  bool sent = await WifiScanService().sendWifiCredentials(
    device,
    selectedWifi!,
    wifiPasswordController.text.trim(),
    emailController.text.trim(),
    userPasswordController.text.trim(),
    widget.deviceId,
  );

  if (!sent) {
    throw Exception("Failed to send WiFi credentials");
  }

  if (!mounted) return;

  // STEP 3: Go to Dashboard
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => const DashboardScreen(),
    ),
  );
} catch (e) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        e.toString().replaceFirst("Exception: ", ""),
      ),
    ),
  );
}
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          AppColors.background,

      appBar: AppBar(
        title: const Text("Setup"),
        backgroundColor:
            AppColors.background,
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [

            const SizedBox(height: 10),

            Center(
  child: Column(
    children: [
      CircleAvatar(
        radius: 40,
        backgroundColor:
            AppColors.primary.withOpacity(.15),
        child: const Icon(
          Icons.watch,
          size: 40,
          color: AppColors.primary,
        ),
      ),

      const SizedBox(height: 15),

      const Text(
        "Band online!",
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 8),

      const Text(
        "Your band is connected. Let's finish setting it up.",
        textAlign: TextAlign.center,
      ),
    ],
  ),
),

const SizedBox(height: 30),

// NETWORK SETTINGS

Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          "📶 Network Settings",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 15),


DropdownButtonFormField<String>(
  value: selectedWifi,
hint: const Text("Select WiFi"),
  decoration: const InputDecoration(
    labelText: "Select WiFi",
    border: OutlineInputBorder(),
    prefixIcon: Icon(Icons.wifi),
  ),
  items: wifiNetworks.map((wifi) {
    return DropdownMenuItem(
      value: wifi,
      child: Text(wifi),
    );
  }).toList(),
  onChanged: (value) {
    setState(() {
      selectedWifi = value;
    });
  },
),    const SizedBox(height: 12),

        AppTextField(
          controller: wifiPasswordController,
          obscureText: true,
          labelText: "Password *",
        ),
      ],
    ),
  ),
),

const SizedBox(height: 20),

// WHO WEARS THIS BAND

Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [

        const Text(
          "Who wears this band?",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 15),

        Row(
  children: [

    GestureDetector(
      onTap: () {
        setState(() {
          selectedWearer = "user";
          showProfileForm = true;
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color:
              selectedWearer == "user"
                  ? AppColors.primary
                  : AppColors.white,
          borderRadius:
              BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary,
          ),
        ),
        child: Text(
          "You",
          style: TextStyle(
            color:
                selectedWearer == "user"
                    ? AppColors.textOnColor
                    : AppColors.black,
          ),
        ),
      ),
    ),

    const SizedBox(width: 12),

    GestureDetector(
      onTap: () {
        setState(() {
          selectedWearer = "new";
          showProfileForm = true;
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color:
              selectedWearer == "new"
                  ? AppColors.primary
                  : AppColors.white,
          borderRadius:
              BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary,
          ),
        ),
        child: Text(
          "+ New Profile",
          style: TextStyle(
            color:
                selectedWearer == "new"
                    ? AppColors.textOnColor
                    : AppColors.black,
          ),
        ),
      ),
    ),
  ],
),

      ],
    ),
  ),
),

if (showProfileForm) ...[

  const SizedBox(height: 20),

  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [

          CircleAvatar(
  radius: 40,
  backgroundColor: AppColors.grey.shade200,
  backgroundImage:
      profileImage != null
          ? FileImage(profileImage!)
          : null,
  child: profileImage == null
      ? const Icon(
          Icons.person,
          size: 40,
        )
      : null,
),
          const SizedBox(width: 20),

Expanded(
  child: PrimaryButton(
    text: "Upload Profile",
    icon: Icons.upload,
    outlined: true,
    foregroundColor: AppColors.primary,
    onPressed: pickProfileImage,
  ),
),
        ],
      ),
    ),
  ),

  const SizedBox(height: 20),

  AppTextField(
    controller: fullNameController,
    labelText: "Full Name *",
  ),

  const SizedBox(height: 12),

  AppTextField(
    controller: ageController,
    keyboardType: TextInputType.number,
    labelText: "Age *",
  ),

  const SizedBox(height: 12),

  if (selectedWearer == "new") ...[

    AppTextField(
      controller: emailController,
      labelText: "Email *",
    ),

    const SizedBox(height: 12),

    AppTextField(
      controller: userPasswordController,
      obscureText: true,
      labelText: "Password *",
    ),

    const SizedBox(height: 12),
  ],

  AppTextField(
    controller: addressController,
    maxLines: 2,
    labelText: "Home Address *",
  ),
],


           const SizedBox(height: 20),

// MEDICAL CARD

Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [

        const Text(
          "🩺 Medical Card",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 15),

        DropdownButtonFormField<String>(
          value: selectedBloodGroup,
          decoration:
              const InputDecoration(
            labelText: "* Blood Group",
            border:
                OutlineInputBorder(),
          ),
          items: const [

            DropdownMenuItem(
              value: "A+",
              child: Text("A+"),
            ),

            DropdownMenuItem(
              value: "A-",
              child: Text("A-"),
            ),

            DropdownMenuItem(
              value: "B+",
              child: Text("B+"),
            ),

            DropdownMenuItem(
              value: "B-",
              child: Text("B-"),
            ),

            DropdownMenuItem(
              value: "AB+",
              child: Text("AB+"),
            ),

            DropdownMenuItem(
              value: "AB-",
              child: Text("AB-"),
            ),

            DropdownMenuItem(
              value: "O+",
              child: Text("O+"),
            ),

            DropdownMenuItem(
              value: "O-",
              child: Text("O-"),
            ),
          ],
          onChanged: (value) {
            setState(() {
              selectedBloodGroup =
                  value;
            });
          },
        ),

        const SizedBox(height: 12),

        AppTextField(
          controller: medicalController,
          maxLines: 3,
          labelText: "Medical Conditions *",
        ),

        const SizedBox(height: 12),

        AppTextField(
          controller: doctorPhoneController,
          keyboardType: TextInputType.phone,
          labelText: "Doctor Phone *",
        ),
      ],
    ),
  ),
),
            const SizedBox(height: 20),

// BAND DETAILS

Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [

        const Text(
          "⌚ Band Details",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 15),

        AppTextField(
          controller: bandNameController,
          labelText: "Band Name *",
          hintText: "Mom's Watch",
        ),
      ],
    ),
  ),
),

const SizedBox(height: 30),

PrimaryButton(
  text: "Finish Setup",
  onPressed: finishSetup,
),

const SizedBox(height: 30),

          ],
        ),
      ),
    );
  }
}