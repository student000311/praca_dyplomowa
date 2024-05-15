import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:communicator/src/app_providers.dart';
import 'package:communicator/src/data_manager.dart';

class AddContactView extends ConsumerStatefulWidget {
  const AddContactView({super.key});

  @override
  ConsumerState<AddContactView> createState() => _AddContactViewState();
}

class _AddContactViewState extends ConsumerState<AddContactView> {
  String _name = '';
  String _peerId = '';
  String? _nameError;
  String? _peerIdError;

  void _cancel(BuildContext context) {
    Navigator.of(context).pop();
  }

  void _add(BuildContext context) {
    if (_name.isEmpty || _peerId.length != 52) {
      setState(() {
        if (_name.isEmpty) {
          _nameError = 'Name cannot be empty';
        } else {
          _nameError = null;
        }
        if (_peerId.length != 52) {
          _peerIdError = 'Peer id must be 52 symbols';
        } else {
          _peerIdError = null;
        }
      });
      return;
    }

    dataManager.addContact(name: _name, peerId: _peerId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(
            mainScreenStateProvider.select((mainScreenState) => mainScreenState.isSmallScreen))
        ? Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _cancel(context);
                },
              ),
              title: const Text('Add Contact'),
              titleSpacing: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.done),
                  onPressed: () {
                    _add(context);
                  },
                ),
              ],
            ),
            body: form(context),
          )
        : Dialog(
            elevation: 0,
            child: form(context),
          );
  }

  Widget form(BuildContext context) {
    return Container(
      constraints: ref.watch(
              mainScreenStateProvider.select((mainScreenState) => mainScreenState.isSmallScreen))
          ? null
          : const BoxConstraints(maxWidth: 400),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ref.watch(mainScreenStateProvider
                      .select((mainScreenState) => mainScreenState.isSmallScreen))
                  ? const SizedBox()
                  : const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Contact',
                          style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 20.0)
                      ],
                    ),
              const Text(
                'Name:',
                style: TextStyle(fontSize: 16.0),
              ),
              const SizedBox(height: 5.0),
              TextField(
                onChanged: (value) {
                  setState(() {
                    _name = value;

                    // remove error hint when text changes
                    _nameError = null;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Enter name',
                  border: const OutlineInputBorder(),
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 20.0),
              const Text(
                'Peer id:',
                style: TextStyle(fontSize: 16.0),
              ),
              const SizedBox(height: 5.0),
              TextField(
                onChanged: (value) {
                  setState(() {
                    _peerId = value;

                    // remove error hint when text changes
                    _peerIdError = null;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Enter peer id',
                  border: const OutlineInputBorder(),
                  errorText: _peerIdError,
                ),
              ),
              ref.watch(mainScreenStateProvider
                      .select((mainScreenState) => mainScreenState.isSmallScreen))
                  ? const SizedBox()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              onPressed: () {
                                _cancel(context);
                              },
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10.0),
                            ElevatedButton(
                              onPressed: () {
                                _add(context);
                              },
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
