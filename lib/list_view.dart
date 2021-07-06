// @dart=2.9

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:random_color/random_color.dart';
import 'todo.dart';
import 'repository.dart';

class TodoList extends StatefulWidget {
  TodoList({Key key, this.calendar, this.repository, this.showGrid})
      : super(key: key);

  final Calendar calendar;
  final Repository repository;
  final bool showGrid;

  @override
  State<StatefulWidget> createState() => _TodoList();
}

class _TodoList extends State<TodoList> {
  List<Color> _randomColors;
  List<Todo> _stagedUpdates = [];

  Timer _updateTimeout;
  int _fadeOutDuration = 600;

  void processUpdates() {
    Repository _repository = widget.repository;
    for (var todo in _stagedUpdates) {
      todo.setDone(!todo.done);
      _repository.updateTodo(todo);
    }
    _stagedUpdates = [];
    _updateTimeout.cancel();
  }

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
  void dispose() {
    super.dispose();
    _updateTimeout.cancel();
    processUpdates();
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

            if (widget.showGrid) {
              return GridView.builder(
                  padding: const EdgeInsets.only(top: 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, childAspectRatio: 1 / 1),
                  itemCount: snapshot.data.length,
                  itemBuilder: (BuildContext ctx, index) {
                    Todo todo = snapshot.data[index];
                    bool removing = _stagedUpdates.contains(todo);
                    return AnimatedOpacity(
                      opacity: removing ? 0.1 : 1.0,
                      duration: Duration(milliseconds: _fadeOutDuration),
                      curve: Curves.fastOutSlowIn,
                      child: Card(
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
                            //We fade out the item, so we don't remove it immediately
                            setState(() {
                              _stagedUpdates.add(todo);

                              // Stage updates with some delay. This allows tapping several items before the layout changes.
                              if (_updateTimeout != null) {
                                _updateTimeout.cancel();
                              }
                              _updateTimeout =
                                  Timer(Duration(milliseconds: _fadeOutDuration + 100), () {
                                processUpdates();
                              });
                            });
                          },
                          onLongPress: () => Navigator.pushNamed(
                              context, '/todo',
                              arguments: TodoArguments(todo, _repository)),
                        ),
                      ),
                    );
                  });
            }

            return ListView.builder(
                shrinkWrap: true,
                itemCount: snapshot.data.length,
                itemBuilder: (context, index) {
                  Todo todo = snapshot.data[index];

                  return ListTile(
                    contentPadding: EdgeInsets.fromLTRB(0, 2, 2, 16),
                    title: Text(todo.summary,
                        style: TextStyle(
                          color: todo.done
                              ? Theme.of(context).disabledColor
                              : null,
                        )),
                    leading: Checkbox(
                      fillColor:
                          MaterialStateProperty.all(getColor(context, todo)),
                      value: todo.done,
                      onChanged: (newValue) {
                        todo.setDone(newValue);
                        _repository.updateTodo(todo);
                      },
                    ),
                    onTap: () => Navigator.pushNamed(context, '/todo',
                        arguments: TodoArguments(todo, _repository)),
                  );
                });
          }),
      onRefresh: () => _repository.refresh(),
    );
  }
}
