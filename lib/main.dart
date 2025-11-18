// lib/main.dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(BloodBankApp());

class BloodBankApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blood Bank',
      theme: ThemeData(primarySwatch: Colors.red),
      home: HomeScreen(),
    );
  }
}

/* --- Model --- */
class Donor {
  int? id;
  String name;
  String bloodGroup;
  String phone;
  String? city;
  int? age;
  String? notes;

  Donor({
    this.id,
    required this.name,
    required this.bloodGroup,
    required this.phone,
    this.city,
    this.age,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'blood_group': bloodGroup,
      'phone': phone,
      'city': city,
      'age': age,
      'notes': notes,
    };
  }

  factory Donor.fromMap(Map<String, dynamic> m) => Donor(
    id: m['id'] as int?,
    name: m['name'] as String,
    bloodGroup: m['blood_group'] as String,
    phone: m['phone'] as String,
    city: m['city'] as String?,
    age: m['age'] as int?,
    notes: m['notes'] as String?,
  );
}

/* --- DB Helper (simple) --- */
class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'bloodbank.db');
    return await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE donors(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          blood_group TEXT,
          phone TEXT,
          city TEXT,
          age INTEGER,
          notes TEXT
        )
      ''');
    });
  }

  Future<int> insertDonor(Donor d) async {
    final database = await db;
    return await database.insert('donors', d.toMap());
  }

  Future<List<Donor>> getDonors({String? q, String? blood}) async {
    final database = await db;
    String where = '';
    List<dynamic> args = [];
    if (q != null && q.isNotEmpty) {
      where += "name LIKE ?";
      args.add('%$q%');
    }
    if (blood != null && blood.isNotEmpty) {
      if (where.isNotEmpty) where += ' AND ';
      where += "blood_group = ?";
      args.add(blood);
    }
    final res = await database.query('donors',
        where: where.isEmpty ? null : where,
        whereArgs: args.isEmpty ? null : args);
    return res.map((m) => Donor.fromMap(m)).toList();
  }

  Future<int> updateDonor(Donor d) async {
    final database = await db;
    return await database
        .update('donors', d.toMap(), where: 'id = ?', whereArgs: [d.id]);
  }

  Future<int> deleteDonor(int id) async {
    final database = await db;
    return await database.delete('donors', where: 'id = ?', whereArgs: [id]);
  }
}

/* --- Home Screen --- */
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DBHelper _db = DBHelper();
  List<Donor> donors = [];
  String search = '';
  String bloodFilter = '';

  final bloodGroups = ['', 'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    donors = await _db.getDonors(q: search, blood: bloodFilter.isEmpty ? null : bloodFilter);
    setState(() {});
  }

  void _openAdd() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditScreen()));
    await refresh();
  }

  void _edit(Donor d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditScreen(donor: d)));
    await refresh();
  }

  void _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _sms(String phone) async {
    final uri = Uri.parse('sms:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Blood Bank'),
        actions: [
          DropdownButton<String>(
            value: bloodFilter,
            underline: SizedBox(),
            onChanged: (v) {
              bloodFilter = v ?? '';
              refresh();
            },
            items: bloodGroups
                .map((g) => DropdownMenuItem(child: Text(g.isEmpty ? 'All' : g), value: g))
                .toList(),
          ),
          SizedBox(width: 8)
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name...'),
              onChanged: (v) {
                search = v;
                refresh();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: donors.isEmpty
                  ? ListView(children: [SizedBox(height: 200), Center(child: Text('No donors yet'))])
                  : ListView.builder(
                itemCount: donors.length,
                itemBuilder: (_, i) {
                  final d = donors[i];
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(d.bloodGroup, style: TextStyle(fontSize: 12)),
                        backgroundColor: Colors.red[100],
                      ),
                      title: Text(d.name),
                      subtitle: Text('${d.city ?? ''} • ${d.age ?? ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: Icon(Icons.call), onPressed: () => _call(d.phone)),
                        IconButton(icon: Icon(Icons.message), onPressed: () => _sms(d.phone)),
                        IconButton(icon: Icon(Icons.edit), onPressed: () => _edit(d)),
                        IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () async {
                              if (d.id != null) {
                                await _db.deleteDonor(d.id!);
                                refresh();
                              }
                            }),
                      ]),
                    ),
                  );
                },
              ),
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _openAdd, child: Icon(Icons.add)),
    );
  }
}

/* --- Add / Edit Screen --- */
class AddEditScreen extends StatefulWidget {
  final Donor? donor;
  AddEditScreen({this.donor});
  @override
  _AddEditScreenState createState() => _AddEditScreenState();
}

class _AddEditScreenState extends State<AddEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final DBHelper _db = DBHelper();

  late TextEditingController nameC;
  late TextEditingController phoneC;
  late TextEditingController cityC;
  late TextEditingController ageC;
  late TextEditingController notesC;
  String blood = 'A+';

  @override
  void initState() {
    super.initState();
    final d = widget.donor;
    nameC = TextEditingController(text: d?.name ?? '');
    phoneC = TextEditingController(text: d?.phone ?? '');
    cityC = TextEditingController(text: d?.city ?? '');
    ageC = TextEditingController(text: d?.age?.toString() ?? '');
    notesC = TextEditingController(text: d?.notes ?? '');
    blood = d?.bloodGroup ?? 'A+';
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    final d = Donor(
      id: widget.donor?.id,
      name: nameC.text.trim(),
      bloodGroup: blood,
      phone: phoneC.text.trim(),
      city: cityC.text.trim(),
      age: ageC.text.isEmpty ? null : int.tryParse(ageC.text),
      notes: notesC.text.trim(),
    );
    if (widget.donor == null) await _db.insertDonor(d);
    else await _db.updateDonor(d);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];
    return Scaffold(
      appBar: AppBar(title: Text(widget.donor == null ? 'Add Donor' : 'Edit Donor')),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            TextFormField(controller: nameC, decoration: InputDecoration(labelText: 'Name'), validator: (v) => v!.isEmpty ? 'Enter name' : null),
            SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: blood,
              items: groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (v) => setState(() => blood = v ?? blood),
              decoration: InputDecoration(labelText: 'Blood Group'),
            ),
            SizedBox(height: 8),
            TextFormField(controller: phoneC, decoration: InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? 'Enter phone' : null),
            SizedBox(height: 8),
            TextFormField(controller: ageC, decoration: InputDecoration(labelText: 'Age'), keyboardType: TextInputType.number),
            SizedBox(height: 8),
            TextFormField(controller: cityC, decoration: InputDecoration(labelText: 'City')),
            SizedBox(height: 8),
            TextFormField(controller: notesC, decoration: InputDecoration(labelText: 'Notes'), maxLines: 3),
            SizedBox(height: 12),
            ElevatedButton(onPressed: _save, child: Text('Save'))
          ]),
        ),
      ),
    );
  }
}

