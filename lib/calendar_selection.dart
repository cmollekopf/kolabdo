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
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              Account account = accounts[index];
              Repository repository = Repository(account);

              return Column(children: [
                ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.menu),
                    tooltip: "Edit",
                    onPressed: () => widget.onEdit(repository.account),
                  ),
                  title: Text(account.username,
                      style: Theme.of(context).textTheme.subtitle1),
                ),
                CalendarList(
                  repository: repository,
                  selected: repository.account.id == _currentAccountId,
                  onCalendarSelected: (Calendar calendar) =>
                      widget.onSelectionChanged(repository.account, calendar),
                ),
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
    this.selected,
  }) : super(key: key);

  final Repository repository;
  final Function(Calendar) onCalendarSelected;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => repository.refreshCalendars(),
      child: StreamBuilder<List<Calendar>>(
          stream: repository.calendars(),
          builder:
              (BuildContext context, AsyncSnapshot<List<Calendar>> snapshot) {
            if (snapshot.hasError) {
              return const Text("Error!");
            } else if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }
            List<Calendar> calendars = snapshot.data;

            return ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: calendars.length,
              itemBuilder: (context, index) {
                Calendar calendar = calendars[index];

                return ListTile(
                  leading: Icon(Icons.format_list_bulleted_rounded),
                  title: Text(calendar.name),
                  selected:
                      (calendar.path == repository.currentCalendar?.path) &&
                          selected,
                  onTap: () => onCalendarSelected(calendar),
                );
              },
            );
          }),
    );
  }
}
