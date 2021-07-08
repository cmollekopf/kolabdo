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

/**
  A wrapper around a stream that also caches the latest value
*/
class Provider<T> {
  Provider() {
    this._controller = StreamController<T>.broadcast(
        //Immediately provide the latest cached snapshot when somebody starts listening.
        onListen: () => _controller.add(_value));
  }

  T _value;

  T get value => _value;
  Stream<T> get stream => _controller.stream;

  notify() {
    _controller.add(_value);
  }

  update(T value) {
    _value = value;
    notify();
  }

  StreamController<T> _controller;
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

  Set<String> _enabledCalendars = Set<String>();
  Queue<ReplayOperation> _replayQueue = Queue<ReplayOperation>();

  Calendar currentCalendar = null;

  Provider<List<Todo>> _todoProvider;
  Provider<List<Calendar>> _calendarProvider;
  Provider<bool> _operationInProgressProvider;

  get rawTodos => _todoProvider.value;

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
    _todoProvider._value.add(todo);
    _todoProvider.notify();

    print("Updating entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.create, todo));
    await _saveToStorage(_todoProvider._value);
  }

  Future<void> updateTodo(todo) async {
    int index = _todoProvider._value.indexOf(todo);
    if (index < 0) {
      print("Failed to find entry");
      return;
    }

    _todoProvider._value[index] = todo;
    _todoProvider.notify();

    print("Updating entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.modify, todo));
    await _saveToStorage(_todoProvider._value);
  }

  Future<void> removeTodo(todo) async {
    int index = _todoProvider._value.indexOf(todo);
    if (index < 0) {
      print("Failed to find entry");
      return;
    }

    _todoProvider._value.removeAt(index);
    _todoProvider.notify();

    print("Removing entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.delete, todo));
    await _saveToStorage(_todoProvider._value);
  }

  static Future<bool> test(
      String server, String username, String password) async {
    print("Testing $server, $username");
    var newClient =
        CalDavClient(Uri.parse("https://${server}"), username, password);
    return await newClient.checkConnection();
  }

  Future<void> init() async {
    print("Initializing repository ${account.id}");
    storage = LocalStorage("${account.id}_cache.json");

    _todoProvider = Provider<List<Todo>>();
    _calendarProvider = Provider<List<Calendar>>();
    _operationInProgressProvider = Provider<bool>();

    //Load current calendar
    await storage.ready;

    var current = storage.getItem("currentCalendar");
    if (current != null) {
      currentCalendar = Calendar.fromJSONEncodable(current);
      _todoProvider.update(await _loadFromStorage());
      _calendarProvider.update(await _loadCalendarsFromStorage());
    }

    var enabled = storage.getItem("enabledCalendars");
    if (enabled != null) {
      _enabledCalendars = Set<String>.from(enabled);
    }

    print("Logging in as ${account.username}");
    _client = CalDavClient(Uri.parse("https://${account.server}"),
        account.username, account.password);

    //We're not waiting for these to complete
    fetchCalendars().then((calendars) {
      _calendarProvider.update(calendars);
    });
    fetchTodos(currentCalendar).then((todos) {
      _todoProvider.update(todos);
    });
  }

  Future<void> setCalendar(Calendar calendar) async {
    currentCalendar = calendar;
    await storage.setItem("currentCalendar", currentCalendar.toJSONEncodable());

    //Reset to empty list
    _todoProvider.update([]);

    //Start both operations in parallel, but await before completing
    var cached = _loadFromStorage();
    var remote = fetchTodos(calendar);
    _todoProvider.update(await cached);
    _todoProvider.update(await remote);
  }

  set showDoing(show) {
    _showDoing = show;
    //Reload todos (we're just filtering locally)
    _todoProvider.notify();
  }

  get showDoing => _showDoing;

  Future<void> refreshAll() async {
    _todoProvider.update(await fetchTodos(currentCalendar));
  }

  Future<void> refresh() async {
    _todoProvider.update(await fetchTodos(currentCalendar));
  }

  Future<void> refreshCalendars() async {
    _calendarProvider.update(await fetchCalendars());
  }

  _saveToStorage(List<Todo> todos) async {
    await storage.setItem(
        "todos${currentCalendar.path}",
        todos.map((todo) {
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
    return todos;
  }

  _saveCalendarsToStorage(List<Calendar> calendars) async {
    await storage.setItem(
        "calendars",
        calendars.map((calendar) {
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
    return calendars;
  }

  Stream<bool> operationInProgress() {
    return _operationInProgressProvider.stream;
  }

  Stream<List<Todo>> todos() {
    return _todoProvider._controller.stream.map((list) {
      list.sort((b, a) {
        if (a.id == b.id) return 0;
        if (a.done && !b.done) return -1;
        if (!a.done && b.done) return 1;
        return a.dateTime.compareTo(b.dateTime);
      });
      return list.where((a) => !_showDoing || a.doing).toList();
    });
  }

  bool isEnabled(Calendar calendar) {
    return _enabledCalendars.contains(calendar.path);
  }

  void setEnabled(Calendar calendar, bool value) async {
    if (value) {
      _enabledCalendars.add(calendar.path);
    } else {
      _enabledCalendars.remove(calendar.path);
    }
    await storage.setItem("enabledCalendars", _enabledCalendars.toList());
  }

  Stream<List<Calendar>> calendars({bool showEnabled = false}) {
    return _calendarProvider.stream.map((list) {
      return list.where((c) => !showEnabled || isEnabled(c)).toList();
    });
    ;
  }

  void _setInProgress(bool state) {
    _operationInProgressProvider.update(state);
  }

  Future<List<Todo>> fetchTodos(Calendar calendar) async {
    //Load from server
    if (calendar == null || _client == null) {
      return [];
    }

    _setInProgress(true);

    List<String> protectedEntries =
        _replayQueue.map((ReplayOperation operation) {
      return operation.todo.id;
    }).toList();

    var entries = await _client.getEntries(calendar.path);

    _setInProgress(false);

    List<Todo> todos = [];
    for (var entry in entries) {
      print("Todo ${entry.data}");
      Todo todo = Todo.fromICal(entry.data, entry.path);
      //Protect local items with pending operations
      if (protectedEntries.contains(todo.id)) {
        print("Skipping protected entry ${todo.id}");
      } else {
        todos.add(todo);
      }
    }

    await _saveToStorage(todos);
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
        for (var calendar in calendars) {
            if (isEnabled(calendar)) {
                setCalendar(calendar);
            }
        }
    }

    _saveCalendarsToStorage(calendars);

    return calendars;
  }

  Future<void> removeCompleted() async {
    List<Todo> list = await _loadFromStorage();
    var completed = list.where((todo) => todo.done).toList();
    var other = list.where((todo) => !todo.done).toList();
    _todoProvider.update(other);
    for (Todo todo in completed) {
      print("Removing ${todo.path}");
      enqueue(ReplayOperation(ReplayType.delete, todo));
    }

    await _saveToStorage(other);
  }
}
