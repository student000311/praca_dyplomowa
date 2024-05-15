import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;

class DataManager {
  static DataManager? _instance;
  static bool _initialized = false;
  late final Completer<void> _initializationCompleter;
  late final Database _database;
  late final int _backendPort;
  late final int _frontendPort;
  late final Profile _initialProfile;
  final _profileUpdateStreamController = StreamController<ProfileStreamWrapper>.broadcast();
  final _contactUpdateStreamController = StreamController<ContactStreamWrapper>.broadcast();
  final _threadUpdateStreamController = StreamController<ThreadStreamWrapper>.broadcast();
  final _messageUpdateStreamController = StreamController<MessageStreamWrapper>.broadcast();

  factory DataManager() {
    if (_instance == null) {
      _instance = DataManager._internal();
      return _instance!;
    } else {
      throw StateError('DataManager instance has already been created.');
    }
  }

  DataManager._internal() {
    _initializationCompleter = Completer<void>();
    _initializeInstance();
  }

  static DataManager get instance {
    if (_instance == null) {
      throw StateError('DataManager instance has not been created.');
    } else if (!_initialized) {
      throw StateError('DataManager instance has not been initialized.');
    }
    return _instance!;
  }

  Future<void> get initializationDone => _initializationCompleter.future;
  int get backendPort => _backendPort;
  int get frontendPort => _frontendPort;
  Profile get initialProfile => _initialProfile;

  Stream<ProfileStreamWrapper> get profileUpdateStream => _profileUpdateStreamController.stream;
  Stream<ContactStreamWrapper> get contactUpdateStream => _contactUpdateStreamController.stream;
  Stream<ThreadStreamWrapper> get threadUpdateStream => _threadUpdateStreamController.stream;
  Stream<MessageStreamWrapper> get messageUpdateStream => _messageUpdateStreamController.stream;

  // INITIALIZATION

  Future<void> _initializeInstance() async {
    await _initializeDatabase();
    await _initializeBackend();
    List<Profile> profiles = await getAllProfiles();
    if (profiles.isEmpty) {
      await createProfile();
    }
    Profile? profile = await getProfileByDbId(1);
    _initialProfile = profile!;

    // TODO async connection
    // List<Thread> threads = await getAllThreads();
    // for (Thread thread in threads) {
    //   Contact? contact = await getContactByDbId(thread.contactDbId);
    //   addConnection(profile: profile, contact: contact!, thread: thread);
    // }

    // test
    var prof = await getProfileByDbId(1);
    var cont = await getContactByDbId(1);
    var thr = await getThreadByDbId(1);
    if (prof != null && cont != null && thr != null) {
      addConnection(profile: prof, contact: cont, thread: thr);
    }
    // \test

    // TODO after initialization some query could stuck after adding new contact in time of massage is sent

    _initialized = true;
    _initializationCompleter.complete();
  }

