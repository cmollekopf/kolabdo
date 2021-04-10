import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:uuid/uuid.dart';
import 'package:ical_parser/ical_parser.dart';
import 'package:caldav/caldav.dart';
import 'package:localstorage/localstorage.dart';
import 'package:intl/intl.dart';
import 'accounts.dart';

class Calendar {
  Calendar(this.path, this.name);
  String path;
  String name;

  factory Calendar.fromJSONEncodable(map) {
    return Calendar(map['path'], map['name']);
  }

  toJSONEncodable() {
    return {
      'name': name,
      'path': path,
    };
  }
}

String formatDateTime(DateTime dt) {
  return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt);
}

class Todo {
  Todo(this.path, this.id, this.summary, this.dateTime, this.done, this.json);

  Todo.newTodo(String summary, String path, {bool isDoing = false}) {
    this.summary = summary;
    this.id = Uuid().v4();
    this.dateTime = DateTime.now().toUtc();
    this.done = false;
    this.path = path + this.id + ".ics";
    this.json = {
      'VTODO': [
        {
          'UID': this.id,
          'SUMMARY': this.summary,
          'DTSTAMP': formatDateTime(this.dateTime),
          'STATUS': 'NEEDS-ACTION',
        },
      ],
    };
    setDoing(isDoing);
  }

  Todo.empty() {}

  Todo.fromJson(json, href) {
    if (json != null && json.containsKey('VTODO') && !json['VTODO'].isEmpty) {
      var t = json['VTODO'][0];
      this.path = href;
      this.id = t['UID'];
      this.summary = t['SUMMARY'];
      this.description = t['DESCRIPTION'];
      this.dateTime = DateTime.parse(t['DTSTAMP']);
      this.done = t['STATUS'] == 'COMPLETED';
      this.doing = t['STATUS'] == 'IN-PROCESS';
      this.json = json;
    }
  }

  static Todo fromICal(ical, href) {
    var parsed = ICal.toJson(ical);
    return Todo.fromJson(parsed, href);
  }

  static void toBuffer(StringBuffer buffer, Map<String, dynamic> map) {
    map.forEach((key, value) {
      if (key == "VTODO") {
        buffer.writeln("BEGIN:VTODO");
        toBuffer(buffer, value[0]);
        buffer.writeln("END:VTODO");
      } else {
        buffer.writeln("$key:$value");
      }
    });
  }

  String toICal() {
    var buffer = StringBuffer();
    buffer.writeln("BEGIN:VCALENDAR");
    toBuffer(buffer, json);
    buffer.writeln("END:VCALENDAR");
    return buffer.toString();
  }

  Todo setDone(bool isDone) {
    done = isDone;
    json['VTODO'][0]['STATUS'] = isDone ? 'COMPLETED' : 'NEEDS-ACTION';
    json['VTODO'][0]['PERCENT-COMPLETE'] = isDone ? '100' : '0';
    if (isDone) {
      json['VTODO'][0]['COMPLETED'] = formatDateTime(DateTime.now().toUtc());
    } else {
      json['VTODO'][0].remove('COMPLETED');
    }
    return this;
  }

  Todo setDoing(bool isDoing) {
    doing = isDoing;
    json['VTODO'][0]['STATUS'] =
        doing ? 'IN-PROCESS' : (done ? 'COMPLETED' : 'NEEDS-ACTION');
    return this;
  }

  factory Todo.fromJSONEncodable(map) {
    return Todo.fromJson(map['json'], map['path']);
  }

  toJSONEncodable() {
    return {
      'json': json,
      'path': path,
    };
  }

  String id;
  String summary = "";
  String description = "";
  DateTime dateTime = DateTime.now();
  bool done = false;
  bool doing = false;

  Map<String, dynamic> json;
  String path;
}

enum ReplayType { create, modify, delete }

class ReplayOperation {
  ReplayOperation(this.type, this.todo);
  final ReplayType type;
  final Todo todo;
}

