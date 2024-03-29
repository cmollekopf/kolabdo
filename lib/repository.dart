import 'dart:async';
import 'dart:core';
import 'dart:collection';

import 'package:uuid/uuid.dart';
import 'package:ical_parser/ical_parser.dart';
import 'package:caldav/caldav.dart';
import 'package:localstorage/localstorage.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'accounts.dart';

class Calendar {
  Calendar(this.path, this.name, this.ctag);
  String path;
  String name;
  String ctag;

  factory Calendar.fromJSONEncodable(map) {
    return Calendar(map['path'], map['name'], map['ctag']);
  }

  toJSONEncodable() {
    return {
      'name': name,
      'path': path,
      'ctag': ctag,
    };
  }
}

String formatDateTime(DateTime dt) {
  return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt);
}

class Todo {
  Todo(this.path, this.id, this.summary, this.dateTime, this.done, this.json);

  Todo.newTodo(String summary, String path,
      {bool isDoing = false, String id = null}) {
    this.summary = summary;
    if (id == null) {
      this.id = Uuid().v4();
    } else {
      this.id = id;
    }
    this.dateTime = DateTime.now().toUtc();
    this.done = false;
    this.path = path + this.id + ".ics";
    this.sequence = 1;
    this.json = {
      'VTODO': [
        {
          'UID': this.id,
          'SUMMARY': this.summary,
          'DTSTAMP': formatDateTime(this.dateTime),
          'STATUS': 'NEEDS-ACTION',
          'SEQUENCE': '1',
        },
      ],
    };
    setDoing(isDoing);
  }

  Todo.empty() {}

  Todo.fromEtag(href, etag) {
    this.path = href;
    this.etag = etag;
  }

  Todo.fromJson(json, href, etag) {
    this.path = href;
    this.etag = etag;
    if (json != null && json.containsKey('VTODO') && !json['VTODO'].isEmpty) {
      var t = json['VTODO'][0];
      this.id = t['UID'];
      this.summary = t['SUMMARY'];
      this.description = t['DESCRIPTION'];
      this.dateTime = DateTime.parse(t['DTSTAMP']);
      //From storage we get an int, but from the network we may get a string
      if (t['SEQUENCE'] is String) {
        this.sequence = int.parse(t['SEQUENCE']);
      } else {
        this.sequence = t['SEQUENCE'];
      }
      this.done = t['STATUS'] == 'COMPLETED';
      this.doing = t['STATUS'] == 'IN-PROCESS';
      this.json = json;
    }
  }

  updateTimestamp() {
    dateTime = DateTime.now().toUtc();
  }

  updateJson() {
    json['VTODO'][0]['SUMMARY'] = this.summary;
    json['VTODO'][0]['DESCRIPTION'] = this.description;
    json['VTODO'][0]['SEQUENCE'] = this.sequence;
    json['VTODO'][0]['DTSTAMP'] = formatDateTime(this.dateTime);
  }

  static Todo fromICal(ical, href, etag) {
    var parsed = ICal.toJson(ical);
    return Todo.fromJson(parsed, href, etag);
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
    return Todo.fromJson(map['json'], map['path'], map['etag']);
  }

  toJSONEncodable() {
    return {
      'json': json,
      'path': path,
      'etag': etag,
    };
  }

  String id;
  String summary = "";
  String description = "";
  DateTime dateTime = DateTime.now();
  bool done = false;
  bool doing = false;
  int sequence = 0;
  String etag;
  bool dirty = false;

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
  Future<void> initialized;

  LocalStorage storage;

  CalDavClient _client = null;

  final Account account;

  http.BaseClient httpClient;

  Repository(this.account, {http.BaseClient httpClient}) {
    this.httpClient = httpClient;
    ready = init();
  }

  Set<String> _enabledCalendars = Set<String>();
  Queue<ReplayOperation> _replayQueue = Queue<ReplayOperation>();

  Calendar currentCalendar = null;

  Provider<List<Todo>> _todoProvider;
  Provider<List<Calendar>> _calendarProvider;
  Provider<bool> _operationInProgressProvider;

  get rawCalendars => _calendarProvider.value;
  get rawTodos => _todoProvider.value;