  Future<void> _initializeDatabase() async {
    databaseFactory = databaseFactoryFfi;
    if (kDebugMode) {
      File dbFile = File(join(
          await getDatabasesPath(), join(Directory.current.path, 'test/databases/main.sqlite')));
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      // ${await File(join(await getDatabasesPath(), join(Directory.current.path, 'test/databases/drop_tables.sql'))).readAsString()}
      final sql = """
        ${await File(join(await getDatabasesPath(), join(Directory.current.path, 'assets/databases/initial_structures.sql'))).readAsString()}
        ${await File(join(await getDatabasesPath(), join(Directory.current.path, 'test/databases/initial_data.sql'))).readAsString()}
        """;
      final String path = join(
          await getDatabasesPath(), join(Directory.current.path, 'test/databases/main.sqlite'));
      _database = await openDatabase(path, version: 1);
      await _database.transaction((txn) async {
        await txn.execute(sql);
      });
    } else {
      final String path = join(
          await getDatabasesPath(), join(Directory.current.path, 'assets/databases/main.sqlite'));

      bool dbInit = false;
      if (!await File(path).exists()) {
        dbInit = true;
      }

      _database = await openDatabase(path, version: 1);

      var structFile = File(join(await getDatabasesPath(),
          join(Directory.current.path, 'assets/databases/initial_structures.sql')));
      if (!await structFile.exists()) {
        throw Exception(
            'Database: no assets/databases/initial_structures.sql at ${Directory.current.path}');
      }

      if (dbInit) {
        await _database.transaction((txn) async {
          await txn.execute(await File(join(await getDatabasesPath(),
                  join(Directory.current.path, 'assets/databases/initial_structures.sql')))
              .readAsString());
        });
      }
    }
    await _database.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _initializeBackend() async {
    // start frontend server
    var frontendServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _frontendPort = frontendServer.port;
    listenFrontendServer(frontendServer);

    // get free port
    ServerSocket tempServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _backendPort = tempServer.port;
    await tempServer.close();

    // start backend
    final process = await Process.start(join(Directory.current.path, './backend/backend'),
        ['--backend-port', '$backendPort', '--frontend-port', '$frontendPort']);
    process.stdout.transform(utf8.decoder).listen((data) {
      print('Backend: stdout: $data');
    });
    process.stderr.transform(utf8.decoder).listen((data) {
      print('Backend: stderr: $data');
    });
    process.exitCode.then((exitCode) {
      print('Backend: Process exited with code $exitCode');
      throw Exception('Backend: Process exited with code $exitCode');
    });
  }

  Future<void> listenFrontendServer(HttpServer frontendServer) async {
    print('Frontend listening on port $frontendPort');
    await for (var request in frontendServer) {
      handleBackendRequests(request);
    }
  }

  // HELP METHODS

  // TESTING

  void testUpdateDatabase() async {
    await _database.rawUpdate('''
      UPDATE contacts
      SET name = "Frank"
      WHERE db_id = 6
    ''');
    _contactUpdateStreamController
        .add(ContactStreamWrapper(dbId: 6, contact: await getContactByDbId(6)));

    await Future.delayed(const Duration(seconds: 1), () {});

    int creationTimestamp = DateTime.now().millisecondsSinceEpoch;

    var newMessageDbId = await _database.insert('messages', {
      'thread_db_id': 7,
      'sender_db_id': 7,
      'creation_timestamp': creationTimestamp,
      'type': 'text',
      'file': null,
      'text': 'What project?',
      'markdown': 0,
    });
    _messageUpdateStreamController.add(MessageStreamWrapper(
        dbId: newMessageDbId, message: await getMessageByDbId(newMessageDbId)));

    _threadUpdateStreamController
        .add(ThreadStreamWrapper(dbId: 7, thread: await getThreadByDbId(7)));

    await Future.delayed(const Duration(seconds: 1), () {});

    await _database.delete('threads', where: 'db_id = ?', whereArgs: [5]);
    _threadUpdateStreamController
        .add(ThreadStreamWrapper(dbId: 5, thread: await getThreadByDbId(5)));
  }

  // OPERATIONS

  // OPERATIONS // GET DATA

  // OPERATIONS // GET DATA // Profile

  Future<Profile?> getProfileByDbId(int dbId) async {
    final List<Map<String, dynamic>> maps =
        await _database.query('profiles', where: 'db_id = ?', whereArgs: [dbId]);
    if (maps.isNotEmpty) {
      return Profile.fromMap(maps[0]);
    } else {
      return null;
    }
  }

  Future<List<Profile>> getAllProfiles() async {
    final List<Map<String, dynamic>> maps = await _database.query('profiles');
    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) => Profile.fromMap(maps[i]));
    } else {
      return [];
    }
  }

  // OPERATIONS // GET DATA // Contact

  Future<Contact?> getContactByDbId(int dbId) async {
    final List<Map<String, dynamic>> maps =
        await _database.query('contacts', where: 'db_id = ?', whereArgs: [dbId]);
    if (maps.isNotEmpty) {
      return Contact.fromMap(maps[0]);
    } else {
      return null;
    }
  }

  // Future<List<Contact>?> getContactsByProfileDbId(int dbId) async {
  //   // await initializationDone;
  //   final List<Map<String, dynamic>> maps = await _database.query('contacts');
  //   if (maps.isNotEmpty) {
  //     return List.generate(maps.length, (i) => Contact.fromMap(maps[i]));
  //   } else {
  //     return null;
  //   }
  // }

  // OPERATIONS // GET DATA // Thread

  Future<Thread?> getThreadByDbId(int dbId) async {
    final List<Map<String, dynamic>> maps =
        await _database.query('threads', where: 'db_id = ?', whereArgs: [dbId]);
    if (maps.isNotEmpty) {
      return Thread.fromMap(maps[0]);
    } else {
      return null;
    }
  }

  Future<List<Thread>> getThreadsByProfileDbId(int profileDbId) async {
    final List<Map<String, dynamic>> maps =
        await _database.query('threads', where: 'profile_db_id = ?', whereArgs: [profileDbId]);
    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) => Thread.fromMap(maps[i]));
    } else {
      return [];
    }
  }

  Future<List<Thread>> getAllThreads() async {
    final List<Map<String, dynamic>> maps = await _database.query('threads');
    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) => Thread.fromMap(maps[i]));
    } else {
      return [];
    }
  }

  Future<Thread?> getThreadByContactDbId(int dbId) async {
    final List<Map<String, dynamic>> maps =
        await _database.query('threads', where: 'contact_db_id = ?', whereArgs: [dbId]);
    if (maps.isNotEmpty) {
      return Thread.fromMap(maps[0]);
    } else {
      return null;
    }
  }

  // OPERATIONS // GET DATA // Message

  Future<Message?> getMessageByDbId(int dbId) async {
    final List<Map<String, dynamic>> maps =
        await _database.query('messages', where: 'db_id = ?', whereArgs: [dbId]);
    if (maps.isNotEmpty) {
      return Message.fromMap(maps[0]);
    } else {
      return null;
    }
  }

  Future<List<Message>> getMessagesForTimestamp(
      {required int threadDbId, required int timestamp}) async {
    final List<Map<String, dynamic>> maps = await _database.query(
      'messages',
      where: 'thread_db_id = ?  AND creation_timestamp = ?',
      whereArgs: [threadDbId, timestamp],
      orderBy: 'creation_timestamp ASC',
    );

    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) => Message.fromMap(maps[i]))
          .reversed
          .toList(); // TODO optimize reverse
    } else {
      return [];
    }
  }

  // list from oldest to newest
  Future<List<Message>> getMessagesAfterTimestamp(
      {required int threadDbId,
      required int startTimestamp,
      required bool directionToNewest,
      required int count}) async {
    if (directionToNewest) {
      final List<Map<String, dynamic>> maps = await _database.query(
        'messages',
        where: 'thread_db_id = ? AND creation_timestamp > ?',
        whereArgs: [threadDbId, startTimestamp],
        orderBy: 'creation_timestamp ASC',
        limit: count,
      );
      if (maps.isNotEmpty) {
        return List.generate(maps.length, (i) => Message.fromMap(maps[i]))
            .reversed
            .toList(); // TODO optimize reverse
      } else {
        return [];
      }
    } else {
      final List<Map<String, dynamic>> maps = await _database.query(
        'messages',
        where: 'thread_db_id = ? AND creation_timestamp < ?',
        whereArgs: [threadDbId, startTimestamp],
        orderBy: 'creation_timestamp DESC',
        limit: count,
      );
      if (maps.isNotEmpty) {
        return List.generate(maps.length, (i) => Message.fromMap(maps[i])); // TODO optimize reverse
      } else {
        return [];
      }
    }
  }

  // OPERATIONS // MODIFY DATA

  // OPERATIONS // BACKEND

  Future<Map<String, dynamic>> sendJsonGetRequest({
    required String target,
  }) async {
    final response = await http.get(
      Uri.parse('http://localhost:$backendPort/$target'),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
    );

    if (response.statusCode == 200) {
      print('Backend: Succeed to "$target": ${response.statusCode}');
      return jsonDecode(response.body);
    } else {
      print('Backend: Failed to "$target": ${response.statusCode}');
      return {};
    }
  }

  Future<void> sendJsonPostRequest({
    required String target,
    required dynamic jsonData,
  }) async {
    final response = await http.post(
      Uri.parse('http://localhost:$backendPort/$target'),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode(jsonData),
    );

    if (response.statusCode == 200) {
      print('Backend: Succeed to "$target": ${response.statusCode}');
    } else {
      print('Backend: Failed to "$target": ${response.statusCode}');
    }
  }

  Future<void> addConnection(
      {required Profile profile, required Contact contact, required Thread thread}) async {
    await sendJsonPostRequest(target: 'add_connection', jsonData: {
      "profile_db_id": profile.dbId,
      "profile_private_key": profile.privateKey,
      "contact_db_id": contact.dbId,
      "contact_peer_id": contact.peerId,
    });
  }

  // Future<void> activateProfile({required Profile profile}) async {
  //   await sendJsonPostRequest(target: 'activate_profile', jsonData: profile.toJson());
  // }

  // Future<void> establishConnection({required Contact contact}) async {
  //   await sendJsonPostRequest(target: 'establish_connection', jsonData: contact.toJson());
  // }

  // OPERATIONS // MODIFY DATA // Profile

  Future<void> createProfile() async {
    Map<String, dynamic> data = await sendJsonGetRequest(target: 'get_new_keys_and_peer_id');
    if (data.isEmpty) {
      throw Exception('ERROR: could not create profile'); // TODO
    }

    int profileDbId = await _database.insert(
      'profiles',
      {
        'peer_id': data['peer_id'],
        'private_key': data['private_key'],
        'avatar': null,
        'name': "Dummy",
      },
    );
    Profile? profile = await getProfileByDbId(profileDbId);
    _profileUpdateStreamController.add(ProfileStreamWrapper(dbId: profileDbId, profile: profile));
  }

  // OPERATIONS // MODIFY DATA // Contact/Thread

  Future<void> addContact({required String name, required String peerId}) async {
    Contact? contact;
    Thread? thread;

    int contactDbId = await _database.insert(
      'contacts',
      {
        'peer_id': peerId,
        'avatar': null,
        'name': name,
      },
    );
    contact = await getContactByDbId(contactDbId);

    int creationTimestamp = DateTime.now().millisecondsSinceEpoch;
    int threadDbId = await _database.insert(
      'threads',
      {
        'profile_db_id': 1,
        'contact_db_id': contactDbId,
        'last_update': creationTimestamp,
        'last_message_db_id': null,
        'new_messages_count': 0,
        'first_unseen_message_by_contact_db_id': null,
        'first_new_message_db_id': null,
      },
    );
    thread = await getThreadByDbId(threadDbId);

    _contactUpdateStreamController.add(ContactStreamWrapper(dbId: contactDbId, contact: contact));
    _threadUpdateStreamController.add(ThreadStreamWrapper(dbId: threadDbId, thread: thread));

    Profile? profile = await getProfileByDbId(1);
    await addConnection(profile: profile!, contact: contact!, thread: thread!);
  }

  Future<void> removeThread({required int threadDbId}) async {
    Thread? thread = await getThreadByDbId(threadDbId);
    if (thread != null) {
      int contactDbId = thread.contactDbId;

      await _database.delete('threads', where: 'db_id = ?', whereArgs: [threadDbId]);
      _threadUpdateStreamController.add(ThreadStreamWrapper(dbId: threadDbId, thread: null));

      await _database.delete('contacts', where: 'db_id = ?', whereArgs: [contactDbId]);
      _contactUpdateStreamController.add(ContactStreamWrapper(dbId: contactDbId, contact: null));
    }
  }

  // OPERATIONS // MODIFY DATA // Message

  Future<void> sendMessage(
      {required int threadDbId,
      required int? senderDbId,
      required String type,
      String? file,
      String? text,
      bool markdown = false}) async {
    Message? message;
    int creationTimestamp = DateTime.now().millisecondsSinceEpoch;
    int newMessageDbId = await _database.insert(
      'messages',
      {
        'thread_db_id': threadDbId,
        'sender_db_id': senderDbId,
        'creation_timestamp': creationTimestamp,
        'type': type,
        'file': file,
        'text': text,
        'markdown': markdown == true ? 1 : 0,
      },
    );
    message = await getMessageByDbId(newMessageDbId);
    _messageUpdateStreamController
        .add(MessageStreamWrapper(dbId: newMessageDbId, message: message));

    Thread? thread = await getThreadByDbId(threadDbId);
    _threadUpdateStreamController.add(ThreadStreamWrapper(dbId: threadDbId, thread: thread));

    Profile? profile = await getProfileByDbId(1);
    Contact? contact = await getContactByDbId(thread!.contactDbId);
    await sendJsonPostRequest(target: 'send_message', jsonData: {
      'message': {
        'creation_timestamp': creationTimestamp,
        'type': type,
        'file': null,
        'text': text,
        'markdown': markdown
      },
      'addressing': {'sender_db_id': profile!.dbId, 'receiver_db_id': contact!.dbId}
    });

    // old code, possible could be helpful in case of migration of logic implementation
    // from database to app for performance improvement

    // int creationTimestamp = DateTime.now().millisecondsSinceEpoch;
    // Thread? thread = await getThreadByDbId(threadDbId);
    // Message? message;
    // if (thread != null) {
    //   int newMessageDbId = await _database.insert(
    //     'messages',
    //     {
    //       'thread_db_id': threadDbId,
    //       'sender_db_id': senderDbId,
    //       'creation_timestamp': creationTimestamp,
    //       'type': type,
    //       'file': file,
    //       'text': text,
    //       'markdown': markdown == true ? 1 : 0,
    //     },
    //   );
    //   message = await getMessageByDbId(newMessageDbId);

    //   int firstUnseenMessageByContactDbId =
    //       thread.firstUnseenMessageByContactDbId ?? newMessageDbId;
    //   await _database.update(
    //     'threads',
    //     {
    //       'last_update': creationTimestamp,
    //       'last_message_db_id': newMessageDbId,
    //       'new_messages_count': 0,
    //       'first_unseen_message_by_contact_db_id': firstUnseenMessageByContactDbId,
    //       'first_new_message_db_id': null,
    //     },
    //     where: 'db_id = ?',
    //     whereArgs: [threadDbId],
    //   );
    //   thread = await getThreadByDbId(threadDbId);

    //   _messageUpdateStreamController
    //       .add(MessageStreamWrapper(dbId: newMessageDbId, message: message));
    //   _threadUpdateStreamController.add(ThreadStreamWrapper(dbId: threadDbId, thread: thread));

    //   Profile? profile = await getProfileByDbId(1);
    //   Contact? contact = await getContactByDbId(thread!.contactDbId);
    //   await sendJsonPostRequest(target: 'send_message', jsonData: {
    //     ...message!.toJson(),
    //     'sender_peer_id': profile!.peerId,
    //     'receiver_peer_id': contact!.peerId,
    //   });
    // }
  }

  Future<void> removeAllMessagesForThread({required Thread thread}) async {
    /*
      TODO create stream for massive message update for thread
      TODO prepare db for massive deletion for thread
    */
  }

  Future<void> removeMessage({required Message message}) async {
    await _database.delete('messages', where: 'db_id = ?', whereArgs: [message.dbId]);
    _messageUpdateStreamController.add(MessageStreamWrapper(dbId: message.dbId, message: null));

    Thread? thread = await getThreadByDbId(message.threadDbId);
    _threadUpdateStreamController.add(ThreadStreamWrapper(dbId: thread!.dbId, thread: thread));

    // old code, possible could be helpful in case of migration of logic implementation
    // from database to app for performance improvement

    // Message? message = await getMessageByDbId(messageDbId);
    // if (message != null) {
    //   Thread? thread = await getThreadByDbId(message.threadDbId);

    //   if (thread!.lastMessageDbId == messageDbId) {}

    //   int firstUnseenMessageByContactDbId =
    //       thread.firstUnseenMessageByContactDbId ?? newMessageDbId;
    //   await _database.update(
    //     'threads',
    //     {
    //       'last_update': creationTimestamp,
    //       'last_message_db_id': newMessageDbId,
    //       'new_messages_count': 0,
    //       'first_unseen_message_by_contact_db_id': firstUnseenMessageByContactDbId,
    //       'first_new_message_db_id': null,
    //     },
    //     where: 'db_id = ?',
    //     whereArgs: [threadDbId],
    //   );
    //   thread = await getThreadByDbId(threadDbId);

    //   _messageUpdateStreamController
    //       .add(MessageStreamWrapper(dbId: newMessageDbId, message: message));
    //   _threadUpdateStreamController.add(ThreadStreamWrapper(dbId: threadDbId, thread: thread));

    //   await _database.delete('messages', where: 'db_id = ?', whereArgs: [messageDbId]);
    //   _messageUpdateStreamController.add(MessageStreamWrapper(dbId: messageDbId, message: null));
    // }
  }

  // OPERATIONS // IN PROGRESS

  Future<void> handleBackendRequests(HttpRequest request) async {
    switch (request.uri.path) {
      case '/receive_message':
        await handleReceiveMessage(request);
        break;
      case '/message-seen':
        handleMessageSeen(request);
        break;
      case '/message-received':
        handleMessageReceived(request);
        break;
      case '/new-contact-request':
        handleNewContactRequest(request);
        break;
      default:
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found');
    }
    request.response.close();
  }

  Future<void> handleReceiveMessage(HttpRequest request) async {
    try {
      if (request.method == 'POST' && request.headers.contentType?.mimeType == 'application/json') {
        var requestBody = await utf8.decoder.bind(request).join();
        Map<String, dynamic> jsonData = jsonDecode(requestBody);

        // print('Received JSON data: ${jsonData['message']['creation_timestamp']}'); // test

        Thread? thread = await getThreadByContactDbId(jsonData['addressing']['sender_db_id']);

        Message? message;
        int newMessageDbId = await _database.insert(
          'messages',
          {
            'thread_db_id': thread!.dbId,
            'sender_db_id': jsonData['addressing']['sender_db_id'],
            'creation_timestamp': jsonData['message']['creation_timestamp'],
            'type': jsonData['message']['type'],
            'file': jsonData['message']['file'],
            'text': jsonData['message']['text'],
            'markdown': jsonData['message']['markdown'] == true ? 1 : 0,
          },
        );
        message = await getMessageByDbId(newMessageDbId);
        _messageUpdateStreamController
            .add(MessageStreamWrapper(dbId: newMessageDbId, message: message));

        thread =
            await getThreadByContactDbId(jsonData['addressing']['sender_db_id']); // update thread
        _threadUpdateStreamController.add(ThreadStreamWrapper(dbId: thread!.dbId, thread: thread));

        var responseBody = {'message': 'Received JSON data successfully'};
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(responseBody));
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
      }
    } catch (e) {
      print('Error handling request: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Server error');
    }
  }

  void handleMessageSeen(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('Message seen request received');
  }

  void handleMessageReceived(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('Message received request received');
  }

  void handleNewContactRequest(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('New contact connection request received');
  }
}

