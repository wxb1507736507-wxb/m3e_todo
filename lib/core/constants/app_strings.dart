/// Every user-facing string in the app.
///
/// Concentrating them here means the UI can be localised later by swapping this
/// class for generated `AppLocalizations` lookups without hunting for string
/// literals across dozens of widgets. Parameterised strings are methods rather
/// than constants so the placeholders stay visible at the call site.
abstract final class AppStrings {
  // --- Shell ---------------------------------------------------------------

  static const String appTitle = 'M3E 待办';
  static const String navAll = '全部';
  static const String navActive = '进行中';
  static const String navCompleted = '已完成';

  // --- Toolbar -------------------------------------------------------------

  static const String searchHint = '搜索待办';
  static const String clearSearch = '清除搜索';
  static const String sortTooltip = '排序方式';
  static const String sortManual = '手动排序';
  static const String sortCreatedNewest = '最近创建';
  static const String sortDueSoonest = '最快到期';
  static const String sortPriorityFirst = '优先级优先';
  static const String appearanceTooltip = '外观设置';

  // --- Summary -------------------------------------------------------------

  static String activeCount(int count) => '$count 项进行中';
  static const String progressLabel = '完成进度';
  static String progressValue(int done, int total) => '$done / $total';

  // --- Due dates -----------------------------------------------------------

  static const String dueOverdue = '已逾期';
  static const String dueToday = '今天到期';
  static const String dueTomorrow = '明天到期';
  static String dueInDays(int days) => '$days 天后到期';

  // --- Empty states --------------------------------------------------------

  static const String emptyAllTitle = '还没有待办';
  static const String emptyAllBody = '添加第一件事，开始规划今天。';
  static const String emptyActiveTitle = '全部完成了';
  static const String emptyActiveBody = '当前没有进行中的待办。';
  static const String emptyCompletedTitle = '还没有已完成的事项';
  static const String emptyCompletedBody = '完成待办后，它们会归档到这里。';
  static const String emptySearchTitle = '没有找到匹配的待办';
  static const String emptySearchBody = '试试其他关键词。';

  // --- Editor --------------------------------------------------------------

  static const String newTodo = '新建待办';
  static const String editTodo = '编辑待办';
  static const String titleLabel = '标题';
  static const String titleHint = '例如：整理设计评审纪要';
  static const String titleRequired = '请输入待办标题';
  static const String notesLabel = '备注';
  static const String notesHint = '补充说明（可选）';
  static const String priorityLabel = '优先级';
  static const String priorityLow = '低';
  static const String priorityNormal = '中';
  static const String priorityHigh = '高';
  static const String dueDateLabel = '截止日期';
  static const String dueDateUnset = '未设置';
  static const String pickDueDate = '选择日期';
  static const String clearDueDate = '清除日期';
  static const String save = '保存';
  static const String create = '创建';
  static const String cancel = '取消';

  // --- Item actions --------------------------------------------------------

  static const String moreActions = '更多操作';
  static const String actionEdit = '编辑';
  static const String actionDelete = '删除';
  static const String actionMarkComplete = '标记为已完成';
  static const String actionMarkIncomplete = '标记为未完成';
  static const String actionMoveUp = '上移';
  static const String actionMoveDown = '下移';
  static const String undo = '撤销';
  static String deletedTodo(String title) => '已删除「$title」';

  // --- Bulk actions --------------------------------------------------------

  static const String clearCompleted = '清除已完成';
  static const String clearCompletedTitle = '清除已完成待办？';
  static String clearCompletedBody(int count) =>
      '将永久删除 $count 项已完成的待办，此操作无法撤销。';
  static const String confirm = '确定';
  static String clearedCompleted(int count) => '已清除 $count 项待办';

  // --- Appearance ----------------------------------------------------------

  static const String appearanceTitle = '外观设置';
  static const String themeModeLabel = '主题模式';
  static const String themeSystem = '跟随系统';
  static const String themeLight = '浅色';
  static const String themeDark = '深色';
  static const String colorSeedLabel = '主题色';
  static const String colorSeedViolet = '紫罗兰';
  static const String colorSeedOcean = '海洋蓝';
  static const String colorSeedTeal = '青绿';
  static const String colorSeedForest = '森林绿';
  static const String colorSeedAmber = '琥珀';
  static const String colorSeedRose = '玫红';

  // --- Failures ------------------------------------------------------------

  static const String loadFailedTitle = '无法加载待办';
  static const String loadFailedBody = '本地数据文件可能已被占用或损坏。';
  static const String retry = '重试';
  static const String saveFailed = '保存失败，请重试';

  // --- Shortcut hints ------------------------------------------------------

  static const String shortcutModifier = 'Ctrl';
}
