import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:communicator/src/app_providers.dart';
import 'package:communicator/src/views/navigation_view/navigation_view.dart';
import 'package:communicator/src/data_manager.dart';
import 'package:communicator/src/views/chat_view/chat_view.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  bool _firstBuildWasInitialized = false;
  final NavigationView _navigationView = NavigationView(key: GlobalKey());
  ChatView _chatView = ChatView(key: GlobalKey(), thread: null);

  @override
  void initState() {
    super.initState();

    // no need to remove this listener
    ref.listenManual(currentThreadProvider, (previous, next) {
      _chatView = ChatView(key: GlobalKey(), thread: next);
      setState(() {});
    });

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    updateMainScreenState();
  }

  void updateMainScreenState() {
    ref.read(mainScreenStateProvider.notifier).state.screenWidth =
        MediaQuery.of(context).size.width;
  }

  @override
  Widget build(BuildContext context) {
    if (!_firstBuildWasInitialized) {
      updateMainScreenState();
      _firstBuildWasInitialized = true;
    }

    return Scaffold(
        appBar: kDebugMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.lightbulb),
                  onPressed: () {
                    dataManager.testUpdateDatabase();
                  },
                ),
                title: const Text('debug_panel'),
              )
            : null,
        body: ref.watch(
                mainScreenStateProvider.select((mainScreenState) => mainScreenState.isSmallScreen))
            ? ref.watch(currentThreadProvider) == null
                ? _navigationView
                : _chatView
            : Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 900),
                  decoration: BoxDecoration(border: Border.all(width: 1)),
                  child: Row(
                    children: [
                      Expanded(
                        child: _navigationView,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: _chatView),
                    ],
                  ),
                ),
              ));
  }
}