/// just second name of DataManager singleton instance
var dataManager = DataManager.instance;

class Profile {
  final int dbId;
  final String peerId;
  final String privateKey;
  String? avatar;
  String name;

  static final Map<int, WeakReference<Profile>> _profiles = {};

  Profile._({
    required this.dbId,
    required this.peerId,
    required this.privateKey,
    this.avatar,
    required this.name,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    final int dbId = map['db_id'] as int;
    final existingProfile = _profiles[dbId]?.target;
    if (existingProfile != null) {
      existingProfile.avatar = map['avatar'] as String?;
      existingProfile.name = map['name'] as String;
      return existingProfile;
    } else {
      final profile = Profile._(
        dbId: dbId,
        peerId: map['peer_id'] as String,
        privateKey: map['private_key'] as String,
        avatar: map['avatar'] as String?,
        name: map['name'] as String,
      );
      _profiles[dbId] = WeakReference(profile);
      return profile;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'db_id': dbId,
      'peer_id': peerId,
      'private_key': privateKey,
      'avatar': avatar,
      'name': name,
    };
  }
}

class ProfileStreamWrapper {
  final int dbId;
  final Profile? profile;

  ProfileStreamWrapper({required this.dbId, required this.profile});
}

class Contact {
  final int dbId;
  String peerId;
  String? avatar;
  String name;