class Repository {
  bool _showDoing = false;

  Future<void> ready;

  LocalStorage storage;

  CalDavClient _client = null;

  final Account account;

  Repository(this.account) {
    ready = init();
  }

  List<Todo> _todos = [];
  List<Calendar> _calendars = [];
  Queue<ReplayOperation> _replayQueue = Queue<ReplayOperation>();

  Calendar currentCalendar = null;

  StreamController<List<Todo>> _streamController;
  StreamController<List<Calendar>> _calendarStreamController;

  get rawTodos => _todos;

  Future<void> processQueue() {
    if (_client == null) {
      return null;
    }

    while (!_replayQueue.isEmpty) {
      ReplayOperation operation = _replayQueue.last;

      //TODO await result and verify it succeeded
      switch (operation.type) {
        case ReplayType.create:
          print("Create ${operation.todo.path} ${operation.todo.toICal()}");
          _client.addEntry(operation.todo.path, operation.todo.toICal());
          break;
        case ReplayType.modify:
          print("Modify ${operation.todo.path} ${operation.todo.toICal()}");
          _client.updateEntry(operation.todo.path, operation.todo.toICal());
          break;
        case ReplayType.delete:
          print("Delete ${operation.todo.path}");
          _client.removeEntry(operation.todo.path);
          break;
      }

      _replayQueue.removeLast();
      //TODO persist queue
    }
  }

  Future<void> enqueue(ReplayOperation operation) async {
    _replayQueue.addFirst(operation);
    //TODO persist queue
    //TODO only process if not already processing?
    processQueue();
  }

