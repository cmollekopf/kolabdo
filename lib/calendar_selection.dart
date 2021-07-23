import 'package:flutter/material.dart';

import 'list_view.dart';
import 'repository.dart';
import 'todo.dart';
import 'accounts.dart';
import 'login.dart';

class CalendarSelection extends StatefulWidget {
  CalendarSelection(
      {Key key, this.onSelectionChanged, this.onEdit, this.repository})
      : super(key: key);

  Function(Account account, Calendar calendar) onSelectionChanged;
  Function(Account account) onEdit;
  Repository repository;

  @override
  State<StatefulWidget> createState() => _CalendarSelection();
}

class _CalendarSelection extends State<CalendarSelection> {
  Future<List<Account>> _accounts;
  Future<Account> _currentAccount;
  String _currentAccountId;
  Repository repository;
  int _editEnabled = -1;

  @override
  void initState() {
    super.initState();

    repository = widget.repository;
    _accounts = Account.listAccounts();
    _currentAccount = Account.loadCurrent();
    //TODO not sure if this is the correct way to go about it?
    _currentAccount.then((Account current) => _currentAccountId = current.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Account>>(
        future: _accounts,
        builder: (BuildContext context, AsyncSnapshot<List<Account>> snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          List<Account> accounts = snapshot.data;
          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              Account account = accounts[index];
              Repository repository = Repository(account);

              return Column(children: [
                ListTile(
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_editEnabled == index
                            ? Icons.favorite
                            : Icons.favorite_outline),
                        tooltip: "Edit",
                        onPressed: () {
                          setState(() {
                            if (_editEnabled != index) {
                              _editEnabled = index;
                            } else {
                              _editEnabled = -1;
                            }
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.settings),
                        tooltip: "Edit",
                        onPressed: () => widget.onEdit(repository.account),
                      ),
                    ],
                  ),
                  title: Text(account.username,
                      style: Theme.of(context).textTheme.subtitle1),
                ),
                CalendarList(
                  repository: repository,
                  selected: repository.account.id == _currentAccountId,
                  editEnabled: _editEnabled == index,
                  onCalendarSelected: (Calendar calendar) =>
                      widget.onSelectionChanged(repository.account, calendar),
                  onCalendarEnabled: (Calendar calendar, bool enabled) =>
                      setState(() {
                    repository.setEnabled(calendar, enabled);
                  }),
                  onSelectCalendars: () => setState(() {
                    _editEnabled = index;
                  }),
                ),
                if (_editEnabled == index)
                    ElevatedButton(
                        child: Text("Done"),
                        onPressed: () => setState(() {
                            _editEnabled = -1;
                        })
                    )

              ]);
            },
          );
        });
  }
}

class CalendarList extends StatelessWidget {
  CalendarList({
    Key key,
    this.repository,
    this.onCalendarSelected,
    this.onCalendarEnabled,
    this.onSelectCalendars,
    this.selected,
    this.editEnabled,
  }) : super(key: key);

  final Repository repository;
  final Function(Calendar) onCalendarSelected;
  final Function(Calendar, bool) onCalendarEnabled;
  final Function() onSelectCalendars;
  final bool selected;
  final bool editEnabled;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => repository.refreshCalendars(),
      child: StreamBuilder<List<Calendar>>(
          stream: repository.calendars(showEnabled: !editEnabled),
          builder:
              (BuildContext context, AsyncSnapshot<List<Calendar>> snapshot) {
            if (snapshot.hasError) {
              return const Text("Error!");
            } else if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }
            List<Calendar> calendars = snapshot.data;

            if (calendars.isEmpty) {
              return Center(
                  child: ElevatedButton(
                child: Text("Select Calendars"),
                onPressed: () => this.onSelectCalendars(),
              ));
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: calendars.length,
              itemBuilder: (context, index) {
                Calendar calendar = calendars[index];
                var isEnabled = repository.isEnabled(calendar);

                return ListTile(
                  leading: (editEnabled
                      ? IconButton(
                          icon: (isEnabled
                              ? Icon(Icons.favorite)
                              : Icon(Icons.favorite_outline)),
                          onPressed: () {
                            onCalendarEnabled(calendar, !isEnabled);
                          })
                      : Icon(Icons.chevron_right)),
                  title: Text(calendar.name),
                  selected:
                      (calendar.path == repository.currentCalendar?.path) &&
                          selected,
                  onTap: () {
                      if (editEnabled) {
                        onCalendarEnabled(calendar, !isEnabled);
                      } else {
                        onCalendarSelected(calendar);
                      }
                  },
                );
              },
            );
          }),
    );
  }
}