  Future<void> processQueue() async {
    if (_client == null) {
      return null;
    }

    const numRetries = 3;
    int retries = numRetries;

    while (!_replayQueue.isEmpty) {
      ReplayOperation operation = _replayQueue.last;

      try {
        switch (operation.type) {
          case ReplayType.create:
            print("Create ${operation.todo.path} ${operation.todo.toICal()}");
            await _client.addEntry(
                operation.todo.path, operation.todo.toICal());
            break;
          case ReplayType.modify:
            print("Modify ${operation.todo.path} ${operation.todo.toICal()}");
            await _client.updateEntry(
                operation.todo.path, operation.todo.toICal());
            break;
          case ReplayType.delete:
            print("Delete ${operation.todo.path}");
            await _client.removeEntry(operation.todo.path);
            break;
        }
        _replayQueue.removeLast();
        retries = numRetries;
        print("Replay succeeded");
      } on Exception catch (error) {
        print("Error during replay: ${error}");
        retries--;
        if (retries <= 0) {
          print("Giving up with replay operation after ${numRetries} retries.");
          _replayQueue.removeLast();
        }
      }

      //TODO persist queue
    }
  }

  Future<void> enqueue(ReplayOperation operation) async {
    _replayQueue.addFirst(operation);
    //TODO persist queue
    //TODO only process if not already processing?
    await processQueue();
  }

