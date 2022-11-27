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
  TextEditingController _summaryController;
  TextEditingController _descriptionController;
  FocusNode _focusNode;

  String unescape(String s) {
    return s.replaceAll("\\n", "\n");
  }

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController();
    _descriptionController = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TodoArguments args = ModalRoute.of(context).settings.arguments;

    todo = args.todo;

    _repository = args.repository;
    String description = todo.description ?? "";
    description = unescape(description);

    _summaryController.text = todo.summary;
    _descriptionController.text = description;

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
          TextField(
            decoration: InputDecoration(
              labelText: 'Summary',
            ),
            controller: _summaryController,
            onSubmitted: (String value) async {
              _focusNode.requestFocus();
            },
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: 16),
          TextField(
            focusNode: _focusNode,
            keyboardType: TextInputType.multiline,
            maxLines: null,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'No description.',
            ),
            controller: _descriptionController,
          ),
          ButtonBar(children: [
            OutlinedButton(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 20),
              ),
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Discard'),
            ),
            ElevatedButton(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 20),
              ),
              onPressed: () {
                var modified = todo;
                modified.summary = _summaryController.text;
                modified.description = _descriptionController.text;
                _repository.updateTodo(modified);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ]),
        ]),
      )),
    );
  }
}
