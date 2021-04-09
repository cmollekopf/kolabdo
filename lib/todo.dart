// @dart=2.9

import 'package:flutter/material.dart';

import 'package:ical_parser/ical_parser.dart';

import 'repository.dart';

class TodoArguments {
  final Todo todo;
  final Repository repository;
  TodoArguments(this.todo, this.repository) : assert(todo != null);
}

class TodoView extends StatefulWidget {
  TodoView({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _TodoView();
}

class _TodoView extends State<TodoView> {
  Todo todo;
  Repository _repository;

  String unescape(String s) {
    return s.replaceAll("\\n", "\n");
  }

  @override
  Widget build(BuildContext context) {
    final TodoArguments args = ModalRoute.of(context).settings.arguments;

    todo = args.todo;
    _repository = args.repository;

    return Scaffold(
      appBar: AppBar(
        title: Text(todo.summary, maxLines: 2),
      ),
      body: SingleChildScrollView(
          child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          CheckboxListTile(
              value: todo.doing,
              onChanged: (state) {
                var modified = todo;
                modified.setDoing(state);
                _repository.updateTodo(modified);
                setState(() {
                  todo = modified;
                });
              },
              title: const Text("Doing"),
              controlAffinity: ListTileControlAffinity.leading),
          CheckboxListTile(
              value: todo.done,
              onChanged: (state) {},
              title: const Text("Done"),
              controlAffinity: ListTileControlAffinity.leading),
          SizedBox(height: 10),
          Text(unescape(todo.description ?? "")),
          ElevatedButton(
            child: Text("Delete"),
            onPressed: () {
              _repository.removeTodo(todo);
              Navigator.pop(context);
            },
          ),
        ]),
      )),
    );
  }
}
