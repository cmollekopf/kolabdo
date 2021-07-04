import 'package:flutter/material.dart';

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
        {
          await repository.removeCompleted();
        }
        break;
      case 'doing':
        {
          setState(() {
            repository.showDoing = !repository.showDoing;
          });
        }
        break;
      default:
        break;
    }
  }

  Future<void> showLoginDialog(
      BuildContext context, replace, Account acc) async {
    Account account;
    if (replace) {
      account = await Navigator.pushReplacement(
        context,
        MaterialPageRoute<Account>(
          builder: (BuildContext context) => LoginDialog(account: acc),
          fullscreenDialog: true,
        ),
      );
    } else {
      account = await Navigator.push(
        context,
        MaterialPageRoute<Account>(
          builder: (BuildContext context) => LoginDialog(account: acc),
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
                    return TodoInput(
                        calendar: repository.currentCalendar,
                        repository: repository);
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
                            showLoginDialog(context, false, account),
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
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TodoList(
                  calendar: repository.currentCalendar,
                  repository: repository,
                  showGrid: _showGrid),
            ),
          );
        });
  }
}
