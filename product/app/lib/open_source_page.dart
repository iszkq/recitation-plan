import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';

import 'design.dart';

class OpenSourcePage extends StatefulWidget {
  const OpenSourcePage({super.key});
  @override
  State<OpenSourcePage> createState() => _OpenSourcePageState();
}

class _OpenSourcePageState extends State<OpenSourcePage> {
  late final Future<String> license = rootBundle.loadString(
    'assets/licenses/lpinyin.txt',
  );
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('开源许可')),
    child: SafeArea(
      child: FutureBuilder<String>(
        future: license,
        builder: (context, state) => ListView(
          padding: const EdgeInsets.all(Design.inset),
          children: [
            const Text('拼音读音数据', style: Design.heading),
            const Text('lpinyin 2.0.3 · BSD-2-Clause', style: Design.caption),
            const SizedBox(height: Design.gap),
            if (state.hasError) const Text('许可暂时无法读取，请重新打开。'),
            if (state.connectionState != ConnectionState.done)
              const CupertinoActivityIndicator(),
            if (state.hasData)
              SelectableText(state.data!, style: Design.caption),
          ],
        ),
      ),
    ),
  );
}
