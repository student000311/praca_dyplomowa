import 'package:flutter/material.dart';
import 'package:communicator/src/views/chat_view/chat_bar_widget.dart';
import 'package:communicator/src/views/chat_view/chat_history_widget.dart';
import 'package:communicator/src/views/chat_view/chat_input_panel_widget.dart';
import 'package:communicator/src/data_manager.dart';

class ChatView extends StatefulWidget {
  final Thread? thread;
  const ChatView({required super.key, required this.thread});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  // widgets are defined here to save their state at parent change in MainScreen
  late ChatBarWidget chatBarWidget;
  late ChatHistoryWidget chatHistoryWidget;
  late ChatInputPanelWidget chatInputPanelWidget;

  @override
  void initState() {
    if (widget.thread != null) {
      // var inits must be before super.initState();
      chatBarWidget = ChatBarWidget(key: GlobalKey(), thread: widget.thread!);
      chatHistoryWidget = ChatHistoryWidget(key: GlobalKey(), thread: widget.thread!);
      chatInputPanelWidget = ChatInputPanelWidget(key: GlobalKey(), thread: widget.thread!);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return widget.thread != null
        ? Scaffold(
            appBar: chatBarWidget,
            body: Column(
              children: [
                Expanded(
                  child: chatHistoryWidget,
                ),
                chatInputPanelWidget,
              ],
            ),
          )
        : const Center(
            child: Text(
              'Select thread',
              style: TextStyle(color: Colors.grey),
            ),
          );
  }
}
