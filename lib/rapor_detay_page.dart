import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RaporDetayPage extends StatefulWidget {
  final String title;
  final String centralUrl;
  final String username;
  final String storedProc;
  final Map<String, dynamic> parameters;

  const RaporDetayPage({
    super.key,
    required this.title,
    required this.centralUrl,
    required this.username,
    required this.storedProc,
    required this.parameters,
  });

  @override
  State<RaporDetayPage> createState() => _RaporDetayPageState();
}

class _RaporDetayPageState extends State<RaporDetayPage> {
  bool loading = true;
  String? error;

  List<String> columns = [];
  List<Map<String, dynamic>> rows = [];
  List<String> visibleColumns = [];

  final Map<String, String> _columnFilters = {};

  int _currentPage = 1;
  final int _rowsPerPage = 15;

  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final limit = prefs.getInt('recordLimit') ?? 50;

      final uri = Uri.parse("${widget.centralUrl}/report/run");
      final body = jsonEncode({
        "Username": widget.username,
        "StoredProc": widget.storedProc,
        "Parameters": widget.parameters,
      });

      final res = await http.post(uri,
          headers: {"Content-Type": "application/json"}, body: body);

      final b = jsonDecode(res.body);

      if (b["success"] == true) {
        setState(() {
          columns = List<String>.from(b["columns"] ?? []);
          visibleColumns = List.from(columns);
          rows = List<Map<String, dynamic>>.from(b["data"] ?? []);
          if (rows.length > limit) rows = rows.take(limit).toList();
          loading = false;
          error = null;
          _currentPage = 1;
          _columnFilters.clear();
        });
      } else {
        setState(() {
          error = b["message"];
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredRows {
    if (_columnFilters.isEmpty) return rows;
    return rows.where((r) {
      for (final f in _columnFilters.entries) {
        final v = (r[f.key]?.toString() ?? "").toLowerCase();
        if (!v.contains(f.value.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  // ✅ Doğru sayı çözümleme
  String normalizeNumber(String raw) {
    raw = raw.trim();
    if (raw.contains(',') && raw.contains('.')) {
      raw = raw.replaceAll('.', '').replaceAll(',', '.'); 
    } else if (raw.contains(',')) {
      raw = raw.replaceAll(',', '.');
    }
    return raw;
  }

  Map<String, dynamic> get totalRow {
    final result = <String, dynamic>{};

    for (var col in visibleColumns) {
      bool isNumeric = true;
      double sum = 0;

      for (var r in filteredRows) {
        final raw = r[col]?.toString();
        if (raw == null) { isNumeric = false; break; }

        final cleaned = normalizeNumber(raw);
        final parsed = double.tryParse(cleaned);
        if (parsed == null) { isNumeric = false; break; }

        sum += parsed;
      }

      result[col] = (isNumeric && filteredRows.isNotEmpty)
          ? sum.toStringAsFixed(2).replaceAll(".", ",")
          : "";
    }

    return result;
  }

  void _showFilterSheet() async {
    final temp = List<String>.from(visibleColumns);

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text("Görünecek Sütunlar",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: columns.map((c) {
                    final visible = temp.contains(c);
                    return CheckboxListTile(
                      title: Text(c),
                      value: visible,
                      onChanged: (v) {
                        setSheet(() {
                          v == true ? temp.add(c) : temp.remove(c);
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              ElevatedButton(
                child: const Text("Uygula"),
                onPressed: () {
                  setState(() => visibleColumns = temp);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  void _askHeaderFilter(String columnName) async {
    final initial = _columnFilters[columnName] ?? "";
    final ctrl = TextEditingController(text: initial);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$columnName - İçeren Filtre"),
        content: TextField(controller: ctrl, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ""), child: const Text("Temizle")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text("Uygula")),
        ],
      ),
    );

    if (result == null) return;
    setState(() {
      result.trim().isEmpty ? _columnFilters.remove(columnName) : _columnFilters[columnName] = result.trim();
      _currentPage = 1;
    });
  }

  void _showValueSelect(String columnName) async {
    final values = filteredRows.map((r) => r[columnName]?.toString() ?? "").toSet().toList()..sort();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$columnName - Değer Seç"),
        content: SizedBox(height: 420, width: double.maxFinite,
          child: ListView.builder(
            itemCount: values.length,
            itemBuilder: (_, i) => ListTile(title: Text(values[i]), onTap: () => Navigator.pop(ctx, values[i])),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ""), child: const Text("Filtreyi Temizle")),
        ],
      ),
    );

    if (result == null) return;
    setState(() {
      result.isEmpty ? _columnFilters.remove(columnName) : _columnFilters[columnName] = result;
      _currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) return Scaffold(appBar: AppBar(title: Text(widget.title)), body: Center(child: Text(error!)));

    final list = filteredRows;
    final totals = totalRow;

    final totalPages = (list.length / _rowsPerPage).ceil().clamp(1, 9999);
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = (_currentPage * _rowsPerPage).clamp(0, list.length);
    final visibleRowsPage = list.sublist(start, end);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.filter_alt), onPressed: _showFilterSheet),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadReport),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: Card(
                elevation: 3,
                child: Scrollbar(
                  controller: _hCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _hCtrl,
                    scrollDirection: Axis.horizontal,
                    child: Scrollbar(
                      controller: _vCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _vCtrl,
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          border: TableBorder.all(color: Colors.black12),
                          headingRowColor: WidgetStateColor.resolveWith((_) => Colors.grey[200]!),
                          columns: visibleColumns.map((c) {
                            return DataColumn(
                              label: GestureDetector(
                                onTap: () => _askHeaderFilter(c),
                                onLongPress: () => _showValueSelect(c),
                                child: Row(
                                  children: [
                                    Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    if (_columnFilters.containsKey(c)) const Icon(Icons.filter_alt, size: 15),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                          rows: [
                            ...visibleRowsPage.map((r) => DataRow(
                                  cells: visibleColumns.map((c) => DataCell(Text(r[c]?.toString() ?? ""))).toList(),
                                )),
                            DataRow(
                              color: WidgetStateProperty.resolveWith((_) => Colors.grey.shade100),
                              cells: visibleColumns.map((c) => DataCell(Text(
                                totals[c]?.toString() ?? "",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ))).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null),
                    Text("Sayfa $_currentPage / $totalPages", style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
