import 'package:flutter/material.dart';
import 'repository.dart';
import 'accounts.dart';

class LoginDialog extends StatefulWidget {
  LoginDialog({Key key, this.account, this.onDone = null}) : super(key: key);

  @override
  LoginDialogState createState() {
    return LoginDialogState();
  }

  final Account account;
  final Function(Account) onDone;
}

class LoginDialogState extends State<LoginDialog> {
  final _formKey = GlobalKey<FormState>();
  Account _account;
  bool _isObscure = true;

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
        body: SingleChildScrollView(
            child: Center(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 60.0),
                      child: Center(
                        child: Container(
                            width: 100,
                            height: 100,
                            child: Image.asset('logo.png')),
                      ),
                    ),
                    SizedBox(
                      height: 20,
                    ),
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
                      keyboardType: TextInputType.emailAddress,
                      onSaved: (String value) {
                        username = value;
                      },
                      initialValue: _account.username,
                      decoration: const InputDecoration(
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
                      keyboardType: TextInputType.visiblePassword,
                      onSaved: (String value) {
                        password = value;
                      },
                      initialValue: _account.password,
                      decoration: InputDecoration(
                        hintText: 'Your password',
                        labelText: 'Password',
                        suffixIcon: IconButton(
                            icon: Icon(_isObscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _isObscure = !_isObscure;
                              });
                            }),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                      enableSuggestions: false,
                      autocorrect: false,
                      obscureText: _isObscure,
                    ),
                    SizedBox(
                      height: 50,
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                        textStyle: TextStyle(fontSize: 20),
                      ),
                      child: Text('Login'),
                      onPressed: () async {
                        // Validate returns true if the form is valid, or false otherwise.
                        if (_formKey.currentState.validate()) {
                          _formKey.currentState.save();
                          if (await Repository.test(
                              server, username, password)) {
                            Account account = Account.create(
                                server: server,
                                username: username,
                                password: password);

                            if (widget.onDone != null) {
                              widget.onDone(account);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Success!')));
                              Navigator.pop(context, account);
                            }
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
        )));
  }
}
