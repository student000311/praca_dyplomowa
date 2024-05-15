// import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:communicator/src/app.dart';
import 'package:communicator/src/settings/settings_controller.dart';
import 'package:communicator/src/settings/settings_service.dart';
import 'package:communicator/src/data_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must add this line.
  // await windowManager.ensureInitialized();

  // WindowOptions windowOptions = const WindowOptions(
  //   minimumSize: Size(250, 300),
  // );
  // windowManager.waitUntilReadyToShow(windowOptions, () async {
  //   await windowManager.show();
  //   await windowManager.focus();
  // });

  // Set up the SettingsController, which will glue user settings to multiple
  // Flutter Widgets.
  final settingsController = SettingsController(SettingsService());

  // Load the user's preferred theme while the splash screen is displayed.
  // This prevents a sudden theme change when the app is first displayed.
  await settingsController.loadSettings();

  await DataManager().initializationDone;

  // Run the app and pass in the SettingsController. The app listens to the
  // SettingsController for changes, then passes it further down to the
  // SettingsView.
  runApp(ProviderScope(child: MyApp(settingsController: settingsController)));
}
