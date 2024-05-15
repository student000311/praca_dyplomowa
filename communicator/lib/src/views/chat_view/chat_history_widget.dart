import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:communicator/src/data_manager.dart';
import 'package:communicator/src/utils.dart' as utils;

class ChatHistoryWidget extends StatefulWidget {
  final Thread thread;
  const ChatHistoryWidget({required super.key, required this.thread});

  @override
  State<ChatHistoryWidget> createState() => _ChatHistoryWidgetState();
}

class _ChatHistoryWidgetState extends State<ChatHistoryWidget> {
  List<Message> _messages = [];
  static const int _uploadedMessagesCountLimit = 60;
  static const int _perUpdateMessageCount = 20;
  final List<StreamSubscription> _listeners = [];
  final ScrollController _scrollController = ScrollController(keepScrollOffset: false);
  Offset _tapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();

    () async {
      await _uploadInitialMessages();
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      _scrollController.addListener(_scrollListener);
    }();

    _listeners.add(dataManager.messageUpdateStream.listen((messageStreamWrapper) async {
      if (messageStreamWrapper.message == null ||
          messageStreamWrapper.message!.threadDbId == widget.thread.dbId) {
        Message? existingMessage =
            _messages.firstWhereOrNull((message) => message.dbId == messageStreamWrapper.dbId);
        if (existingMessage == null) {
          if (messageStreamWrapper.message != null) {
            if (_messages.isNotEmpty) {
              if (messageStreamWrapper.message!.creationTimestamp >=
                  _messages.last.creationTimestamp) {
                _messages.insert(0, messageStreamWrapper.message!);
                _messages = List.from(_messages);
                if (_scrollController.position.pixels ==
                    _scrollController.position.minScrollExtent) {
                  setState(() {});
                  await WidgetsBinding.instance.endOfFrame;
                } else {
                  _updateListView(atListTop: false);
                }
              }
            } else {
              _messages.add(messageStreamWrapper.message!);
              _messages = List.from(_messages);
              setState(() {});
              await WidgetsBinding.instance.endOfFrame;
            }
          }
        } else {
          if (messageStreamWrapper.message != null) {
            setState(() {});
            await WidgetsBinding.instance.endOfFrame;
            // TODO prevent jumps
          } else {
            _messages.remove(existingMessage);
            setState(() {});
            await WidgetsBinding.instance.endOfFrame;
            // TODO prevent jumps
          }
        }
      }
    }));
    // TODO unordered message upload
  }

  @override
  void dispose() {
    for (var listener in _listeners) {
      listener.cancel();
    }
    _scrollController.dispose();
    super.dispose();
  }

  // for future:
  // void _sortMessages() {
  //   _messages.sort((a, b) => b.creationTimestamp.compareTo(a.creationTimestamp));
  // }

  void _scrollListener() async {
    if (!_scrollController.position.outOfRange && _scrollController.position.atEdge) {
      // in case we are at top
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        // upload messages at top
        await _uploadMessages(directionToNewest: false);
        await _updateListView(atListTop: true);

        // remove messages from bottom
        _cleanUpMessages(directionToNewest: false);
        await _updateListView(atListTop: false);
      }
      // in case we are at bottom
      else if (_scrollController.position.pixels == _scrollController.position.minScrollExtent) {
        // upload messages at bottom
        await _uploadMessages(directionToNewest: true);
        await _updateListView(atListTop: false);

        // remove messages from top
        _cleanUpMessages(directionToNewest: true);
        await _updateListView(atListTop: true);
      }
    }
  }

  Future<void> _uploadInitialMessages() async {
    int now = DateTime.now().millisecondsSinceEpoch;
    _messages =
        await dataManager.getMessagesForTimestamp(threadDbId: widget.thread.dbId, timestamp: now);
    _messages.addAll(await dataManager.getMessagesAfterTimestamp(
        threadDbId: widget.thread.dbId,
        startTimestamp: now,
        directionToNewest: false,
        count: _perUpdateMessageCount));
  }

  void _cleanUpMessages({required bool directionToNewest}) {
    if (_messages.length > _uploadedMessagesCountLimit) {
      if (directionToNewest) {
        _messages.removeRange(_uploadedMessagesCountLimit, _messages.length);
      } else {
        _messages.removeRange(0, _messages.length - _uploadedMessagesCountLimit);
      }
    }
  }

  Future<void> _uploadMessages({required bool directionToNewest}) async {
    if (_messages.isEmpty) {
      _uploadInitialMessages();
    } else {
      List<Message> newMessages = await dataManager.getMessagesAfterTimestamp(
          threadDbId: widget.thread.dbId,
          startTimestamp:
              directionToNewest ? _messages[0].creationTimestamp : _messages.last.creationTimestamp,
          directionToNewest: directionToNewest,
          count: _perUpdateMessageCount);

      if (directionToNewest) {
        _messages.insertAll(0, newMessages);
      } else {
        _messages.addAll(newMessages);
      }
    }
  }

  // !!! should be called after each _messages update at edge !!!
  // this mean if we need to edit messages in two edges - we should call it for each separately
  Future<void> _updateListView({required bool atListTop}) async {
    if (atListTop) {
      // rebuild and wait until _scrollController.position.maxScrollExtent will change to updated value
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    } else {
      // remember offset from top before rebuild
      double offsetFromTop =
          _scrollController.position.maxScrollExtent - _scrollController.position.pixels;

      // rebuild and wait for changes to take effect. in other case it will jump to top after update
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;

      // reset position back after removing messages
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent - offsetFromTop);

      // rebuild and wait one more time just to be sure nothing will interrupt the rebuild
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      cacheExtent:
          9999999, // for proper work of scroll jumpTo. otherwise it could not count size properly
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return _chatBubble(context, index);
      },
    );
  }

  Widget _chatBubble(BuildContext context, int index) {
    bool messageIsMine = _messages[index].senderDbId == null ? true : false;
    final String creationTime =
        utils.transformUnixTimestampToTimeHumanFormat(_messages[index].creationTimestamp);

    return GestureDetector(
      onTapDown: (details) => _tapPosition = details.globalPosition,
      onLongPress: () => _showContextMenu(context, index),
      onSecondaryTapDown: (details) => _tapPosition = details.globalPosition,
      onSecondaryTap: () => _showContextMenu(context, index),
      child: Container(
        padding: EdgeInsets.fromLTRB(messageIsMine ? 40 : 10, 5.0, messageIsMine ? 10 : 40, 5.0),
        alignment: messageIsMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: messageIsMine ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(15),
              topRight: const Radius.circular(15),
              bottomLeft: messageIsMine ? const Radius.circular(15) : const Radius.circular(0),
              bottomRight: messageIsMine ? const Radius.circular(0) : const Radius.circular(15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _messages[index].text ?? '',
                style: TextStyle(color: messageIsMine ? Colors.white : Colors.black),
              ),
              Text(
                creationTime,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, int index) async {
    final screenSize = MediaQuery.of(context).size;
    await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(
          _tapPosition.dx,
          _tapPosition.dy,
          screenSize.width - _tapPosition.dx,
          screenSize.height - _tapPosition.dy,
        ),
        items: [
          PopupMenuItem(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: _messages[index].text ?? ''));
            },
            child: const Text('Copy'),
          ),
          PopupMenuItem(
            onTap: () async {
              dataManager.removeMessage(message: _messages[index]);
            },
            child: const Text('Remove'),
          ),
        ]);
  }
}
