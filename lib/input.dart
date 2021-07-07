import 'package:flutter/material.dart';
import 'repository.dart';

class TodoInput extends StatefulWidget {
  TodoInput({Key key, this.calendar, this.repository}) : super(key: key);

  final Calendar calendar;
  final Repository repository;

  @override
  State<StatefulWidget> createState() => _TodoInput();
}

class _TodoInput extends State<TodoInput> {
  TextEditingController _textInputController = TextEditingController();
  List<String> _suggestions = [];
  Repository _repository;
  Calendar _currentCalendar;

  void updateSuggestions() {
    if (_textInputController.text.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }
    List<String> suggestions = _repository.rawTodos
        .where((Todo todo) {
          if (todo.done && todo.summary.startsWith(_textInputController.text)) {
            return true;
          }
          return false;
        })
        .map<String>((Todo todo) => todo.summary)
        .toSet()
        .toList();

    setState(() {
      _suggestions = suggestions;
    });
  }

  void addTodo(text) async {
    //If there is an existing completed todo with the same summary, we simply set it to not done
    Iterable<Todo> existing = _repository.rawTodos.where((Todo todo) {
      if (todo.summary == _textInputController.text) {
        return true;
      }
      return false;
    });
    if (!existing.isEmpty) {
      Todo t = existing.first;
      t.done = false;
      _repository.updateTodo(t);
    } else {
      await _repository.createTodo(Todo.newTodo(text, _currentCalendar.path,
          isDoing: _repository.showDoing));
    }
    _textInputController.clear();
  }

  @override
  void initState() {
    super.initState();
    _textInputController.addListener(updateSuggestions);
  }

  @override
  void dispose() {
    _textInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _repository = widget.repository;
    _currentCalendar = widget.calendar;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            children: List<Widget>.generate(
              _suggestions.length,
              (int index) {
                return ChoiceChip(
                  label: Text(_suggestions[index]),
                  selected: false,
                  onSelected: (bool selected) async {
                    await addTodo(_suggestions[index]);
                  },
                );
              },
            ).toList(),
          ),
          Row(
            children: [
              Flexible(
                  child: TextField(
                      controller: _textInputController,
                      autofocus: true,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(), hintText: 'Add a todo'),
                      onSubmitted: (text) async {
                        await addTodo(text);
                        //TODO refocus the edit instead of pop
                        Navigator.pop(context);
                      })),
              ElevatedButton(
                child: Icon(Icons.add),
                onPressed: () async => await addTodo(_textInputController.text),
                style: ElevatedButton.styleFrom(
                  shape: CircleBorder(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