  static final Map<int, WeakReference<Contact>> _contacts = {};

  Contact._({
    required this.dbId,
    required this.peerId,
    this.avatar,
    required this.name,
  });

  factory Contact.fromMap(Map<String, dynamic> map) {
    final int dbId = map['db_id'] as int;
    final existingContact = _contacts[dbId]?.target;
    if (existingContact != null) {
      existingContact.avatar = map['avatar'] as String?;
      existingContact.name = map['name'] as String;
      return existingContact;
    } else {
      final contact = Contact._(
        dbId: dbId,
        peerId: map['peer_id'] as String,
        avatar: map['avatar'] as String?,
        name: map['name'] as String,
      );

      _contacts[dbId] = WeakReference(contact);
      return contact;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'db_id': dbId,
      'peer_id': peerId,
      'avatar': avatar,
      'name': name,
    };
  }
}

class ContactStreamWrapper {
  final int dbId;
  final Contact? contact;

  ContactStreamWrapper({required this.dbId, required this.contact});
}

class Thread {
  final int dbId;
  final int profileDbId;
  final int contactDbId;

  int lastUpdate; // timestamp for oldest message or thread adding to profile timestamp
  int? lastMessageDbId; // newest message of this thread
  int newMessagesCount;

  // Set<int>?
  //     pendingMessageIds; // messages sent but not yet received. the sender is always profileId // TODO db impl
  int? firstUnseenMessageByContactDbId; // first message unseen by the contact
  int? firstNewMessageDbId; // first message among those not yet seen by user

