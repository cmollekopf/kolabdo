// @dart=2.9

import 'package:flutter/material.dart';
import 'package:random_color/random_color.dart';
import 'todo.dart';
import 'repository.dart';

class TodoList extends StatefulWidget {
  TodoList({Key key, this.calendar, this.repository}) : super(key: key);

  final Calendar calendar;
  final Repository repository;

  @override
  State<StatefulWidget> createState() => _TodoList();
}

class _TodoList extends State<TodoList> {
  List<Color> _randomColors;

  List<Color> initializeColors() {
    //Fixed a seed that seems to result in decent colors
    RandomColor randomColor = RandomColor(6);
    return Iterable<Color>.generate(
            20, (index) => randomColor.randomColor(colorHue: ColorHue.blue))
        .toList();
  }

  Color getColor(BuildContext context, Todo todo) {
    return todo.done
        ? Theme.of(context).buttonColor
        : _randomColors[todo.id.hashCode.remainder(_randomColors.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _randomColors = initializeColors();
  }

  @override
  Widget build(BuildContext context) {
    Repository _repository = widget.repository;
    return RefreshIndicator(
      child: StreamBuilder<List<Todo>>(
          stream: _repository.todos(),
          builder: (BuildContext context, AsyncSnapshot<List<Todo>> snapshot) {
            if (snapshot.hasError) {
              return const Text("Error!");
            } else if (snapshot.data == null) {
              return Center(child: CircularProgressIndicator());
            }

            if (true) {
              return GridView.builder(
                  padding: const EdgeInsets.only(top: 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, childAspectRatio: 1 / 1),
                  itemCount: snapshot.data.length,
                  itemBuilder: (BuildContext ctx, index) {
                    Todo todo = snapshot.data[index];

                    return Card(
                      color: getColor(context, todo),
                      child: InkWell(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.topLeft,
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  todo.summary.toLowerCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18.0,
                                  ),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ]),
                        ),
                        onTap: () async {
                          todo.setDone(!todo.done);
                          _repository.updateTodo(todo);
                        },
                        onLongPress: () => Navigator.pushNamed(context, '/todo',
                            arguments: TodoArguments(todo, _repository)),
                      ),
                    );
                  });
            }

            return ListView.builder(
                shrinkWrap: true,
                itemCount: snapshot.data.length,
                itemBuilder: (context, index) {
                  Todo todo = snapshot.data[index];

                  return CheckboxListTile(
                    title: Text(todo.summary),
                    subtitle: Text(todo.dateTime?.toString() ?? 'N/A'),
                    value: todo.done,
                    onChanged: (newValue) {
                      todo.setDone(newValue);
                      _repository.updateTodo(todo);
                    },
                    // onTap: () => Navigator.pushNamed(context, '/todo',
                    //     arguments: TodoArguments(todo)),
                  );
                });
          }),
      onRefresh: () => _repository.refresh(),
    );
  }
}
