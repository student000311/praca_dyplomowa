import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:communicator/src/app_providers.dart';
import 'package:communicator/src/data_manager.dart';

class ChatBarWidget extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final Thread thread;
  const ChatBarWidget({required super.key, required this.thread});

  @override
  ConsumerState<ChatBarWidget> createState() => _ChatBarWidgetState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ChatBarWidgetState extends ConsumerState<ChatBarWidget> {
  Contact? _contact;
  final List<StreamSubscription> _listeners = [];

  @override
  void initState() {
    super.initState();

    () async {
      _contact = await dataManager.getContactByDbId(widget.thread.contactDbId);
      setState(() {});
    }();

    _listeners.add(dataManager.contactUpdateStream.listen((contactStreamWrapper) async {
      if (contactStreamWrapper.dbId == widget.thread.contactDbId) {
        if (contactStreamWrapper.contact != null && _contact == null) {
          _contact = contactStreamWrapper.contact;
        }
        // no other cases should exist, only some delays in transactions are possible
        setState(() {});
      }
    }));
  }

  @override
  void dispose() {
    for (var listener in _listeners) {
      listener.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          ref.watch(currentThreadProvider.notifier).state = null;
        },
      ),
      title: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 20,
              backgroundImage: null, // TODO AssetImage(chatData['avatarImage']),
            ),
          ),
          Text(_contact?.name ?? ''),
        ],
      ),
      titleSpacing: 0,
      actions: [
        PopupMenuButton(
          itemBuilder: (context) {
            return [
              PopupMenuItem(
                onTap: () {
                  // TODO implement massive message deletion for thread
                },
                child: const Row(
                  children: [
                    Icon(Icons.delete_forever),
                    SizedBox(width: 10),
                    Text('Clear History'),
                  ],
                ),
              ),
            ];
          },
        ),
      ],
    );
  }
}
