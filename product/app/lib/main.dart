import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:recitation_core/recitation_core.dart';

import 'app.dart';
import 'app_model.dart';
import 'design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final root = await getApplicationDocumentsDirectory();
    final store = await HiveRecitationStore.open('${root.path}/recitation');
    final model = AppModel(store);
    await model.reload();
    runApp(RecitationApp(model: model));
  } catch (error) {
    runApp(
      CupertinoApp(
        theme: Design.theme,
        home: CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(middle: Text('背诵计划')),
          child: SafeArea(
            child: EmptyContent(
              '无法打开本机档案',
              '请重启应用后再试。原有数据未清除。\n${error is FileSystemException ? '存储空间或文件访问不可用。' : error}',
            ),
          ),
        ),
      ),
    );
  }
}
