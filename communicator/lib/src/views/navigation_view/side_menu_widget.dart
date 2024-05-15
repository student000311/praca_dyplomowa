import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:communicator/src/app_providers.dart';

class SideMenuWidget extends ConsumerWidget {
  const SideMenuWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: ListView(
        // Important: no padding should be in the ListView.
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 140,
            child: DrawerHeader(
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 37, 51, 59),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundImage: null, // TODO AssetImage(chatData['avatarImage']),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  Text(
                    ref.watch(currentProfileProvider
                        .select((currentProfileProvider) => currentProfileProvider.name)),
                    style: const TextStyle(
                      fontSize: 20.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Row(
              children: [
                Icon(Icons.person),
                SizedBox(width: 10),
                Text('Show Peer ID'),
              ],
            ),
            onTap: () {
              showPeerId(context: context, ref: ref);
            },
          ),
          const Divider(),
          ListTile(
            title: const Row(
              children: [
                Icon(Icons.contacts),
                SizedBox(width: 10),
                Text('Contacts'),
              ],
            ),
            onTap: () {
              // TODO contacts
            },
          ),
          ListTile(
            title: const Row(
              children: [
                Icon(Icons.settings),
                SizedBox(width: 10),
                Text('Settings'),
              ],
            ),
            onTap: () {
              // TODO settings
            },
          ),
          const Divider(),
          ListTile(
            title: const Row(
              children: [
                Icon(Icons.info),
                SizedBox(width: 10),
                Text('About App'),
              ],
            ),
            onTap: () {
              // TODO about app
            },
          ),
        ],
      ),
    );
  }

  void showPeerId({required BuildContext context, required WidgetRef ref}) {
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return Center(
            child: Dialog(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'Profile peer id:',
                        style: TextStyle(fontSize: 16.0),
                      ),
                      const SizedBox(height: 5.0),
                      Text(
                        ref.watch(currentProfileProvider
                            .select((currentProfileProvider) => currentProfileProvider.peerId)),
                        softWrap: true,
                        style: const TextStyle(
                            fontSize: 20, backgroundColor: Color.fromRGBO(21, 32, 41, 1)),
                      ),
                      const SizedBox(height: 20.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          ElevatedButton(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(
                                  text: ref.read(currentProfileProvider.select(
                                      (currentProfileProvider) => currentProfileProvider.peerId))));
                              if (context.mounted) Navigator.of(context).pop();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            child: const Text('Copy'),
                          ),
                          const SizedBox(width: 10.0),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
  }
}
