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
  static const String sortManual = '手动排序';
  static const String sortCreatedNewest = '最近创建';
  static const String sortDueSoonest = '最快到期';
  static const String sortPriorityFirst = '优先级优先';

  // --- Summary -------------------------------------------------------------

  static String activeCount(int count) => '$count 项进行中';
  static String progressValue(int done, int total) => '$done / $total';

  // --- Due dates -----------------------------------------------------------

  static const String dueOverdue = '已逾期';
  static const String dueToday = '今天到期';
  static const String dueTomorrow = '明天到期';

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

  // --- Subtasks --------------------------------------------------------------

  static const String subtasksLabel = '子备忘录';
  static const String addSubtask = '添加子选项';
  static const String subtaskHint = '输入子选项';
  static const String subtaskEmptyHint = '还没有子选项，点右上角 + 添加';
  static const String removeSubtask = '移除子选项';
  static String subtaskProgress(int done, int total) => '$done/$total';

  // --- Attachments -------------------------------------------------------------

  static const String attachmentsLabel = '附件';
  static const String attachImage = '图片';
  static const String attachVideo = '视频';
  static const String attachDocument = '文档';
  static const String attachVoice = '语音';
  static const String attachmentUnsupported =
      '此平台暂不支持添加附件';
  static const String attachmentOpenFailed = '无法打开此附件';
  static const String voiceRecording = '正在录音…';
  static const String voiceRecordStart = '开始录音';
  static const String voiceRecordStop = '完成';
  static const String voiceRecordCancel = '取消';
  static const String voiceRecordFailed = '录音失败，请检查麦克风权限';

  // --- Appearance --------------------------------------------------------------

  static const String accentColorLabel = '色块颜色';
  static const String accentColorNone = '跟随主题';
  static const String textColorLabel = '字体颜色';
  static const String textColorAuto = '自动';
  static const String colorCustom = '自定义';
  static const String colorPick = '取色';
  static const String colorCommon = '常用颜色';
  static const String colorSoft = '浅色';
  static const String colorContrastWarning = '与色块颜色太接近，文字可能看不清';
  static const String backgroundImageLabel = '背景图片';
  static const String pickBackgroundImage = '选择图片';
  static const String clearBackgroundImage = '移除背景图';
  static const String cropBackgroundImage = '裁剪';

  // --- Colour picker ---------------------------------------------------------------

  static const String colorPickerTitle = '调色板';
  static const String colorHue = '色相';
  static const String colorSaturation = '饱和度';
  static const String colorBrightness = '明度';
  static const String colorHexLabel = '十六进制颜色值';
  static const String colorHexInvalid = '不是有效的颜色值';

  // --- Colour extraction --------------------------------------------------------------

  static const String colorExtractTitle = '从图片取色';
  static const String colorExtractHint = '点按图片取色；双指缩放可以更精确地对准';
  static const String colorExtractFailed = '无法读取这张图片';

  // --- Cropper -------------------------------------------------------------------

  static const String cropTitle = '裁剪图片';
  static const String cropApply = '完成';
  static const String cropHint = '双指缩放、拖动调整范围，框内即为保留部分';
  static const String cropFailed = '图片处理失败，请重试';
  static const String cropAspectOriginal = '原图';
  static const String cropAspectScreen = '屏幕';
  static const String cropAspectSquare = '1:1';
  static const String cropAspectStandard = '4:3';
  static const String cropAspectWide = '16:9';
  static const String cropAspectPortrait = '9:16';

  // --- App background ---------------------------------------------------------------

  static const String settingsSectionBackground = '应用背景';
  static const String appBackgroundNone = '未设置背景图，应用使用主题底色';
  static const String appBackgroundPick = '选择背景图';
  static const String appBackgroundChange = '更换';
  static const String appBackgroundRemove = '移除';
  static const String backgroundDimLabel = '遮罩浓度';
  static String backgroundDimValue(int percent) => '$percent%';

  // --- Calendar -----------------------------------------------------------------

  static const String navCalendar = '日历';
  static const String calendarTitle = '日历回顾';
  static const String calendarSearchHint = '搜索历史待办';
  static const String calendarToday = '今天';
  static const String calendarPreviousMonth = '上个月';
  static const String calendarNextMonth = '下个月';
  static const String calendarJumpToDate = '跳转到指定日期';
  static const String calendarNoTodos = '这一天没有待办记录';
  static String calendarMonthLabel(int year, int month) => '$year年$month月';
  static const String calendarDueLegend = '到期';
  static const String calendarCompletedLegend = '完成';

  // --- Settings -------------------------------------------------------------------

  static const String settingsTooltip = '设置';
  static const String settingsTitle = '设置';
  static const String settingsSectionAppearance = '外观';
  static const String settingsSectionReminders = '到期提醒';
  static const String reminderModeLabel = '提醒方式';
  static const String reminderModeRing = '响铃';
  static const String reminderModeSilent = '仅消息';
  static const String ringtoneLabel = '铃声';
  static const String ringtoneSystem = '跟随系统';
  static const String ringtoneCustom = '自定义铃声';
  static const String ringtonePick = '选择铃声';
  static const String ringtonePreview = '试听';
  static const String notificationPermissionNeeded =
      '尚未授予通知权限，点击此处授权';
  static const String exactAlarmNeeded = '精确提醒未获授权，提醒可能延迟约 1 小时，点击此处设置';
  static const String notificationTest = '发送测试通知';
  static const String reminderTimeHint = '提醒在到期日上午 9:00 发送';
  static const String settingsSectionTips = '使用说明';
  static const String tipReorder = '在列表中长按待办即可拖动排序';
  static const String tipSubtask = '编辑待办时可以添加子选项，把一件事拆成可勾选的步骤';
  static const String tipCalendar = '在「日历」页回顾历史待办，支持按日期跳转和搜索';
  static const String tipAttachment = '待办可以附加图片、视频、文档或语音备忘';
  static const String tipAppearance = '在编辑待办时可以自定义色块颜色与背景图片';
  static const String tipAppBackground = '设置 →「应用背景」可以给整个应用换背景图，图片可裁剪';
}
