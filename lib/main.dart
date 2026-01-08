import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _similarCategory = "健身";

  final List<String> _categories = [
    "餐饮",
    "酒水",
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
    "旅行",
  ];

  late final TextEditingController _textController;
  late final TextEditingController _newCategoryTextController;
  late final TextEmbeddingService _service;

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
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text("所有分类：${_categories.join(",")}"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: showNewCategorySheet,
              child: const Text("添加分类"),
            ),
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
    _textController.text = "跑步";
    _newCategoryTextController = TextEditingController();
    _service = TextEmbeddingService();
    init();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final categories = prefs.getStringList("categories");
    if (categories != null) {
      setState(() {
        _categories.clear();
        _categories.addAll(categories);
      });
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
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
    await Future.delayed(Duration(milliseconds: 50));
    final word = _textController.text;
    final index = await _service.mostSimilarIndex(word, _categories);
    setState(() {
      _similarCategory = _categories[index];
    });
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
