import 'package:flutter/material.dart';
import 'repository.dart';
import 'accounts.dart';

class LoginDialog extends StatefulWidget {
  LoginDialog({Key key, this.account}) : super(key: key);

  @override
  LoginDialogState createState() {
    return LoginDialogState();
  }

  final Account account;
}

class LoginDialogState extends State<LoginDialog> {
  final _formKey = GlobalKey<FormState>();
  Account _account;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
  }

  @override
  Widget build(BuildContext context) {
    String server;
    String username;
    String password;

    return Scaffold(
        appBar: AppBar(
          title: Text('Login'),
        ),
        body: Center(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    TextFormField(
                      onSaved: (String value) {
                        server = value;
                      },
                      initialValue: _account.server,
                      decoration: const InputDecoration(
                        hintText: 'Your server',
                        labelText: 'Server',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      onSaved: (String value) {
                        username = value;
                      },
                      initialValue: _account.username,
                      decoration: const InputDecoration(
                        icon: Icon(Icons.person),
                        hintText: 'Your username',
                        labelText: 'Username',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      onSaved: (String value) {
                        password = value;
                      },
                      initialValue: _account.password,
                      decoration: const InputDecoration(
                        icon: Icon(Icons.vpn_key),
                        hintText: 'Your password',
                        labelText: 'Password',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                      enableSuggestions: false,
                      autocorrect: false,
                      // obscureText: true,
                    ),
                    ElevatedButton(
                      child: Text('Submit'),
                      onPressed: () async {
                        // Validate returns true if the form is valid, or false otherwise.
                        if (_formKey.currentState.validate()) {
                          _formKey.currentState.save();
                          if (await Repository.test(
                              server, username, password)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Success!')));
                            Account account = Account.create(
                                server: server,
                                username: username,
                                password: password);
                            Navigator.pop(context, account);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text('Your credentials are garbage =(')));
                          }
                        }
                      },
                    ),
                  ],
                ),
              )),
        ));
  }
}
