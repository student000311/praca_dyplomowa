import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:communicator/src/data_manager.dart';
import 'package:communicator/src/app_providers.dart';
import 'package:communicator/src/utils.dart' as utils;

class ThreadData {
  final Thread thread;
  Contact? contact;
  Message? message;

  ThreadData({required this.thread, required this.contact, required this.message});
}

class ListOfThreadsWidget extends ConsumerStatefulWidget {
  const ListOfThreadsWidget({required super.key});

  @override
  ConsumerState<ListOfThreadsWidget> createState() => _ListOfThreadsWidgetState();
}

class _ListOfThreadsWidgetState extends ConsumerState<ListOfThreadsWidget> {
  final int _profileDbId = 1;
  List<ThreadData> _threadDatas = [];
  late Future _initThreadDatasUpdateFinished;
  final List<StreamSubscription> _listeners = [];
  Offset _tapPosition = Offset.zero;

  // TODO if no current thread present -> null

  @override
  void initState() {
    super.initState();
    _initThreadDatasUpdateFinished = _updateThreadDatas();

    // if info about some thread was updated
    _listeners.add(dataManager.threadUpdateStream.listen((threadStreamWrapper) async {
      // look for known threads in _threadData list
      ThreadData? existingThreadData = _threadDatas
          .firstWhereOrNull((threadData) => threadData.thread.dbId == threadStreamWrapper.dbId);
      // if we already have this thread
      if (existingThreadData != null) {
        if (threadStreamWrapper.thread != null) {
          existingThreadData.contact =
              await dataManager.getContactByDbId(threadStreamWrapper.thread!.contactDbId);
          if (threadStreamWrapper.thread!.lastMessageDbId != null) {
            existingThreadData.message =
                await dataManager.getMessageByDbId(threadStreamWrapper.thread!.lastMessageDbId!);
          }
          _sortThreads();
        } else {
          _threadDatas.remove(existingThreadData);
        }
        setState(() {});
      }
      // else if we haven't
      else {
        if (threadStreamWrapper.thread?.profileDbId == _profileDbId) {
          _threadDatas.add(await _loadThreadData(threadStreamWrapper.thread));
          _sortThreads();
          setState(() {});
        }
      }
    }));
    _listeners.add(dataManager.contactUpdateStream.listen((contactStreamWrapper) async {
      ThreadData? existingThreadData = _threadDatas.firstWhereOrNull(
          (threadData) => threadData.thread.contactDbId == contactStreamWrapper.dbId);
      if (existingThreadData != null) {
        existingThreadData.contact = contactStreamWrapper.contact;
        // update widget
        setState(() {});
      }
    }));
    _listeners.add(dataManager.messageUpdateStream.listen((messageStreamWrapper) async {
      ThreadData? existingThreadData = _threadDatas.firstWhereOrNull(
          (threadData) => threadData.thread.lastMessageDbId == messageStreamWrapper.dbId);
      if (existingThreadData != null) {
        existingThreadData.message = messageStreamWrapper.message;
        // update widget
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

  void _sortThreads() {
    _threadDatas.sort((a, b) => b.thread.lastUpdate.compareTo(a.thread.lastUpdate));
  }

  Future<ThreadData> _loadThreadData(thread) async {
    Contact? contact = await dataManager.getContactByDbId(thread.contactDbId);
    Message? message;
    if (thread.lastMessageDbId != null) {
      message = await dataManager.getMessageByDbId(thread.lastMessageDbId!);
    }
    return ThreadData(thread: thread, contact: contact, message: message);
  }

  Future<void> _updateThreadDatas() async {
    var threads = await dataManager.getThreadsByProfileDbId(_profileDbId);
    _threadDatas = [];
    for (var thread in threads) {
      _threadDatas.add(await _loadThreadData(thread));
    }
    _sortThreads();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initThreadDatasUpdateFinished,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else {
          if (_threadDatas.isEmpty) {
            return const Center(child: Text('no threads'));
          }
          return ListView.builder(
            itemCount: _threadDatas.length,
            itemBuilder: (context, index) {
              return _buildListItem(context, index);
            },
          );
        }
      },
    );
  }

  Widget _buildListItem(BuildContext context, int index) {
    final String lastUpdateTimestampFormatted =
        utils.transformUnixTimestampToGeneralizedHumanFormat(_threadDatas[index].thread.lastUpdate);
    final String unseenMessagesFormatted = _threadDatas[index].thread.newMessagesCount > 9999
        ? '9999+'
        : _threadDatas[index].thread.newMessagesCount.toString();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          ref.watch(currentThreadProvider.notifier).state = _threadDatas[index].thread;
        },
        onTapDown: (details) => _tapPosition = details.globalPosition,
        onLongPress: () => _showContextMenu(context, index),
        onSecondaryTapDown: (details) => _tapPosition = details.globalPosition,
        onSecondaryTap: () => _showContextMenu(context, index),
        child: Container(
          color: ref.watch(currentThreadProvider) == _threadDatas[index].thread
              ? Colors.blueGrey[900]
              : null,
          child: ListTile(
            leading: const CircleAvatar(
              radius: 20,
              backgroundImage: null, // TODO AssetImage(chatData['avatarImage']),
            ),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _threadDatas[index].contact?.name ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.0,
                    ),
                  ),
                ),

                // if we have some last message
                if (_threadDatas[index].message != null)
                  // and it is the same, that should should be
                  if (_threadDatas[index].message!.dbId ==
                      _threadDatas[index].thread.lastMessageDbId)
                    // if it's sender is user
                    if (_threadDatas[index].message!.senderDbId == null)
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Icon(
                            _threadDatas[index].thread.firstUnseenMessageByContactDbId != null
                                ? Icons.done
                                : Icons.done_all,
                            size: 17),
                      ),
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Text(
                    lastUpdateTimestampFormatted,
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 13.0,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _threadDatas[index].message?.text ?? '',
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 14.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_threadDatas[index].thread.newMessagesCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Container(
                      padding: const EdgeInsets.only(left: 6, right: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        unseenMessagesFormatted,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
              dataManager.removeThread(threadDbId: _threadDatas[index].thread.dbId);
            },
            child: const Text('Remove'),
          ),
        ]);
  }
}
