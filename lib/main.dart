import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:platform/platform.dart';

import 'list_view.dart';
import 'repository.dart';
import 'todo.dart';
import 'accounts.dart';
import 'login.dart';
import 'input.dart';
import 'calendar_selection.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kolab Do',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: "/",
      routes: {
        '/': (context) => KolabDo(title: 'Kolab Do'),
        '/todo': (context) => TodoView(),
      },
    );
  }
}

class KolabDo extends StatefulWidget {
  KolabDo({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _App createState() => _App();
}

class _App extends State<KolabDo> {
  Future<Repository> _repository;
  bool _showGrid = true;
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _repository = Account.loadCurrent().then((Account account) async {
      Repository repository = Repository(account);
      await repository.ready;
      return repository;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> onActionSelected(String value) async {
    Repository repository = await _repository;
    switch (value) {
      case 'clear-completed':
        await repository.removeCompleted();
        break;
      case 'update':
        if (const LocalPlatform().isAndroid) {
          AndroidIntent intent = AndroidIntent(
            action: 'action_view',
            data:
                'https://github.com/cmollekopf/kolabdo/releases/latest/download/kolabdo.apk',
            flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          await intent.launch();
        }
        break;
      case 'doing':
        setState(() {
          repository.showDoing = !repository.showDoing;
        });
        break;
      default:
        break;
    }
  }

  Future<void> showLoginDialog(BuildContext context, replace, Account acc,
      {Function(Account) onRemove = null}) async {
    Account account;
    if (replace) {
      account = await Navigator.pushReplacement(
        context,
        MaterialPageRoute<Account>(
          builder: (BuildContext context) =>
              LoginDialog(account: acc, onRemove: onRemove),
          fullscreenDialog: true,
        ),
      );
    } else {
      account = await Navigator.push(
        context,
        MaterialPageRoute<Account>(
          builder: (BuildContext context) =>
              LoginDialog(account: acc, onRemove: onRemove),
          fullscreenDialog: true,
        ),
      );
    }

    if (account != null) {
      print("Setting the repository");
      Account.store(account);
      Account.setCurrent(account);

      setState(() {
        _repository = Future<Repository>.value(Repository(account));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Repository>(
        future: _repository,
        builder: (BuildContext context, AsyncSnapshot<Repository> snapshot) {
          if (snapshot.hasError) {
            return LoginDialog(
                account: Account.create(),
                onDone: (Account account) {
                  Account.store(account);
                  Account.setCurrent(account);

                  setState(() {
                    _repository = Future<Repository>.value(Repository(account));
                  });
                });
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          Repository repository = snapshot.data;

          return Scaffold(
            key: _scaffoldKey,
            appBar: AppBar(
              title: Text(repository.currentCalendar?.name ?? widget.title),
              actions: <Widget>[
                IconButton(
                  icon: Icon(_showGrid ? Icons.list : Icons.grid_view),
                  tooltip: "Switch between grid and list view",
                  onPressed: () {
                    setState(() {
                      _showGrid = !_showGrid;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(repository.showDoing
                      ? Icons.bookmark_border
                      : Icons.bookmark),
                  tooltip: "Show tasks marked as doing",
                  onPressed: () {
                    setState(() {
                      repository.showDoing = !repository.showDoing;
                    });
                  },
                ),
                PopupMenuButton<String>(
                  onSelected: onActionSelected,
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'clear-completed',
                      child: Text('Clear completed'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'update',
                      child: Text('Update'),
                    ),
                  ],
                ),
              ],
              bottom: PreferredSize(
                preferredSize: Size(double.infinity, 1.0),
                child: StreamBuilder(
                    stream: repository.operationInProgress(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data) {
                        return LinearProgressIndicator();
                      } else {
                        return Container();
                      }
                    }),
              ),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (BuildContext context) {
                    return Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom),
                        child: TodoInput(
                            calendar: repository.currentCalendar,
                            repository: repository));
                  },
                );
              },
              tooltip: 'Add Todo',
              child: Icon(Icons.add),
            ),
            drawer: Drawer(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppBar(
                    leading: Container(),
                    title: Text("Kolab Do"),
                    actions: <Widget>[
                      IconButton(
                        icon: Icon(Icons.add),
                        tooltip: "Add Account",
                        onPressed: () =>
                            showLoginDialog(context, false, Account.create()),
                      ),
                    ],
                  ),
                  Expanded(
                    child: CalendarSelection(
                        repository: repository,
                        onEdit: (Account account) =>
                            showLoginDialog(context, false, account,
                                onRemove: (Account account) async {
                              await Account.remove(account);
                              await repository.remove();

                              var accounts = await Account.listAccounts();
                              if (accounts.isEmpty) {
                                setState(() {
                                  Account.setCurrent(null);
                                  _repository = Future<Repository>.error(
                                      "No account available");
                                });
                              } else {
                                Account newAccount = accounts.first;
                                setState(() {
                                  Account.setCurrent(newAccount);
                                  _repository = Future<Repository>.value(
                                      Repository(newAccount));
                                });
                              }
                            }),
                        onSelectionChanged:
                            (Account account, Calendar calendar) {
                          var repo = Repository(account);
                          if (calendar != null) {
                            repo.setCalendar(calendar);
                          }

                          setState(() {
                            Account.setCurrent(account);
                            _repository = Future<Repository>.value(repo);
                          });

                          Navigator.pop(context);
                        }),
                  ),
                ],
              ),
            ),
            body: repository.currentCalendar != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TodoList(
                        calendar: repository.currentCalendar,
                        repository: repository,
                        showGrid: _showGrid))
                : Center(
                    child: ElevatedButton(
                    child: Text("Select Calendars"),
                    onPressed: () => _scaffoldKey.currentState.openDrawer(),
                  )),
          );
        });
  }
}
