import 'package:flutter/material.dart';

import 'list_view.dart';
import 'repository.dart';
import 'todo.dart';
import 'accounts.dart';
import 'login.dart';
import 'input.dart';

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
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          Repository repository = snapshot.data;

          if (repository == null) {
            return Center(
                child: TextButton(
              child: Text("Login"),
              onPressed: () =>
                  showLoginDialog(context, false, Account.create()),
            ));
          }

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
                    CheckedPopupMenuItem<String>(
                      checked: repository.showDoing,
                      value: 'doing',
                      child: const Text('Doing'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'clear-completed',
                      child: Text('Clear completed'),
                    ),
                  ],
                ),
              ],
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
                  UserAccountsDrawerHeader(
                      accountEmail:
                          Text(repository.account.username ?? "No account?"),
                      onDetailsPressed: () async {
                        List<Account> accounts = await Account.listAccounts();
                        await showDialog<void>(
                            context: context,
                            builder: (BuildContext context) {
                              return SimpleDialog(
                                title: const Text('Select account'),
                                children: <Widget>[
                                  for (Account account in accounts)
                                    SimpleDialogOption(
                                      onPressed: () {
                                        Account.setCurrent(account);
                                        setState(() {
                                          _repository =
                                              Future<Repository>.value(
                                                  Repository(account));
                                        });
                                        Navigator.pop(context);
                                      },
                                      child: Text(account.username),
                                    ),
                                  SimpleDialogOption(
                                    onPressed: () => showLoginDialog(
                                        context, true, Account.create()),
                                    child: const Text('Add Account'),
                                  ),
                                ],
                              );
                            });
                      }),
                  ListTile(
                    leading: Icon(Icons.person),
                    title: Text('Edit'),
                    onTap: () =>
                        showLoginDialog(context, false, repository.account),
                  ),
                  const Divider(
                    height: 10,
                    thickness: 2,
                    indent: 20,
                    endIndent: 20,
                  ),
                  Flexible(
                    child: RefreshIndicator(
                      child: StreamBuilder<List<Calendar>>(
                          stream: repository.calendars(),
                          builder: (BuildContext context,
                              AsyncSnapshot<List<Calendar>> snapshot) {
                            if (snapshot.hasError) {
                              return const Text("Error!");
                            } else if (snapshot.data == null) {
                              return Center(child: CircularProgressIndicator());
                            }

                            return ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: snapshot.data.length,
                              itemBuilder: (context, index) {
                                Calendar calendar = snapshot.data[index];

                                return ListTile(
                                  leading:
                                      Icon(Icons.format_list_bulleted_rounded),
                                  title: Text(calendar.name),
                                  tileColor: (calendar.path ==
                                          repository.currentCalendar?.path)
                                      ? Colors.blue
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      repository.setCalendar(calendar);
                                      Navigator.pop(context);
                                    });
                                  },
                                );
                              },
                            );
                          }),
                      onRefresh: () => repository.refreshCalendars(),
                    ),
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
