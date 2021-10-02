import 'package:test/test.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/accounts.dart';
import '../lib/repository.dart';

String userPrincipalResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:card="urn:ietf:params:xml:ns:carddav">
    <d:response>
        <d:href>/</d:href>
        <d:propstat>
            <d:prop>
                <d:current-user-principal>
                    <d:href>/principals/test1@kolab.org/</d:href>
                </d:current-user-principal>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
    </d:response>
</d:multistatus>''';

String calendarResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
    <d:response>
        <d:href>/calendars/johndoe/home/</d:href>
        <d:propstat>
            <d:prop>
                <d:displayname>Home calendar</d:displayname>
                <cs:getctag>3145</cs:getctag>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
    </d:response>
</d:multistatus>''';

String todoResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:card="urn:ietf:params:xml:ns:carddav"><d:response><d:href>/calendars/test1@kolab.org/f700fa68-3eb8-4b4f-9816-4741b712d398/%7b37af7f9d-65b5-434f-9b28-3e165eda7cee%7d.ics</d:href><d:propstat><d:prop><cal:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Kolab//iRony DAV Server 0.4.3//Sabre//Sabre VObject 3.5.3//EN
CALSCALE:GREGORIAN
BEGIN:VTODO
UID:{37af7f9d-65b5-434f-9b28-3e165eda7cee}
DTSTAMP:20210402T172433Z
CREATED:20210329T081421Z
LAST-MODIFIED:20210402T172433Z
SUMMARY:another new todo
SEQUENCE:3
STATUS:COMPLETED
CLASS:PUBLIC
PERCENT-COMPLETE:100
COMPLETED:20210402T172433Z
ORGANIZER;CN=John Doe:mailto:mailto
END:VTODO
END:VCALENDAR
</cal:calendar-data><d:getetag>"b634d9dafc712905-149-0"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response><d:response><d:href>/calendars/test1@kolab.org/f700fa68-3eb8-4b4f-9816-4741b712d398/180de4d7-f88f-484f-bb9f-c9a4ee525f17.ics</d:href><d:propstat><d:prop><cal:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Kolab//iRony DAV Server 0.4.3//Sabre//Sabre VObject 3.5.3//EN
CALSCALE:GREGORIAN
BEGIN:VTODO
UID:180de4d7-f88f-484f-bb9f-c9a4ee525f17
DTSTAMP:20210402T172436Z
CREATED:20210331T214146Z
LAST-MODIFIED:20210402T172436Z
SUMMARY:summary
SEQUENCE:0
STATUS:COMPLETED
CLASS:PUBLIC
PERCENT-COMPLETE:100
COMPLETED:20210402T172436Z
END:VTODO
END:VCALENDAR
</cal:calendar-data><d:getetag>"24e11d7f50cdb63d-201-0"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>''';

MockClient responsesMock(var responses) {
  return MockClient((http.Request request) {
    print(request);
    print(request.body);
    print(request.method);
    var response = responses.first;
    responses.remove(response);
    return Future.value(response);
  });
}

void main() {
  test('test repo initialization', () async {
    var httpMock = responsesMock([http.Response(calendarResponse, 207)]);

    var account = Account.create(
        server: "server", username: "username", password: "password");
    var repo = Repository(account, httpClient: httpMock);
    await repo.ready;
    expect(repo.rawTodos, null);
    await repo.initialized;
    expect(repo.rawCalendars, isNotNull);
    expect(repo.rawCalendars.length, 1);
    expect(repo.rawTodos, []);
  });

  test('test todo initialization', () async {
    var httpMock = responsesMock([
      http.Response(calendarResponse, 207),
      http.Response(todoResponse, 207),
      http.Response(todoResponse, 207)
    ]);

    var account = Account.create(
        server: "server", username: "username", password: "password");
    var repo = Repository(account, httpClient: httpMock);
    await repo.ready;
    await repo.initialized;
    expect(repo.rawCalendars, isNotNull);
    expect(repo.rawCalendars.length, 1);
    //Set current calendar and fetch
    await repo.setCalendar(repo.rawCalendars[0]);
    expect(repo.currentCalendar, isNotNull);
    expect(repo.rawTodos.length, 2);
    //Fetch again
    await repo.updateTodos(repo.currentCalendar);
    expect(repo.rawTodos.length, 2);
  });

  //TODO test  await repo.updateTodos(Calendar("path", "name", "ctag")); => should create a new todo with a response containing one

  test('test todo replay', () async {
    //TODO callback for responses
    var httpMock = responsesMock([http.Response(calendarResponse, 207)]);

    var account = Account.create(
        server: "server", username: "username", password: "password");
    var repo = Repository(account, httpClient: httpMock);
    await repo.initialized;

    // var todo = Todo.newTodo("summary", "path", isDoing: false);
    // repo.createTodo(todo);
    //TODO test that we send what we expect to the server
  });

  test('test todo serialization', () async {
    var jsonEncodable = {
      "json": {
        "VERSION": "2.0",
        "PRODID":
            "-//Kolab//iRony DAV Server 0.4.3//Sabre//Sabre VObject 3.5.3//EN",
        "CALSCALE": "GREGORIAN",
        "VTODO": [
          {
            "UID": "95166594-ea23-4c29-bb79-a75281f3221d",
            "DTSTAMP": "20210920T225403Z",
            "CREATED": "20210402T171039Z",
            "LAST-MODIFIED": "20210920T225403Z",
            "SUMMARY": "ggfdss",
            "DESCRIPTION": "sdfsdf2345",
            "SEQUENCE": 8,
            "STATUS": "NEEDS-ACTION",
            "CLASS": "PUBLIC"
          }
        ]
      },
      "path":
          "/calendars/test1@kolab.org/f700fa68-3eb8-4b4f-9816-4741b712d398/95166594-ea23-4c29-bb79-a75281f3221d.ics",
      "etag": "\"24e11d7f50cdb63d-200-0\""
    };

    var todo = Todo.fromJSONEncodable(jsonEncodable);

    expect(todo.sequence, 8);
  });

  test('test string sequence', () async {
    var jsonEncodable = {
      "json": {
        "VERSION": "2.0",
        "PRODID":
            "-//Kolab//iRony DAV Server 0.4.3//Sabre//Sabre VObject 3.5.3//EN",
        "CALSCALE": "GREGORIAN",
        "VTODO": [
          {
            "UID": "95166594-ea23-4c29-bb79-a75281f3221d",
            "DTSTAMP": "20210920T225403Z",
            "CREATED": "20210402T171039Z",
            "LAST-MODIFIED": "20210920T225403Z",
            "SUMMARY": "ggfdss",
            "DESCRIPTION": "sdfsdf2345",
            "SEQUENCE": "8",
            "STATUS": "NEEDS-ACTION",
            "CLASS": "PUBLIC"
          }
        ]
      },
      "path":
          "/calendars/test1@kolab.org/f700fa68-3eb8-4b4f-9816-4741b712d398/95166594-ea23-4c29-bb79-a75281f3221d.ics",
      "etag": "\"24e11d7f50cdb63d-200-0\""
    };

    var todo = Todo.fromJSONEncodable(jsonEncodable);

    expect(todo.sequence, 8);
  });
}
