import 'package:flutter/material.dart';
import 'package:communicator/src/data_manager.dart';

class ChatInputPanelWidget extends StatelessWidget {
  final Thread thread;
  ChatInputPanelWidget({required super.key, required this.thread});

  final TextEditingController _textEditingController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textEditingController,
              decoration: const InputDecoration(hintText: 'Type your message...'),
              onSubmitted: (value) {
                _sendMessage(context);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () {
              _sendMessage(context);
            },
          ),
        ],
      ),
    );
  }

  void _sendMessage(BuildContext context) {
    String text = _textEditingController.text.trim();
    if (text.isNotEmpty) {
      dataManager.sendMessage(threadDbId: thread.dbId, senderDbId: null, type: "Text", text: text);

      // clear text field after sending message
      _textEditingController.clear();
    }
  }
}
