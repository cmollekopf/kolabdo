import 'dart:async';
import 'dart:convert';
import 'package:localstorage/localstorage.dart';
import 'package:uuid/uuid.dart';

class Account {
  final String id;

  String server = "caldav.kolabnow.com";
  String username;
  String password;

  Account(this.id, {this.server, this.username, this.password});

  factory Account.create({server, username, password}) {
    return Account(Uuid().v4(),
        server: server, username: username, password: password);
  }

  toJson() => {
        'id': id,
        'server': server,
        'username': username,
        'password': password,
      };

  static Future<List<Account>> listAccounts() async {
    LocalStorage storage = LocalStorage("accounts.json");
    await storage.ready;
    var item = storage.getItem("accounts");
    if (item == null) {
      return [];
    }

    List<Account> accounts = [];
    for (String id in item['ids']) {
      Account account = await loadAccount(id);
      if (account.username == null) {
        print("Invalid account $id");
      } else {
        accounts.add(account);
      }
    }
    return accounts;
  }

  static Future<Account> loadAccount(id) async {
    LocalStorage storage = LocalStorage("accounts.json");
    await storage.ready;
    var map2 = storage.getItem(id);
    return Account(
      map2["id"],
      server: map2["server"],
      username: map2["username"],
      password: map2["password"],
    );
  }

  static Future<Account> loadCurrent() async {
    LocalStorage storage = LocalStorage("accounts.json");
    await storage.ready;
    var id = storage.getItem("currentAccount");
    if (id == null) {
      return Account.create();
    }
    return await loadAccount(id);
  }

  static Future<void> store(Account account) async {
    LocalStorage storage = LocalStorage("accounts.json");
    await storage.ready;
    assert(account.server != null);
    assert(account.username != null);
    assert(account.password != null);
    storage.setItem(account.id, account);
  }

  static Future<void> setCurrent(Account account) async {
    LocalStorage storage = LocalStorage("accounts.json");
    await storage.ready;
    storage.setItem("currentAccount", account.id);

    var map = storage.getItem("accounts");

    List<String> accounts = [];
    if (map != null) {
      accounts = (map['ids'] as List)?.map((id) => id as String).toList();
    }

    if (!accounts.contains(account.id)) {
      storage.setItem("accounts", {
        'ids': [...accounts, account.id]
      });
    }
  }
}
