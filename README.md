# FundLink | 一基暴富 📈

这是一款基金持仓管理与分析工具，支持多平台部署（iOS/Android/Windows/macOS）。

---

## 📋 目录

- [✨ 核心特性](#-核心特性)
- [🚀 快速开始](#-快速开始)
- [📁 项目结构](#-项目结构)
- [⚖️ 开源协议](#️-开源协议)

---

## ✨ 核心特性

### 📊 资产管理
- **多维度收益计算**：支持绝对与年化收益率计算
- **穿透式持仓分析**：展示基金"十大重仓股"及占比
- **业绩曲线可视化**：基金净值走势对比（同类平均/沪深300/中证500等）
- **交易流水管理**：支持同一客户对同一基金的多次买入/卖出，自动计算加权平均成本
- **待确认交易管理**：识别闭市前后交易，标记待确认后T+1/T+2确认

### 📥 数据导入导出
- **模糊智能导入**：支持 CSV/Excel 批量导入，具备日期与格式模糊匹配能力
- **自定义导出**：可根据需求组合字段（客户号、备注、净值等）导出汇总数据

### 🔒 信息安全
- **隐私模式**：脱敏展示基金信息，方便截屏或转发
- **本地化存储**：数据存储于本地 SQLite 数据库，不经过第三方服务器
- **安全加固**：文件大小限制、字段长度限制、错误消息脱敏

### 🎨 用户体验
- **跨平台支持**：iOS / Android / Windows / macOS
- **深色模式**：支持浅色/深色/跟随系统 三种主题
- **响应式设计**：适配手机、平板、桌面端不同屏幕尺寸
- **磨玻璃效果**：现代化的 UI 设计风格

------

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 2.17.0
- 支持的平台：iOS / Android / Windows / macOS / Linux

### 安装与运行

```bash
# 1. 克隆仓库
git clone https://github.com/rizona27/fundlink.git
cd fundlink

# 2. 安装依赖
flutter pub get

# 3. 生成代码（如果使用了 build_runner）
flutter pub run build_runner build

# 4. 启动项目
flutter run

# 5. 指定平台运行
flutter run -d windows    # Windows
flutter run -d chrome     # Web
flutter run -d <device>   # 其他设备
```

### 构建发布版本

```bash
# Android APK (arm64)
flutter build apk --release --split-per-abi --target-platform android-arm64

# Windows 应用
flutter build windows --release

# iOS 应用
flutter build ios --release
```

------

## 📝 项目结构

```
lib/
├── main.dart                              # 应用入口，初始化 DataManager，配置主题模式（浅色/深色/跟随系统）
│
├── constants/
│   └── app_constants.dart                 # 全局常量管理，统一管理 API 地址、缓存键名、业务常量、User-Agent 等
│
├── utils/
│   ├── animation_config.dart              # 动画配置工具类，统一定义动画时长、曲线等参数
│   ├── input_formatters.dart              # 输入格式化工具类，提供金额、整数、客户姓名、客户号等格式化器
│   ├── memory_info_native.dart            # 原生平台内存信息实现（iOS/Android/macOS），使用 flutter_memory_info
│   ├── memory_info_web.dart               # Web平台内存信息实现，使用 Performance API 或估算值
│   ├── memory_monitor.dart                # 内存监控工具类，跨平台兼容，监控应用内存使用情况，防止内存泄漏
│   ├── security_utils.dart                # 安全工具类，错误消息脱敏、敏感数据掩码、输入清理
│   └── smart_cache.dart                   # 智能 LRU 缓存工具类，支持 TTL 过期和容量限制，用于 API 数据缓存
│
├── services/
│   ├── china_trading_day_service.dart     # 中国交易日判断服务，智能识别法定节假日和调休补班，采用三层降级策略
│   ├── client_mapping_service.dart        # 客户映射词典服务，管理客户号与客户名的映射关系，支持增删改查和双向查询
│   ├── data_manager.dart                  # 数据管理核心，持仓增删改查、交易记录管理、日志记录、隐私模式、收益计算
│   ├── database_helper.dart               # SQLite 数据库帮助类，跨平台数据库支持，提供 CRUD 操作和 Schema 管理
│   ├── database_repository.dart           # 数据访问层封装，统一管理所有数据库操作，支持批量插入和高级查询
│   ├── file_export_service.dart           # 文件导出服务，支持 CSV/Excel 格式
│   ├── file_import_service.dart           # 文件导入服务，支持 CSV/Excel 格式，具备模糊匹配能力
│   ├── fund_service.dart                  # 基金 API 服务，调用接口获取数据，含多源冗余、缓存和重试机制
│   ├── ui_state_service.dart              # UI 状态管理服务，使用 SQLite 存储 UI 状态（如展开/折叠状态）
│   └── version_check_service.dart         # 版本检查服务，优先从后端检查，失败时回退到 GitHub Release API
│
├── models/
│   ├── client_mapping.dart                  # 客户映射模型，存储客户号与客户名的映射关系（ID、客户号、客户名、创建/更新时间）
│   ├── fund_holding.dart                  # 持仓数据模型，客户信息、基金代码/名称、累计投入、持有份额、平均成本、净值、收益
│   ├── fund_info_cache.dart               # 基金信息缓存模型，存储基金代码、名称、当前净值等数据的本地缓存
│   ├── log_entry.dart                     # 日志条目模型，消息内容、日志类型、时间戳
│   ├── net_worth_point.dart               # 净值及趋势数据点
│   ├── profit_result.dart                 # 收益结果模型，绝对收益、年化收益率
│   ├── top_holding.dart                   # 十大重仓股数据
│   └── transaction_record.dart            # 交易记录模型，单笔买入/卖出交易的详细信息
│
├── views/
│   ├── add_holding_view.dart              # 新增持仓页，表单输入客户信息、基金代码、交易金额/份额/日期
│   ├── client_view.dart                   # 客户视图页，分组展示持仓
│   ├── config_view.dart                   # 程序设置页面，隐私/主题切换/日志查询/持仓管理等
│   ├── edit_holding_view.dart             # 编辑持仓页，显示持仓详情，支持加仓/减仓操作，查看交易历史，编辑基金备注
│   ├── export_holding_view.dart           # 导出数据页面，支持 CSV/Excel 格式
│   ├── fund_detail_view.dart              # 基金详情页，包含估值/净值趋势/十大重仓
│   ├── history_view.dart                  # 历史净值弹窗页
│   ├── import_holding_view.dart           # 导入数据页面，支持 CSV/Excel 格式
│   ├── license_view.dart                  # 开源协议页面（AGPL v3）
│   ├── log_view.dart                      # 日志页面，以功能性分类展示日志
│   ├── manage_holdings_view.dart          # 管理持仓页，编辑/删除/客户与基金持仓信息，支持批量编辑客户信息（姓名+客户号）
│   ├── mapping_dictionary_view.dart       # 映射词典页，管理客户号与客户名的映射关系
│   ├── pending_transactions_view.dart     # 待确认交易管理页，展示 T+1/T+2 待确认的交易列表
│   ├── splash_view.dart                   # 开场动画页
│   ├── summary_view.dart                  # 基金汇总页，按基金代码分组，显示基金详情及收益
│   ├── top_performers_view.dart           # 收益排行页，按金额/收益/收益率/持有天数排序
│   └── version_view.dart                  # 版本信息页，显示应用版本和功能说明，始终显示 Update 按钮
│
└── widgets/
    ├── adaptive_top_bar.dart              # 顶部工具栏组件，包含刷新、搜索、筛选等功能
    ├── add_transaction_dialog.dart        # 加仓/减仓对话框，支持交易金额/份额/净值/费率输入
    ├── batch_rename_dialog.dart           # 批量编辑客户信息弹窗组件，支持姓名和客户号修改，同名客户冲突检测
    ├── countdown_refresh_button.dart      # 倒计时刷新按钮组件，自动更新净值
    ├── custom_fund_config_dialog.dart     # 自定义基金配置对话框，支持基金代码验证
    ├── empty_state.dart                   # 空状态组件，无数据时显示的占位图标和提示文字
    ├── floating_tab_bar.dart              # 底部导航栏组件，滚动时变化透明度
    ├── fund_card.dart                     # 基金卡片组件，展示基金名称/代码/净值/收益/收益率
    ├── fund_performance_chart.dart        # 基金业绩走势折线图组件，支持多指标对比
    ├── fund_performance_dialog.dart       # 基金业绩详情弹窗组件，展示多周期业绩表现
    ├── glass_button.dart                  # 全局磨玻璃风格按钮组件
    ├── gradient_card.dart                 # 渐变卡片组件，客户分组、基金分组标题
    ├── paginated_list_view.dart           # 分页列表组件，支持懒加载和无限滚动
    ├── refresh_button.dart                # 刷新按钮组件，封装刷新逻辑
    ├── search.dart                        # 顶部搜索栏组件，防抖支持条件搜索
    ├── stock_candle_chart.dart            # 股票 K 线蜡烛图组件，支持日 K/周 K/月 K 切换
    ├── stock_chart_widget.dart            # 股票图表容器组件，封装 K 线图和成交量图
    ├── stock_detail_dialog.dart           # 股票详情弹窗组件，显示实时行情、价格呼吸动画、K 线图
    ├── theme_switch.dart                  # 主题切换组件，药丸状滑动开关
    ├── toast.dart                         # Toast 提示组件，全局消息提示
    ├── top_holdings_widget.dart           # 前十大重仓股展示组件
    ├── transaction_history_dialog.dart    # 交易历史对话框，展示某客户某基金的所有交易记录
    └── update_dialog.dart                 # 版本更新提示对话框，显示新版本信息和下载选项
```

## ⚖️ 开源协议

本项目采用 **GNU Affero General Public License v3.0 (AGPL-3.0)** 协议授权。

------

###   声明

- 本项目仅供**个人学习**与**技术交流**使用，不得用于任何商业用途。
- 项目中展示的所有数据及计算结果均来自公开网络接口，**不保证其准确性、完整性或及时性**。
- 本项目所提供的信息**不构成任何投资建议**。
- 请在遵守相关法律法规及数据源服务条款的前提下使用.



**FundLink** - 让每一份资产波动都尽在掌握。

Designed with ❤️ for Finance Professionals.