  Future<void> createTodo(todo) async {

    todo.dirty = true;

    _todoProvider._value.add(todo);
    _todoProvider.notify();

    print("Updating entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.create, todo));
    await _saveToStorage(_todoProvider._value);
  }

  Future<void> updateTodo(todo) async {
    int index = _findLocalTodoIndex(todo.id);
    if (index < 0) {
      print("Failed to find entry for: ${todo.summary}");
      return;
    }

    todo.sequence += 1;
    todo.updateTimestamp();
    todo.updateJson();

    todo.dirty = true;

    _todoProvider._value[index] = todo;
    _todoProvider.notify();

    print("Updating entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.modify, todo));
    await _saveToStorage(_todoProvider._value);
  }

  Future<void> removeTodo(todo) async {
    int index = _findLocalTodoIndex(todo.id);
    if (index < 0) {
      print("Failed to find entry: ${todo.summary}");
      return;
    }

    _todoProvider._value.removeAt(index);
    _todoProvider.notify();

    print("Removing entry ${todo.path}");
    enqueue(ReplayOperation(ReplayType.delete, todo));
    await _saveToStorage(_todoProvider._value);
  }

  static Future<bool> test(String server, String username, String password,
      {http.BaseClient httpClient}) async {
    print("Testing $server, $username");
    var newClient = CalDavClient(
        Uri.parse("https://${server}"), username, password,
        httpClient: httpClient);
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
    }

    _calendarProvider.update(await _loadCalendarsFromStorage());
    var enabled = storage.getItem("enabledCalendars");
    if (enabled != null) {
      _enabledCalendars = Set<String>.from(enabled);
    }

    print("Logging in as ${account.username}");
    _client = CalDavClient(Uri.parse("https://${account.server}"),
        account.username, account.password,
        httpClient: this.httpClient);

    //We're not waiting for these to complete
    var calendarsResult = updateCalendars();
    var todosResult = updateTodos(currentCalendar);
    this.initialized = Future.wait([calendarsResult, todosResult]);
  }

  Future<void> setCalendar(Calendar calendar) async {
    currentCalendar = calendar;
    await storage.setItem("currentCalendar", currentCalendar.toJSONEncodable());

    //Reset to empty list
    _todoProvider.update([]);

    //Start both operations in parallel, but await before completing
    var cached = _loadFromStorage();
    var remote = updateTodos(calendar);
    _todoProvider.update(await cached);
    await remote;
  }

  Future<void> remove() async {
    await storage.clear();
  }

  set showDoing(show) {
    _showDoing = show;
    //Reload todos (we're just filtering locally)
    _todoProvider.notify();
  }

  get showDoing => _showDoing;

  Future<void> refresh() async {
    return updateTodos(currentCalendar);
  }

  Future<void> refreshCalendars() async {
    await updateCalendars();
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
  }

  void _setInProgress(bool state) {
    _operationInProgressProvider.update(state);
  }

  Todo _findLocalTodo(String id) {
    return _todoProvider._value
        .firstWhere((t) => t.id == id, orElse: () => null);
  }

  int _findLocalTodoIndex(String id) {
    return _todoProvider._value.indexWhere((t) => t.id == id);
  }

  Future<void> updateTodos(Calendar calendar) async {
    //This can apparently happen when first logging in.
    await ready;
    if (calendar == null) {
      _todoProvider.update([]);
      return;
    }
    final stopwatch = Stopwatch()..start();

    bool fetchInOne = true;

    List<Todo> newList = [];
    if (fetchInOne) {
      //Just fetch everything
      newList = await fetchTodos(calendar).then((todos) async {
        print('Fetched items in ${stopwatch.elapsed.inMilliseconds}');
        return todos.map((Todo todo) {
          //Check if we have a newer entry locally already.
          var local = _findLocalTodo(todo.id);
          if (local != null) {
            if (local.sequence > todo.sequence) {
              print(
                  "Keeping local item instead ${local.sequence}:${todo.sequence} ${local.etag}:${todo.etag} ${todo.summary}");
              //If we do, we keep that instead.
              return local;
            }
          }
          return todo;
        }).toList();
      });
    } else {
      //This turns out to be slower than just fetching everything in a single request every time.
      //Only fetch what we need to fetch, but in two queries
      await fetchTodos(calendar, etagsOnly: true).then((todos) async {
        print('fetched hrefs in ${stopwatch.elapsed.inMilliseconds}');
        var localTodos = Map.fromIterable(_todoProvider._value,
            key: (t) => t.path, value: (t) => t);
        List<String> toFetch = [];
        for (var remoteTodo in todos) {
          if (localTodos.containsKey(remoteTodo.path)) {
            var local = localTodos[remoteTodo.path];
            //Modified
            if (remoteTodo.etag != local.etag) {
              toFetch.add(remoteTodo.path);
            } else {
              newList.add(local);
            }
          } else {
            //New
            toFetch.add(remoteTodo.path);
          }
        }
        await fetchTodos(calendar, hrefs: toFetch).then((todos) async {
          print('Fetched items in ${stopwatch.elapsed.inMilliseconds}');
          newList.addAll(todos);
        });
      });
    }

    // Protect new and modified tasks
    for (var t in _todoProvider._value) {
      if (t.dirty) {
        var index = newList.indexWhere((_t) => _t.id == t.id);
        if (index < 0) {
          newList.add(t);
        } else {
          newList[index] = t;
        }
      }
    }

    await _saveToStorage(newList);
    _todoProvider.update(newList);
    print('Complete in ${stopwatch.elapsed.inMilliseconds}');
  }

  Future<List<Todo>> fetchTodos(Calendar calendar,
      {List<String> hrefs, bool etagsOnly = false}) async {
    //Load from server
    if (calendar == null || _client == null) {
      return [];
    }

    _setInProgress(true);

    var entries = [];
    try {
        entries = await _client.getEntries(calendar.path, hrefs: hrefs, etagsOnly: etagsOnly);
    } on ArgumentError catch (e) {
        print("Error while fetching the calendar: ${calendar.path} $e");
    }

    _setInProgress(false);

    return entries
        .map<Todo>((e) => (e.data == null)
            ? Todo.fromEtag(e.path, e.etag)
            : Todo.fromICal(e.data, e.path, e.etag))
        .toList();
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
        calendars.add(Calendar(entry.path, entry.displayName, entry.ctag));
      }
    }

    return calendars;
  }

  Future<void> updateCalendars() async {
    var calendars = await fetchCalendars();

    if (currentCalendar == null && !calendars.isEmpty) {
      for (var calendar in calendars) {
        if (isEnabled(calendar)) {
          await setCalendar(calendar);
        }
      }
    }

    await _saveCalendarsToStorage(calendars);
    _calendarProvider.update(calendars);
  }

  Future<void> checkForUpdates() async {
    final stopwatch = Stopwatch()..start();
    var calendars = await fetchCalendars();

    for (var calendar in calendars) {
      var index = _calendarProvider.value
          .indexWhere((Calendar cal) => cal.path == calendar.path);
      if (index >= 0) {
        Calendar localCalendar = _calendarProvider.value[index];
        if (localCalendar != null && calendar.ctag != localCalendar.ctag) {
          await updateTodos(localCalendar);
          //Update the ctag
          _calendarProvider.value[index] = calendar;
          //We're not notifying because noone is listening for the ctag change?
        }
      }
    }

    print('Checked for updates in ${stopwatch.elapsed.inMilliseconds}');
    await _saveCalendarsToStorage(_calendarProvider.value);
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