  Future<void> createTodo(todo) async {
    _todos.add(todo);
    _streamController.add(_todos);

    print("Updating entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.create, todo));
    _saveToStorage();
  }

  Future<void> updateTodo(todo) async {
    int index = _todos.indexOf(todo);
    if (index < 0) {
      print("Failed to find entry");
      return;
    }

    _todos[index] = todo;
    _streamController.add(_todos);

    print("Updating entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.modify, todo));
    _saveToStorage();
  }

  Future<void> removeTodo(todo) async {
    int index = _todos.indexOf(todo);
    if (index < 0) {
      print("Failed to find entry");
      return;
    }

    _todos.removeAt(index);
    _streamController.add(_todos);

    print("Removing entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.delete, todo));
    _saveToStorage();
  }

  static Future<bool> test(
      String server, String username, String password) async {
    print("Testing $server, $username, $password");
    var newClient =
        CalDavClient(server, username, password, '/', protocol: 'https');
    return await newClient.checkConnection();
  }

  Future<void> init() async {
    print("Initializing repository ${account.id}");
    storage = LocalStorage("${account.id}_cache.json");

    _streamController = StreamController<List<Todo>>.broadcast(
        //Immediately provide the latest cached snapshot when somebody starts listening.
        onListen: () => _streamController.add(_todos));

    _calendarStreamController = StreamController<List<Calendar>>.broadcast(
        //Immediately provide the latest cached snapshot when somebody starts listening.
        onListen: () => _calendarStreamController.add(_calendars));

    //Load current calendar
    await storage.ready;

    var current = storage.getItem("currentCalendar");
    if (current != null) {
      currentCalendar = Calendar.fromJSONEncodable(current);
      _streamController.add(await _loadFromStorage());
      _calendarStreamController.add(await _loadCalendarsFromStorage());
    }

    print("Logging in as ${account.username}");
    _client = CalDavClient(
        account.server, account.username, account.password, '/',
        protocol: 'https');

    //We're not waiting for these to complete
    fetchCalendars().then((calendars) {
      _calendarStreamController.add(calendars);
    });
    fetchTodos(currentCalendar).then((todos) {
      _streamController.add(todos);
    });
  }

  Future<void> setCalendar(Calendar calendar) async {
    currentCalendar = calendar;
    storage.setItem("currentCalendar", currentCalendar.toJSONEncodable());

    //Reset to empty list
    _todos = [];
    _streamController.add(_todos);

    //Start both operations in parallel, but await before completing
    var cached = _loadFromStorage();
    var remote = fetchTodos(calendar);
    _streamController.add(await cached);
    _streamController.add(await remote);
  }

  set showDoing(show) {
    _showDoing = show;
    //Reload todos (we're just filtering locally)
    _streamController.add(_todos);
  }

  get showDoing => _showDoing;

  Future<void> refreshAll() async {
    _streamController.add(await fetchTodos(currentCalendar));
  }

  Future<void> refresh() async {
    _streamController.add(await fetchTodos(currentCalendar));
  }

  Future<void> refreshCalendars() async {
    _calendarStreamController.add(await fetchCalendars());
  }

  _saveToStorage() {
    storage.setItem(
        "todos${currentCalendar.path}",
        _todos.map((todo) {
          return todo.toJSONEncodable();
        }).toList());
  }

  Future<List<Todo>> _loadFromStorage() async {
    if (currentCalendar == null) {
      return [];
    }
    await storage.ready;
    var entries = storage.getItem("todos${currentCalendar.path}") ?? [];
    List<Todo> todos = entries
        .map<Todo>((m) {
          return Todo.fromJSONEncodable(m);
        })
        .where((t) => t.id != null)
        .toList();
    _todos = todos;
    return todos;
  }

  _saveCalendarsToStorage() {
    storage.setItem(
        "calendars",
        _calendars.map((calendar) {
          return calendar.toJSONEncodable();
        }).toList());
  }

  Future<List<Calendar>> _loadCalendarsFromStorage() async {
    await storage.ready;
    var entries = storage.getItem("calendars") ?? [];
    List<Calendar> calendars = entries
        .map<Calendar>((m) {
          return Calendar.fromJSONEncodable(m);
        })
        .where((t) => t.path != null)
        .toList();
    _calendars = calendars;
    return calendars;
  }

  Stream<List<Todo>> todos() {
    return _streamController.stream.map((list) {
      list.sort((b, a) {
        if (a.id == b.id) return 0;
        if (a.done && !b.done) return -1;
        if (!a.done && b.done) return 1;
        return a.dateTime.compareTo(b.dateTime);
      });
      return list.where((a) => !_showDoing || a.doing).toList();
    });
  }

  Stream<List<Calendar>> calendars() {
    return _calendarStreamController.stream;
  }

  Future<List<Todo>> fetchTodos(Calendar calendar) async {
    //Load from server
    if (calendar == null || _client == null) {
      return [];
    }

    var entries = await _client.getEntries(calendar.path);

    List<Todo> todos = [];
    for (var entry in entries) {
      print("Todo ${entry.data}");
      todos.add(Todo.fromICal(entry.data, entry.path));
    }

    _todos = todos;
    _saveToStorage();
    return todos;
  }

  Future<List<Calendar>> fetchCalendars() async {
    if (_client == null) {
      return [];
    }
    //Load from server
    var list =
        await _client.getTodoCalendars("/calendars/${account.username}/");
    List<Calendar> calendars = [];
    for (var entry in list) {
      print("Calendar ${entry.displayName}");
      if (entry.displayName != "[]" && !entry.displayName.isEmpty) {
        calendars.add(Calendar(entry.path, entry.displayName));
      }
    }

    if (currentCalendar == null && !calendars.isEmpty) {
      setCalendar(calendars[0]);
    }

    _calendars = calendars;
    _saveCalendarsToStorage();

    return calendars;
  }

  Future<void> removeCompleted() async {
    List<Todo> list = await _loadFromStorage();
    var completed = list.where((todo) => todo.done).toList();
    _todos.removeWhere((t) => completed.contains(t));
    _streamController.add(_todos);
    for (Todo todo in completed) {
      print("Removing ${todo.path}");
      enqueue(ReplayOperation(ReplayType.delete, todo));
    }

    _saveToStorage();
  }
}