  static final Map<int, WeakReference<Thread>> _threads = {};

  Thread._({
    required this.dbId,
    required this.profileDbId,
    required this.contactDbId,
    required this.lastUpdate,
    this.lastMessageDbId,
    required this.newMessagesCount,
    // this.pendingMessageIds,
    this.firstUnseenMessageByContactDbId,
    this.firstNewMessageDbId,
  });

  factory Thread.fromMap(Map<String, dynamic> map) {
    final int dbId = map['db_id'] as int;
    final existingThread = _threads[dbId]?.target;
    if (existingThread != null) {
      existingThread.lastUpdate = map['last_update'] as int;
      existingThread.lastMessageDbId = map['last_message_db_id'] as int?;
      existingThread.newMessagesCount = map['new_messages_count'] as int;
      existingThread.firstUnseenMessageByContactDbId =
          map['first_unseen_message_by_contact_db_id'] as int?;
      existingThread.firstNewMessageDbId = map['first_new_message_db_id'] as int?;
      return existingThread;
    } else {
      final newThread = Thread._(
        dbId: dbId,
        profileDbId: map['profile_db_id'] as int,
        contactDbId: map['contact_db_id'] as int,
        lastUpdate: map['last_update'] as int,
        lastMessageDbId: map['last_message_db_id'] as int?,
        newMessagesCount: map['new_messages_count'] as int,
        firstUnseenMessageByContactDbId: map['first_unseen_message_by_contact_db_id'] as int?,
        firstNewMessageDbId: map['first_new_message_db_id'] as int?,
      );
      _threads[dbId] = WeakReference(newThread);
      return newThread;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'db_id': dbId,
      'profile_db_id': profileDbId,
      'contact_db_id': contactDbId,
      'last_update': lastUpdate,
      'last_message_db_id': lastMessageDbId,
      'new_messages_count': newMessagesCount,
      'first_unseen_message_by_contact_db_id': firstUnseenMessageByContactDbId,
      'first_new_message_db_id': firstNewMessageDbId,
    };
  }
}

class ThreadStreamWrapper {
  final int dbId;
  final Thread? thread;

