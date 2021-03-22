// @dart=2.9

import 'package:flutter/material.dart';

import 'package:ical_parser/ical_parser.dart';

import 'repository.dart';

/// Todo route arguments.
class TodoArguments {
  final Todo todo;
  // ignore: public_member_api_docs
  TodoArguments(this.todo) : assert(todo != null);
}

class TodoView extends StatelessWidget {
  /// A single data row.
  Widget row(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Row(children: [
        Text('$title: '),
        Text(value ?? 'N/A'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TodoArguments args = ModalRoute.of(context).settings.arguments;
    Todo todo = args.todo;

    return Scaffold(
      appBar: AppBar(
        title: Text(todo.id),
      ),
      body: SingleChildScrollView(
          child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          // row('Triggered application open', args.openedApplication.toString()),

          row('Todo ID', todo.id),
          /* row('Sender ID', todo.senderId), */
          /* row('Category', todo.category), */
          /* row('Collapse Key', todo.collapseKey), */
          /* row('Content Available', todo.contentAvailable.toString()), */
          /* row('Data', todo.data.toString()), */
          /* row('From', todo.from), */
          /* row('Todo ID', todo.todoId), */
          /* row('Sent Time', todo.sentTime?.toString()), */
          /* row('Thread ID', todo.threadId), */
          /* row('Time to Live (TTL)', todo.ttl?.toString()), */
          /* if (notification != null) ...[ */
          /*   Padding( */
          /*     padding: const EdgeInsets.only(top: 16), */
          /*     child: Column(children: [ */
          /*       const Text( */
          /*         'Remote Notification', */
          /*         style: TextStyle(fontSize: 18), */
          /*       ), */
          /*       row( */
          /*         'Title', */
          /*         notification.title, */
          /*       ), */
          /*       row( */
          /*         'Body', */
          /*         notification.body, */
          /*       ), */
          /*       if (notification.android != null) ...[ */
          /*         const Text( */
          /*           'Android Properties', */
          /*           style: TextStyle(fontSize: 18), */
          /*         ), */
          /*         row( */
          /*           'Channel ID', */
          /*           notification.android.channelId, */
          /*         ), */
          /*         row( */
          /*           'Click Action', */
          /*           notification.android.clickAction, */
          /*         ), */
          /*         row( */
          /*           'Color', */
          /*           notification.android.color, */
          /*         ), */
          /*         row( */
          /*           'Count', */
          /*           notification.android.count?.toString(), */
          /*         ), */
          /*         row( */
          /*           'Image URL', */
          /*           notification.android.imageUrl, */
          /*         ), */
          /*         row( */
          /*           'Link', */
          /*           notification.android.link, */
          /*         ), */
          /*         row( */
          /*           'Priority', */
          /*           notification.android.priority?.toString(), */
          /*         ), */
          /*         row( */
          /*           'Small Icon', */
          /*           notification.android.smallIcon, */
          /*         ), */
          /*         row( */
          /*           'Sound', */
          /*           notification.android.sound, */
          /*         ), */
          /*         row( */
          /*           'Ticker', */
          /*           notification.android.ticker, */
          /*         ), */
          /*         row( */
          /*           'Visibility', */
          /*           notification.android.visibility?.toString(), */
          /*         ), */
          /*       ], */
          /*       if (notification.apple != null) ...[ */
          /*         const Text( */
          /*           'Apple Properties', */
          /*           style: TextStyle(fontSize: 18), */
          /*         ), */
          /*         row( */
          /*           'Subtitle', */
          /*           notification.apple.subtitle, */
          /*         ), */
          /*         row( */
          /*           'Badge', */
          /*           notification.apple.badge, */
          /*         ), */
          /*         row( */
          /*           'Sound', */
          /*           notification.apple.sound?.name, */
          /*         ), */
          /*       ] */
          /*     ]), */
          /*   ) */
          /* ] */
        ]),
      )),
    );
  }
}
