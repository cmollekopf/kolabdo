import 'package:flutter/material.dart';

import 'list_view.dart';
import 'repository.dart';
import 'todo.dart';
import 'accounts.dart';
import 'login.dart';

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
  Calendar _currentCalendar = null;
  Repository _repository = null;
  TextEditingController _textInputController = TextEditingController();
  bool _initializing = true;

  @override
  void initState() {
    super.initState();

    Account.loadCurrent().then((Account account) async {
      Repository repository = Repository(account);
      await repository.ready;
      setState(() {
        _repository = repository;
        _currentCalendar = _repository.currentCalendar;
        _initializing = false;
      });
    });
  }

  @override
  void dispose() {
    _textInputController.dispose();
    super.dispose();
  }

  Future<void> onActionSelected(String value) async {
    switch (value) {
      case 'clear-completed':
        {
          await _repository.removeCompleted();
        }
        break;
      case 'doing':
        {
          setState(() {
            _repository.showDoing = !_repository.showDoing;
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
        _repository = Repository(account);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return Center(child: CircularProgressIndicator());
    }

    if (_repository == null) {
      return Center(
          child: TextButton(
        child: Text("Login"),
        onPressed: () => showLoginDialog(context, false, Account.create()),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentCalendar?.name ?? widget.title),
        actions: <Widget>[
          Row(children: [
            Text("Doing"),
            Switch(
              value: _repository.showDoing,
              onChanged: (state) {
                setState(() {
                  _repository.showDoing = state;
                });
              },
            ),
          ]),
          PopupMenuButton<String>(
            onSelected: onActionSelected,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              CheckedPopupMenuItem<String>(
                checked: _repository.showDoing,
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
              return Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: [
                        Flexible(
                            child: TextField(
                                controller: _textInputController,
                                autofocus: true,
                                decoration: InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'Add a todo'),
                                onSubmitted: (text) {
                                  _repository.createTodo(Todo.newTodo(
                                      text, _currentCalendar.path,
                                      isDoing: _repository.showDoing));
                                  _textInputController.clear();
                                  //TODO refocus the edit instead of pop
                                  Navigator.pop(context);
                                })),
                        ElevatedButton(
                          child: Icon(Icons.add),
                          onPressed: () {
                            _repository.createTodo(Todo.newTodo(
                                _textInputController.text,
                                _currentCalendar.path,
                                isDoing: _repository.showDoing));
                            _textInputController.clear();
                          },
                          style: ElevatedButton.styleFrom(
                            shape: CircleBorder(),
                          ),
                        ),
                      ],
                    ),
                    // Align(
                    //     alignment: Alignment.centerRight,
                    //     child: OutlinedButton(
                    //         child: const Text('Done'),
                    //         onPressed: () => Navigator.pop(context),
                    //     )
                    // )
                  ],
                ),
              );
            },
          ).then((result) => _textInputController.clear());
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
                    Text(_repository.account.username ?? "No account?"),
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
                                    _repository = Repository(account);
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
              onTap: () => showLoginDialog(context, false, _repository.account),
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
                    stream: _repository.calendars(),
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
                            leading: Icon(Icons.format_list_bulleted_rounded),
                            title: Text(calendar.name),
                            tileColor: (calendar.path == _currentCalendar?.path)
                                ? Colors.blue
                                : null,
                            onTap: () {
                              setState(() {
                                _currentCalendar = calendar;
                                _repository.setCalendar(calendar);
                                Navigator.pop(context);
                              });
                            },
                          );
                        },
                      );
                    }),
                onRefresh: () => _repository.refreshCalendars(),
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TodoList(calendar: _currentCalendar, repository: _repository),
      ),
    );
  }
}