  ThreadStreamWrapper({required this.dbId, required this.thread});
}

class Message {
  final int dbId;
  final int threadDbId;
  final int? senderDbId;
  final int creationTimestamp;

  final String type; // "Text", "Voice", "Video", "Media", "Files"
  final String? file;
  String? text;
  bool? markdown;
  // String? edited;

  static final Map<int, WeakReference<Message>> _messages = {};

  Message._({
    required this.dbId,
    required this.threadDbId,
    required this.senderDbId,
    required this.creationTimestamp,
    required this.type,
    this.file,
    this.text,
    this.markdown,
    // this.edited,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    final int dbId = map['db_id'] as int;
    final existingMessage = _messages[dbId]?.target;
    if (existingMessage != null) {
      existingMessage.text = map['text'] as String?;
      existingMessage.markdown = map['markdown'] != null ? map['markdown'] == 1 : null;
      return existingMessage;
    } else {
      final message = Message._(
        dbId: dbId,
        threadDbId: map['thread_db_id'] as int,
        senderDbId: map['sender_db_id'] as int?,
        creationTimestamp: map['creation_timestamp'] as int,
        type: map['type'] as String,
        file: map['file'] as String?,
        text: map['text'] as String?,
        markdown: map['markdown'] != null ? map['markdown'] == 1 : null,
      );

      _messages[dbId] = WeakReference(message);
      return message;
    }
  }
  Map<String, dynamic> toJson() => {
        'db_id': dbId,
        'thread_db_id': threadDbId,
        'sender_db_id': senderDbId,
        'creation_timestamp': creationTimestamp,
        'type': type,
        'file': file,
        'text': text,
        'markdown': markdown,
      };
}

class MessageStreamWrapper {
  final int dbId;
  final Message? message;

  MessageStreamWrapper({required this.dbId, required this.message});
}
