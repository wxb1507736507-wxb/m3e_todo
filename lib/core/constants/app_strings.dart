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
  static const String navCategories = '分类';

  // --- Notes (随笔) -------------------------------------------------------------------

  static const String noteSection = '随笔';
  static const String noteNew = '写随笔';
  static const String noteEdit = '编辑随笔';
  static const String noteBodyHint = '记录点什么：今天发生了什么，想到了什么…';
  static const String noteChangeDate = '改日期';
  static const String noteToday = '今天';
  static const String noteTomorrow = '明天';
  static const String noteEmpty = '写点内容或添加一个附件再保存';
  static const String noteNone = '这一天还没有随笔';
  static const String noteAdd = '写一篇';
  static const String noteDeleted = '已删除这篇随笔';

  /// How many attachments a note carries, when it has any.
  static String noteAttachmentCount(int count) => '$count 个附件';

  // --- Folders (categories) ---------------------------------------------------------

  static const String categoriesEmpty = '还没有分类。点右下角新建一个文件夹，把待办分门别类放进去';
  static const String categoryNew = '新建分类';
  static const String categoryEdit = '编辑分类';
  static const String categoryNameLabel = '分类名称';
  static const String categoryNameHint = '例如：工作、生活、学习';
  static const String categoryNameRequired = '请填写分类名称';
  static const String categoryColorLabel = '标记颜色';
  static const String categoryDeleteHint = '删除分类不会删除里面的待办，它们会回到「未分类」';
  static const String categoryUnfiled = '未分类';
  static const String categoryAll = '全部';
  static const String categoryStripHint = '点分类即可只看这一类，长按可改名';
  static const String categoryEmpty = '这个分类里还没有待办';
  static const String categoryEmptyBody = '换一个分类看看，或者把待办归到这里';
  static const String categorySearchHint = '在这个分类里搜索';
  static const String categoryFolderEmpty = '这个分类里还没有待办';
  static const String categoryPaneTodos = '待办';
  static const String noteFolderEmpty = '这个分类里还没有随笔';
  static const String noteSearchEmpty = '没有找到匹配的随笔';
  static const String categoryPickLabel = '分类';

  static String categoryDeleted(String name) => '已删除分类「$name」';

  // --- Toolbar -------------------------------------------------------------

  static const String searchHint = '搜索待办';
  static const String clearSearch = '清除搜索';
  static const String sortTooltip = '排序方式';
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
  /// The phone's own timetable ends its course editor with 完成 rather than
  /// 保存, and the same word ends the pickers inside it: nothing here is
  /// saved to a server, and 完成 says "I am done with this screen".
  static const String done = '完成';
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
  static const String cropHint = '拖动可重新框选，拖动角点调整大小，双指缩放查看细节';
  static const String cropOutputPrefix = '保留';
  static const String cropFailed = '图片处理失败，请重试';
  static const String cropAspectFree = '自由';
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
  // --- Birthdays, anniversaries and countdowns ---------------------------------------

  static const String specialDaySection = '纪念日';
  static const String calendarPaneTodos = '当天待办';
  static const String specialDayNew = '新增纪念日';
  static const String specialDayEdit = '编辑纪念日';
  static const String specialDayTitleHint = '例如：妈妈生日、结婚纪念日';
  static const String specialDayKindLabel = '类型';
  static const String specialDayBirthday = '生日';
  static const String specialDayAnniversary = '纪念日';
  static const String specialDayCountdown = '倒数日';
  static const String specialDayDateLabel = '日期';
  static const String specialDayTargetLabel = '目标日期';
  static const String specialDayDateHelp = '选择日期';
  static const String specialDayYearlyHint = '每年都会出现在日历上';
  static const String specialDayCountdownHint = '只统计这一次，倒数到目标日期为止';
  static const String specialDayAdd = '添加纪念日';
  static const String specialDayEmpty = '还没有纪念日，点击右下角添加生日、纪念日或倒数日';
  static const String specialDayToday = '就是今天';
  static const String specialDayOverdueMark = '已过';

  /// Days until a recurring date comes round again.
  static String specialDayInDays(int days) => '还有 $days 天';

  /// Days since a one-off countdown's target went by.
  static String specialDayPassedDays(int days) => '已过 $days 天';

  /// "30 岁", for a birthday.
  static String specialDayAge(int years) => '$years 岁';

  /// "第 5 年", for an anniversary.
  static String specialDayYears(int years) => '第 $years 年';

  static String specialDayDeleted(String title) => '已删除「$title」';

  static const String calendarDueLegend = '到期';
  static const String calendarCompletedLegend = '完成';

  // --- Settings -------------------------------------------------------------------

  static const String settingsTooltip = '设置';
  static const String settingsTitle = '设置';
  static const String settingsSectionAppearance = '外观';
  static const String settingsSectionReminders = '到期提醒';
  static const String reminderModeLabel = '默认提醒方式';
  static const String reminderModeRing = '响铃';
  static const String reminderModeSilent = '仅消息';
  static const String reminderFollowApp = '跟随默认';
  static const String reminderLeadLabel = '提醒时间';
  static const String reminderLeadOnDue = '当天';
  static const String reminderLeadOneDay = '提前 1 天';
  static const String reminderLeadThreeDays = '提前 3 天';
  static const String reminderLeadOneWeek = '提前 1 周';
  static const String reminderLeadHint = '提醒时间以到期日为准，提前量按整天计算';

  /// The deadline, shown on a reminder that arrives before it.
  static String reminderDueOn(String date) => '到期日：$date';
  static const String reminderDefaultHint = '这里设置的是默认值，每个待办都可以在编辑页单独选择';

  // --- Per-todo reminder (editor) ---------------------------------------------------

  static const String todoReminderLabel = '提醒方式';
  static const String todoReminderSilentHint = '仅消息：不响铃，只在通知栏提示';
  static const String ringtoneFollowApp = '跟随默认铃声';
  static const String ringtoneDefaultLabel = '默认铃声';
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
  static const String tipReminder = '每个待办可以单独选择响铃还是仅消息，也能各自挑选铃声';
  static const String tipAppBackground = '设置 →「应用背景」可以给整个应用换背景图，图片可裁剪';

  // --- Timetable (课程表) ----------------------------------------------------

  static const String timetableTitle = '课程表';
  static const String timetableOpen = '打开课程表';
  static const String timetableThisWeek = '本周';
  static const String timetablePrevWeek = '上一周';
  static const String timetableNextWeek = '下一周';
  static const String timetableCourseList = '课表列表';
  static const String timetableTermSettings = '学期设置';
  static const String timetableWeekEmpty = '这一周没有课';
  static const String timetableNoCourses = '还没有课程';
  static const String timetableNoCoursesBody = '点「新建课程」，把课表填起来';
  static const String timetableToday = '今天';
  static const String courseWidgetSection = '桌面小组件';
  static const String courseWidgetAdd = '添加到桌面';
  static const String courseWidgetAddHint = '竖向列出今天的课程，点一下打开课程表';
  static const String courseWidgetOnDesktop = '课程表小组件已添加到桌面';
  static const String courseWidgetManualHint =
      '若系统没有弹出确认，请到桌面的「小组件 / 卡片」入口手动添加「课程表小组件」';
  static const String courseWidgetEmpty = '今天没有课';
  static const String courseWidgetStale = '新的一天了，打开应用刷新今天的课';
  static const String courseNew = '新建课程';
  static const String courseEdit = '编辑课程';

  // The three ways into a timetable, named the way the phone's own timetable
  // names them — a user who has used that app should not have to read anything
  // here to know what each one does.
  static const String courseNewSingle = '新建单个课程';
  static const String courseNewSingleHint = '一节一节地加，同一门课可以加多个上课时间';
  static const String courseNewPhoto = '拍照导入课程表';
  static const String courseNewPhotoHint = '选一张课表截图，自动认出课程，确认以后再导入';
  static const String courseNewManual = '手动创建课程表';
  static const String courseNewManualHint = '先填学期信息，再在课表上点格子把课填进去';

  static const String courseNameLabel = '课程名';
  static const String courseNameHint = '例如：高等数学';
  static const String courseNameRequired = '课程名不能为空';
  static const String courseRequired = '必填';
  static const String courseOptional = '非必填';
  static const String courseRoomLabel = '教室';
  static const String courseRoomHint = '例如：教三 201';
  static const String courseNoteLabel = '备注（如老师）';
  static const String courseColorLabel = '课程背景色';
  static const String courseColorNone = '不设颜色，按课程名自动分色';
  static const String courseSlotsLabel = '时段';
  static const String courseSlotWeekday = '星期';
  static const String courseSlotPeriods = '节次';
  static const String courseSlotFromLabel = '从';
  static const String courseSlotToLabel = '到';
  static const String courseAddSlot = '再加一个时间';
  static const String courseRemoveSlot = '删除这个时间';
  static const String courseWeeksLabel = '上课周数';
  static const String courseWeeksAll = '全选';
  static const String courseWeeksOdd = '单周';
  static const String courseWeeksEven = '双周';
  static const String courseWeeksFirstHalf = '前半学期';
  static const String courseWeeksSecondHalf = '后半学期';
  static const String courseWeeksClear = '清空';
  static const String courseWeeksRequired = '至少要选一周';
  static const String courseSlotsRequired = '至少要有一个上课时间';
  static const String courseDeleteTitle = '删除这门课程？';
  static const String courseSaved = '已保存';

  // --- The course's own sheet, which the phone's timetable calls 课程详情 -----

  static const String courseDetailTitle = '课程详情';
  static const String courseDetailClose = '关闭';
  static const String courseDetailRoomPrefix = '教室：';
  static const String courseDetailNotePrefix = '备注（如老师）：';
  static const String courseDetailNoRoom = '教室：未填写';
  static const String courseDetailNoNote = '备注（如老师）：未填写';

  /// The plus that appears on an empty cell, and what tapping it does.
  static const String courseAddHere = '在这格加课';

  /// One weekly meeting of a course, numbered the way the phone numbers them.
  static String courseSlotCount(int index) => '课程时间$index';

  // --- 识图导课 (a timetable read out of a photo) ---------------------------

  static const String courseImportTitle = '拍照导入课程表';
  static const String courseImportIntro =
      '选一张课程表截图或照片。识别在本机完成，图片不会上传；认出课程以后先给你看一遍，确认了才写进课程表。';
  static const String courseImportPick = '选择课表图片';
  static const String courseImportCamera = '拍照';
  static const String courseImportCameraHint = '对着课表照一张，适合贴在墙上的课表';
  static const String courseImportGallery = '从相册选择';
  static const String courseImportGalleryHint = '选一张课表截图或者已经拍好的照片';
  static const String courseImportWorking = '正在识别…';
  static const String courseImportTakeLong = '图片大一点会慢一些，请稍等';
  static const String courseImportEmpty =
      '这张图里没认出课程。换一张更清楚的截图试试：把表头（周一…周日）和课程名都拍进去，别裁掉左边的节次。';
  static const String courseImportFailed = '识别失败';
  static const String courseImportReviewHint = '不想要的可以取消勾选；名字认错了点一下就改。';
  static const String courseImportWeeksHint = '照片看不出单双周，导入的课都按整学期排';
  static const String courseImportRename = '改课程名';
  static String courseImportSkipped(int lines) => '另有 $lines 行文字没落在表格里，已跳过';
  static String courseImportFound(int count) => '认出 $count 门课';
  static String courseImportAction(int count) => '导入 $count 门课';
  static String courseImportDone(int count) => '已导入 $count 门课';
  static String courseImportDoneSome(int count, int alreadyThere) =>
      '已导入 $count 门课，$alreadyThere 门课表里已经有了';
  static const String termNameLabel = '学期名称';
  static const String termNameHint = '例如：大三上';
  static const String termStartLabel = '开学第一周的周一';
  static const String termWeeksLabel = '总周数';
  static const String termPeriodsLabel = '节次时间';
  static const String termPeriodsHint = '点某一节可以改它的上下课时间';
  static const String termWeekendLabel = '周末有课';
  static const String termWeekendHint = '关掉以后课表只显示周一到周五';
  static const String termOtherWeeksLabel = '显示非本周课程';
  static const String termOtherWeeksHint = '打开以后，别的周才上的课也会用浅色画出来';
  static const String timetableBackgroundLabel = '课程表背景';
  static const String timetableBackgroundHint = '给课程表单独换一张背景图；觉得课程名字看不清，就把下面的「遮罩浓度」调高一点，图片会变淡';

  /// A course's own picture, set in the course editor.
  static const String courseBackgroundLabel = '课程背景';
  static const String courseBackgroundHint = '给这门课单独换一张背景图，只有它的方块会变；「遮罩浓度」越高，图片越淡、课程名越清楚';

  /// The home-screen widgets' background, set with the app's own controls.
  static const String widgetBackgroundLabel = '小组件背景';
  static const String widgetBackgroundHint = '桌面上的小组件（打卡、课程）用这张背景图；「遮罩浓度」越高，图片越淡、小组件上的字越清楚';

  /// The timetable's current week, as the header shows it.
  static String timetableWeek(int week) => '第 $week 周';

  /// A course that collides with another, said in the editor.
  static String courseClash(String other, String slot) => '与「$other」在 $slot 冲突';

  static String courseDeleteBody(String name) => '「$name」会从课表里移除，历史不受影响。';

  static String courseDeleted(String name) => '已删除「$name」';

  static String periodCount(int count) =>
      count == 1 ? '第 1 节' : '第 1-$count 节';

  static String periodLabel(int index) => '第 $index 节';

  // --- Habits (打卡) ---------------------------------------------------------

  static const String navHabits = '打卡';
  static const String habitsTitle = '打卡';
  static const String habitNew = '新建打卡';
  static const String habitEdit = '编辑打卡';
  static const String habitEmptyTitle = '还没有打卡项';
  static const String habitEmptyBody = '添加一件想坚持的事，比如吃药、健身、喝水，每天来点一下。';
  static const String habitNameLabel = '名称';
  static const String habitNameHint = '例如：吃药、健身、喝水';
  static const String habitNameRequired = '给打卡项起个名字';
  static const String habitIconLabel = '图标';
  static const String habitDaysLabel = '打卡日期';
  static const String habitDaysHint = '只在选中的日子需要打卡';
  static const String habitDaysRequired = '至少要选一天';
  static const String habitScheduleWeekly = '按星期';
  static const String habitScheduleInterval = '每隔几天';
  static const String habitIntervalLess = '少一天';
  static const String habitIntervalMore = '多一天';
  static const String habitEveryDay = '每天';
  static const String habitWeekdays = '工作日';
  static const String habitWeekends = '周末';
  static const String habitReminderLabel = '提醒';
  static const String habitReminderNone = '不提醒';
  static const String habitReminderPick = '选择提醒时间';
  static const String habitReminderClear = '关闭提醒';
  static const String habitAllowNote = '允许写文字记录';
  static const String habitAllowNoteHint = '打开后打卡时可以顺手写一句；关掉就只是一次点击';
  static const String habitCheckIn = '打卡';
  static const String habitCheckedIn = '已打卡';
  static const String habitUndo = '取消打卡';
  static const String habitCheckInTitle = '今日打卡';
  static const String habitNoteLabel = '写点什么（可不写）';
  static const String habitNoteHint = '今天的感受、次数、身体反应……';
  static const String habitHistory = '打卡记录';
  static const String habitHistoryEmpty = '还没有打卡记录';
  static const String habitToday = '今天要打卡';
  static const String habitTodayNone = '今天不用打卡';
  static const String habitOthers = '其他打卡项';
  static const String habitStreak = '连续';
  static const String habitTotalLabel = '累计';
  static const String habitDelete = '删除打卡项';
  static const String habitDeleteTitle = '删除这个打卡项？';
  static const String habitDeleted = '已删除';
  static const String habitSaved = '已保存';
  static const String habitWidgetSection = '桌面小组件';
  static const String habitWidgetAdd = '添加到桌面';
  static const String habitWidgetAddHint = '每个小组件显示一个打卡项，2×2 大小，点一下就能打卡';
  static const String habitWidgetWhereHint = '在某个打卡项的 ⋮ 菜单里选「添加到桌面」';
  static const String habitWidgetAdded = '小组件已添加到桌面';
  static const String habitWidgetPinRequested = '请在系统弹窗里确认添加';
  static const String habitWidgetManualHint =
      '若系统没有弹出确认，请到桌面的「小组件 / 卡片」入口手动添加「打卡小组件」';
  static const String habitWidgetUnsupported = '当前设备不支持桌面小组件';
  static const String habitWidgetOnDesktop = '已添加到桌面';
  static const String habitWidgetAddMore = '再加一个';
  static const String habitWidgetTileTodo = '今天还没打卡';
  static const String habitWidgetTileDone = '已完成';
  static const String habitWidgetTileOff = '今天不用打卡';
  static const String habitWidgetTileMissing = '这个打卡项已删除';
  static const String habitWidgetTileUnconfigured = '还没选择打卡项，长按小组件重新选择';
  static const String habitWidgetStale = '新的一天了，打开应用刷新';
  static const String habitWidgetConfigTitle = '选择要显示的打卡项';
  static const String habitWidgetConfigEmpty = '还没有打卡项，先到应用里添加一个';
  static const String habitReminderBody = '今天还没打卡';
  static const String habitNotificationAction = '打卡';
  static const String habitNotificationPermissionHint =
      '没有通知权限，打卡提醒无法显示。已为你打开通知设置，请打开「允许通知」';
  static const String habitExactAlarmHint =
      '未授权「闹钟和提醒」，提醒可能延迟约 1 小时。已为你打开系统设置，请允许精确闹钟';
  static const String habitOpenSettings = '打开权限设置';
  static const String habitWidgetEmptyTitle = '今天没有要打卡的项目';
  static const String habitWidgetEmptyBody = '在应用里添加打卡项';

  /// The widget's own counter line: `2/3 已完成`.
  static String habitWidgetCount(int done, int total) =>
      '$done/$total $habitWidgetCountSuffix';

  /// The words after the numbers in that line.
  ///
  /// Sent to the widget as well, because the widget recounts by itself when a
  /// row is tapped with the app closed — and a header still reading "0/3"
  /// underneath a ticked row is exactly the kind of small lie a summary must
  /// never tell.
  static const String habitWidgetCountSuffix = '已完成';

  /// The widget's overflow line when more habits are due than it can show.
  static String habitWidgetMore(int count) => '还有 $count 项';

  static String habitReminderStreakBody(int days) => '今天还没打卡，已连续 $days 天';

  static String habitStreakDays(int days) => '连续 $days 天';

  static String habitEveryNDays(int days) => '每隔 $days 天';

  static String habitIntervalHint(int days) =>
      '从创建那天算起，每 $days 天需要打卡一次';

  static String habitTotalTimes(int times) => '累计 $times 次';

  static String habitDeleteBody(String name) => '「$name」和它的全部打卡记录都会被删除，无法恢复。';

  static String habitCheckedInToast(String name) => '「$name」打卡成功';

  static String habitUndoneToast(String name) => '已取消「$name」今天的打卡';

  static String habitDaysSummary(String days) => '打卡日期：$days';
}
