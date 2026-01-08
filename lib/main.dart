import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';

import './text_embedding_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '相似分类',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: '相似分类'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _similarCategory = "";

  RxString _logMsg = "".obs;
  RxMap<String, double> _similarities = <String, double>{}.obs;

  final List<String> _categories = [
    "餐饮",
    "酒水",
    "水果",
    "蔬菜",
    "交通",
    "服饰",
    "购物",
    "健身",
    "娱乐",
    "数码",
    "教育",
    "美容",
    "居家",
    "健康",
    "孩子",
    "长辈",
    "社交",
    "旅行",
    "宠物",
    "礼物",
    "办公",
  ];

  late final TextEditingController _textController;
  late final TextEditingController _newCategoryTextController;
  late final TextEmbeddingService _service;
  late final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: "请输入词语",
                  labelText: "词语",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onSubmitted: (value) => _compute(),
              ),
            ),
            Text(
              "最接近的分类：$_similarCategory",
              style: TextStyle(fontSize: 20, color: Colors.green),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Obx(() {
                if (_similarities.isNotEmpty) {
                  final sortedEntries = _similarities.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
                  return ListView.builder(
                    itemCount: sortedEntries.length,
                    itemBuilder: (context, index) {
                      final entry = sortedEntries[index];
                      return ListTile(
                        title: Text(entry.key),
                        dense: true,
                        trailing: Text(
                          "${(entry.value * 100.0).toStringAsFixed(2)}%",
                        ),
                      );
                    },
                  );
                } else {
                  return ListView.builder(
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_categories[index]),
                        dense: true,
                      );
                    },
                  );
                }
              }),
            ),
            ElevatedButton(
              onPressed: showNewCategorySheet,
              child: const Text("添加分类"),
            ),
            Obx(() => Text(_logMsg.value)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _compute,
        tooltip: 'Compute',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _newCategoryTextController.dispose();
    _service.release();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _newCategoryTextController = TextEditingController();
    _service = TextEmbeddingService();
    _service.setLogHandler((String msg) {
      _logMsg.value = msg;
    });
    init();
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    final categories = prefs.getStringList("categories");
    if (categories != null) {
      setState(() {
        _categories.clear();
        _categories.addAll(categories);
      });
    }
    final query = prefs.getString("lastQuery");
    if (query != null) {
      _textController.text = query;
      await _compute();
    }
  }

  Future<void> save() async {
    print("save categories: $_categories");
    await prefs.setStringList("categories", _categories);
  }

  Future<void> _addCategory(String category) async {
    setState(() {
      _categories.add(category);
    });
    await save();
  }

  Future<void> _compute() async {
    setState(() {
      _similarCategory = "计算中···";
    });
    _similarities.clear();
    await Future.delayed(const Duration(milliseconds: 50));
    final word = _textController.text;
    final similarities = await _service.getSimilarities(word, _categories);
    _similarities.addAll(similarities);

    if (similarities.isNotEmpty) {
      final maxEntry = similarities.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      setState(() {
        _similarCategory = maxEntry.key;
      });
    } else {
      setState(() {
        _similarCategory = "无";
      });
    }

    await prefs.setString("lastQuery", word);
    _logMsg.value = "";
  }

  Future<void> showNewCategorySheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsetsGeometry.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: .spaceAround,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: const Text("添加分类"),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _newCategoryTextController,
                  decoration: InputDecoration(
                    hintText: "请输入分类",
                    labelText: "分类",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: .spaceAround,
                children: [
                  IconButton(
                    onPressed: () {
                      _addCategory(_newCategoryTextController.text);
                      Navigator.of(context).pop();
                    },
                    icon: Icon(Icons.check_circle_outline),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: Icon(Icons.cancel_outlined),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
