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
    _currentAccount.then((Account current) => {_currentAccountId = current.id});
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

              return CalendarList(
                repository: repository,
                selected: repository.account.id == _currentAccountId,
                onCalendarSelected: (Calendar calendar) =>
                    widget.onSelectionChanged(repository.account, calendar),
                onEdit: widget.onEdit,
                title: account.username,
              );
            },
          );
        });
  }
}

class CalendarList extends StatefulWidget {
  CalendarList(
      {Key key,
      this.repository,
      this.onCalendarSelected,
      this.onEdit,
      this.selected,
      this.title})
      : super(key: key);

  final Repository repository;
  final Function(Calendar) onCalendarSelected;
  final Function(Account) onEdit;
  final bool selected;
  final String title;

  @override
  State<StatefulWidget> createState() => _CalendarList();
}

class _CalendarList extends State<CalendarList> {
  Repository repository;
  bool editEnabled = false;

  @override
  void initState() {
    super.initState();

    repository = widget.repository;
    editEnabled = false;
  }

  void onCalendarEnabled(Calendar calendar, bool enabled) {
    setState(() {
      repository.setEnabled(calendar, enabled);
    });
  }

  void onSelectCalendars() {
    setState(() {
      editEnabled = !editEnabled;
    });
  }

  Widget buildCalendarList(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => repository.refreshCalendars(),
      child: StreamBuilder<List<Calendar>>(
          stream: repository.calendars(showEnabled: !editEnabled),
          builder:
              (BuildContext context, AsyncSnapshot<List<Calendar>> snapshot) {
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return const Text("Error!");
            }

            List<Calendar> calendars = snapshot.data;

            if (calendars.isEmpty) {
              if (!editEnabled) {
                //We can't just directly change the state while building the current state, so we schedule a call after the frame.
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => setState(() => editEnabled = true));
              }

              //This button is now largely pointless since we never show an empty list.
              return Center(
                  child: ElevatedButton(
                child: Text("Select Calendars"),
                onPressed: () => onSelectCalendars(),
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
                          widget.selected,
                  onTap: () {
                    if (editEnabled) {
                      onCalendarEnabled(calendar, !isEnabled);
                    } else {
                      widget.onCalendarSelected(calendar);
                    }
                  },
                );
              },
            );
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon:
                    Icon(editEnabled ? Icons.favorite : Icons.favorite_outline),
                tooltip: "Edit",
                onPressed: onSelectCalendars),
            IconButton(
              icon: Icon(Icons.settings),
              tooltip: "Edit",
              onPressed: () => widget.onEdit(repository.account),
            ),
          ],
        ),
        title: Text(widget.title, style: Theme.of(context).textTheme.subtitle1),
      ),
      buildCalendarList(context),
      if (editEnabled)
        ElevatedButton(
            child: Text("Done"),
            onPressed: () => setState(() {
                  editEnabled = false;
                }))
    ]);
  }
}
