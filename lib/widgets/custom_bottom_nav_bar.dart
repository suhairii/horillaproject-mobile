import 'package:flutter/material.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';

class CustomBottomNavBar extends StatelessWidget {
  final NotchBottomBarController controller;
  final Map<String, dynamic> employeeArguments;

  const CustomBottomNavBar({
    super.key,
    required this.controller,
    required this.employeeArguments,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedNotchBottomBar(
      notchBottomBarController: controller,
      color: Colors.white, // Bar Putih Bersih
      showLabel: true,
      notchColor: Colors.red, // Notch Merah (Aksen Brand)
      kBottomRadius: 28.0,
      kIconSize: 24.0,
      removeMargins: false,
      bottomBarWidth: MediaQuery.of(context).size.width * 1,
      durationInMilliSeconds: 500,
      itemLabelStyle: const TextStyle(fontSize: 10, color: Colors.grey),
      elevation: 10, // Shadow untuk memisahkan dari background
      bottomBarItems: const [
        BottomBarItem(
          inActiveItem: Icon(
            Icons.home_filled,
            color: Colors.grey,
          ),
          activeItem: Icon(
            Icons.home_filled,
            color: Colors.white, // Icon Putih di dalam Notch Merah
          ),
          itemLabel: 'Home',
        ),
        BottomBarItem(
          inActiveItem: Icon(
            Icons.update_outlined,
            color: Colors.grey,
          ),
          activeItem: Icon(
            Icons.update_outlined,
            color: Colors.white,
          ),
          itemLabel: 'Check In',
        ),
        BottomBarItem(
          inActiveItem: Icon(
            Icons.person,
            color: Colors.grey,
          ),
          activeItem: Icon(
            Icons.person,
            color: Colors.white,
          ),
          itemLabel: 'Employee',
        ),
      ],
      onTap: (index) {
        // Logic navigasi dipindahkan ke sini
        switch (index) {
          case 0:
            Future.delayed(const Duration(milliseconds: 500), () {
              Navigator.pushNamed(context, '/home');
            });
            break;
          case 1:
            Future.delayed(const Duration(milliseconds: 500), () {
              Navigator.pushNamed(context, '/employee_checkin_checkout');
            });
            break;
          case 2:
            Future.delayed(const Duration(milliseconds: 500), () {
              Navigator.pushNamed(context, '/employees_form',
                  arguments: employeeArguments);
            });
            break;
        }
      },
    );
  }
}