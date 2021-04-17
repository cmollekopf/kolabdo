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
    String description = todo.description ?? "";
    description =
        description.isEmpty ? "No description." : unescape(description);

    return Scaffold(
      appBar: AppBar(title: Text("Details", maxLines: 2), actions: <Widget>[
        IconButton(
          icon: Icon(todo.done ? Icons.check_box : Icons.check_box_outlined),
          tooltip: "Done",
          onPressed: () {
            var modified = todo;
            modified.setDone(!todo.done);
            _repository.updateTodo(modified);
            setState(() {
              todo = modified;
            });
          },
        ),
        IconButton(
          icon: Icon(todo.doing ? Icons.bookmark_border : Icons.bookmark),
          tooltip: "Set task as doing",
          onPressed: () {
            var modified = todo;
            modified.setDoing(!todo.doing);
            _repository.updateTodo(modified);
            setState(() {
              todo = modified;
            });
          },
        ),
        IconButton(
          icon: Icon(Icons.delete),
          onPressed: () {
            _repository.removeTodo(todo);
            Navigator.pop(context);
          },
        ),
      ]),
      body: SingleChildScrollView(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(
            todo.summary,
            style: Theme.of(context).textTheme.title,
          ),
          SizedBox(height: 16),
          Text(description),
        ]),
      )),
    );
  }
}
