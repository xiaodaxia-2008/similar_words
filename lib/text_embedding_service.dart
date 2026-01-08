import 'dart:io';
import 'dart:math';
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

class TextEmbeddingService {
  late SentencePieceTokenizer _tokenizer;
  late OrtSession _session;
  bool _isInitialized = false;

  void Function(String msg)? _log;

  final Map<String, List<double>> _cache = {};

  final Dio _dio = Dio();

  late String _modelPath;
  late String _tokenizerPath;

  void setLogHandler(void Function(String msg) log) {
    _log = log;
  }

  void log(String msg) {
    if (_log != null) {
      _log!(msg);
    } else {
      print(msg);
    }
  }

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    log('Initializing TextEmbeddingService...');

    String appDocDir;
    if (Platform.isWindows && !kIsWeb) {
      appDocDir = ".";
    } else {
      appDocDir = (await getApplicationDocumentsDirectory()).path;
    }
    _modelPath = '$appDocDir/models/model_int8.onnx';
    _tokenizerPath = '$appDocDir/models/tokenizer.model';

    log("downloadModel");
    await downloadModel();
    log("finish downloadModel");

    _tokenizer = SentencePieceTokenizer.fromModelFileSync(
      _tokenizerPath,
      config: SentencePieceConfig.gemma,
    );
    final ort = OnnxRuntime();
    _session = await ort.createSession(_modelPath);

    _isInitialized = true;
    log('TextEmbeddingService initialized.');
  }

  Future<int> mostSimilarIndex(String query, List<String> categories) async {
    await init();
    double maxSimilarity = -1.0;
    int maxIndex = -1;

    final queryEmbedding = await getEmbedding(query);
    final categoryEmbeddings = categories.map((category) async {
      final embedding = await getEmbedding(category, storeCache: true);
      return embedding;
    }).toList();

    for (int i = 0; i < categories.length; i++) {
      final similarity = cosineSimilarity(
        queryEmbedding,
        await categoryEmbeddings[i],
      );
      if (similarity > maxSimilarity) {
        maxSimilarity = similarity;
        maxIndex = i;
      }
    }
    return maxIndex;
  }

  Future<void> downloadModel() async {
    final modelFile = File(_modelPath);
    final tokenizerFile = File(_tokenizerPath);
    if (modelFile.existsSync() && tokenizerFile.existsSync()) {
      print('Model and tokenizer files already exist.');
      return;
    }

    final hostUrlEn = 'https://huggingface.co';
    final hostUrlZn = 'https://hf-mirror.com';
    for (var hostUrl in [hostUrlZn, hostUrlEn]) {
      try {
        log('Try downloading model from $hostUrl');
        if (!modelFile.existsSync()) {
          log("从 $hostUrl 下载模型...");
          final url =
              '$hostUrl/LeePark/gemma-embedding-300M-onnx-int8/resolve/main/model_int8.onnx';
          log('Downloading model from $url to $_modelPath');
          await _dio.download(
            url,
            _modelPath,
            onReceiveProgress: (received, total) {
              if (total != -1) {
                log(
                  'Model download progress: ${(received / total * 100).toStringAsFixed(0)}%',
                );
              }
            },
          );
          log('Model downloaded to $_modelPath');
        }

        if (!tokenizerFile.existsSync()) {
          final url =
              '$hostUrl/LeePark/gemma-embedding-300M-onnx-int8/resolve/main/tokenizer.model';
          log('Downloading tokenizer from $url to $_tokenizerPath');
          await _dio.download(
            url,
            _tokenizerPath,
            onReceiveProgress: (received, total) {
              if (total != -1) {
                log(
                  'Tokenizer download progress: ${(received / total * 100).toStringAsFixed(0)}%',
                );
              }
            },
          );
          log('Tokenizer downloaded to $_tokenizerPath');
        }
        break;
      } catch (e) {
        log('Error downloading model from $hostUrl: $e');
      }
    }
  }

  Future<List<double>> getEmbedding(
    String sentence, {
    bool storeCache = false,
  }) async {
    if (!_isInitialized) {
      throw StateError('Service not initialized. Call init() first.');
    }

    if (_cache.containsKey(sentence)) {
      return _cache[sentence]!;
    }

    final encoding = _tokenizer.encode(sentence);

    final inputIds = Int64List.fromList(encoding.ids);
    final attentionMask = Int64List.fromList(encoding.attentionMask);
    final shape = [1, encoding.ids.length];

    final inputs = {
      'input_ids': await OrtValue.fromList(inputIds, shape),
      'attention_mask': await OrtValue.fromList(attentionMask, shape),
    };

    List<double> meanPooledEmbedding = [];
    Map<String, OrtValue> outputs = {};

    try {
      outputs = await _session.run(inputs);
      final lastHiddenState = await outputs['last_hidden_state']!.asList();
      final embedding = lastHiddenState
          .map<List<Float32List>>((e) => (e as List).cast<Float32List>())
          .toList();

      final embeddingShape = [
        embedding.length,
        embedding.isNotEmpty ? embedding[0].length : 0,
        embedding.isNotEmpty && embedding[0].isNotEmpty
            ? embedding[0][0].length
            : 0,
      ];
      final hiddenSize = embeddingShape[2];

      final summed = List<double>.filled(hiddenSize, 0.0);
      int tokenCount = 0;

      for (int i = 0; i < embedding[0].length; i++) {
        if (attentionMask[i] == 1) {
          tokenCount++;
          for (int j = 0; j < hiddenSize; j++) {
            summed[j] += embedding[0][i][j];
          }
        }
      }

      if (tokenCount > 0) {
        meanPooledEmbedding = summed.map((e) => e / tokenCount).toList();
      }
    } finally {
      for (var v in inputs.values) {
        v.dispose();
      }
      for (var v in outputs.values) {
        v.dispose();
      }
    }

    if (storeCache) {
      _cache[sentence] = meanPooledEmbedding;
    }
    return meanPooledEmbedding;
  }

  static double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) {
      throw ArgumentError('Vectors must have the same length');
    }

    double dotProduct = 0.0;
    double mag1 = 0.0;
    double mag2 = 0.0;

    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      mag1 += v1[i] * v1[i];
      mag2 += v2[i] * v2[i];
    }

    mag1 = sqrt(mag1);
    mag2 = sqrt(mag2);

    if (mag1 == 0 || mag2 == 0) {
      return 0.0;
    } else {
      return dotProduct / (mag1 * mag2);
    }
  }

  Future<void> release() async {
    if (!_isInitialized) {
      return;
    }
    print('Releasing TextEmbeddingService resources...');
    await _session.close();
    _isInitialized = false;
  }
}
