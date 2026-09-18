// Official packages
import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';
// KeyDownEvent / LogicalKeyboardKey 在 services 里，cupertino 不会顺带导出。
import 'package:flutter/services.dart';
import 'package:pcelechron/page/scholar/course_list/course_brief_card.dart';
import 'package:pcelechron/utils/platform_features.dart';
import 'package:get/get.dart';

import 'search_controller.dart';

class SearchPage extends StatelessWidget {
  SearchPage({super.key});

  final _searchController = Get.put(SearchPageController());

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        // 桌面端再补一条 Esc 返回：键盘比点按钮顺手，也符合桌面端的习惯。
        // 焦点在搜索框上时，按键事件会沿 focus 链冒泡到这里的 Focus，
        // 所以不需要抢搜索框的 autofocus。移动端不挂这个回调。
        child: Focus(
            onKeyEvent: PlatformFeatures.isDesktop
                ? (FocusNode node, KeyEvent event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(context).pop();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  }
                : null,
            child: SafeArea(
                child: CustomScrollView(slivers: [
              SliverPinnedToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(children: [
                        Row(
                          children: [
                            // 移动端靠 CupertinoPageRoute 的侧滑返回手势就能回去；
                            // 桌面端没有这个手势，进到搜索页就出不来了，所以补一个返回按钮。
                            if (PlatformFeatures.isDesktop) ...[
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  onPressed: () => Navigator.of(context).pop(),
                                  child:
                                      const Icon(CupertinoIcons.back, size: 22),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: CupertinoSearchTextField(
                                placeholder: '搜索课程、事项...',
                                placeholderStyle: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .copyWith(
                                        color: CupertinoColors.systemGrey,
                                        height: 1.25,
                                        fontSize: 18),
                                style: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .copyWith(height: 1.25, fontSize: 18),
                                borderRadius: BorderRadius.circular(12),
                                itemColor: CupertinoColors.systemGrey,
                                itemSize: 20,
                                suffixInsets:
                                    const EdgeInsetsDirectional.fromSTEB(
                                        0, 0, 5, 0),
                                prefixInsets:
                                    const EdgeInsetsDirectional.fromSTEB(
                                        10, 0, 0, 0),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 8),
                                onChanged: (String value) {
                                  _searchController.searchWord.value = value;
                                },
                                autofocus: true,
                              ),
                            ),
                          ],
                        )
                      ]))),
              Obx(() => SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Container(
                        padding: index == 0
                            ? const EdgeInsets.only(
                                top: 0, bottom: 5, left: 16, right: 16)
                            : const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 5),
                        child: CourseBriefCard(
                          course: _searchController.courseResult[index],
                          allowDirect: true,
                        ),
                      ),
                      childCount: _searchController.courseResult.length,
                    ),
                  )),
            ]))));
  }
}
