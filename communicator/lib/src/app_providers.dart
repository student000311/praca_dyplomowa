import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:communicator/src/data_manager.dart';

final currentProfileProvider = StateProvider<Profile>((ref) => dataManager.initialProfile);

final currentThreadProvider = StateProvider<Thread?>((ref) => null);

final mainScreenStateProvider = StateProvider<MainScreenState>((ref) => MainScreenState());

class MainScreenState {
  late double _screenWidth;

  late bool _isSmallScreen;
  late bool _isMediumScreen;
  late bool _isWideScreen;

  double get screenWidth => _screenWidth;

  bool get isSmallScreen => _isSmallScreen;
  bool get isMediumScreen => _isMediumScreen;
  bool get isWideScreen => _isWideScreen;

  set screenWidth(double screenWidth) {
    _screenWidth = screenWidth;
    _isSmallScreen = screenWidth < 700;
    _isMediumScreen = screenWidth >= 700 && screenWidth < 1100;
    _isWideScreen = screenWidth >= 1100;
  }
}
