import 'package:flutter/material.dart';
import 'package:communicator/src/views/add_contact_view.dart';
import 'package:communicator/src/views/navigation_view/side_menu_widget.dart';
import 'package:communicator/src/views/navigation_view/list_of_chats_widget.dart';

class NavigationView extends StatefulWidget {
  const NavigationView({required super.key});

  @override
  State<NavigationView> createState() => _NavigationViewState();
}

class _NavigationViewState extends State<NavigationView> {
  final ListOfThreadsWidget _listOfThreadsWidget = ListOfThreadsWidget(key: GlobalKey());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        drawer: const SideMenuWidget(),
        appBar: AppBar(
          title: const Text('Communicator'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () {
                showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext context) {
                      return const AddContactView();
                    });
              },
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                // TODO implement search action
              },
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                // TODO implement local menu
              },
            ),
          ],
        ),
        body: _listOfThreadsWidget);
  }
}
