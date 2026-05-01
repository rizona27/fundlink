# FundLink | 一基暴富 📈

一款专业的基金持仓管理与分析工具，支持多平台部署（iOS/Android/Windows/macOS/Linux）。

------

## 📋 目录

- [✨ 核心特性](#-核心特性)
- [🚀 快速开始](#-快速开始)
- [📁 项目结构](#-项目结构)
- [📝 开发指南](#-开发指南)
- [⚖️ 开源协议](#️-开源协议)
- [📜 免责声明](#-免责声明)

------

## ✨ 核心特性

- 📊 **资产分析**：
  - **收益率计算**：支持绝对收益与年化收益率的分开计算。
  - **穿透式分析**：自动展示基金“十大重仓股”及占比。
  - **业绩曲线**：可视化基金净值走势与对比。
  - **交易流水管理**：支持同一客户对同一基金的多次买入/卖出，自动计算加权平均成本。
  - **待确认交易管理**：智能识别T日15:00前后交易，自动标记待确认状态，T+1/T+2日自动确认净值。
- 📥 **数据流**：
  - **模糊智能导入**：支持 CSV/Excel 批量导入，具备日期与格式模糊匹配能力。
  - **自定义导出**：可根据需求组合字段（客户号、备注、净值等）导出汇总数据。
- 🔒 **信息安全**：
  - **隐私模式**：脱敏展示基金信息，方便截屏转发。
  - **本地化存储**：数据全量存储于本地，不经过第三方。
- 🔔 **智能预警**（移动端）：
  - **估值预警**：设置基金净值涨跌阈值，交易时段自动监控并推送通知。
  - **智能时段控制**：仅在交易日9:30-15:30检查，闭市前1小时发送紧急通知。
  - **省电优化**：非交易时段自动休眠，减少电量消耗。
- 👤 **生物识别**（移动端）：
  - **应用锁定**：支持Face ID/Touch ID/指纹识别保护应用安全。
  - **后台检测**：应用切换到后台后自动锁定，返回时需验证身份。
  - **灵活配置**：可设置锁定延迟时间（立即/30秒/1分钟/5分钟）。

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
text
lib/
├── main.dart                              # 应用入口，初始化DataManager，配置主题模式（浅色/深色/跟随系统）
│
├── constants/
│   └── app_constants.dart                 # 全局常量管理，统一管理API地址、缓存键名、业务常量等，支持API冗余设计
│
├── services/
│   ├── alert_service.dart                 # 估值预警服务，管理预警规则、智能时段控制、本地推送通知
│   ├── biometric_guard.dart               # 生物识别保护服务，监听应用生命周期、触发身份验证、管理锁定状态
│   ├── china_trading_day_service.dart     # 中国交易日判断服务，智能识别法定节假日和调休补班，采用三层降级策略（专业API → world_holidays → 基础判断），内置内存缓存优化性能
│   ├── data_manager.dart                  # 数据管理核心，持仓增删改查、交易记录管理、日志记录、隐私模式、收益计算、持久化、自动化缓存失效
│   ├── database_helper.dart               # SQLite数据库帮助类，跨平台数据库支持（iOS/Android/Windows/macOS/Linux），提供CRUD操作和Schema管理
│   ├── file_export_service.dart           # 支持导出组件，解析格式类型CSV/Excel
│   ├── file_import_service.dart           # 支持导入组件，解析格式类型CSV/Excel
│   └── fund_service.dart                  # 基金API服务，调用接口获取数据，含多源冗余、缓存和重试机制
│
├── models/
│   ├── fund_holding.dart                  # 持仓数据模型（聚合视图），客户信息、基金代码/名称、累计投入、持有份额、平均成本、净值、收益计算属性，支持SQLite序列化(toMap/fromMap)
│   ├── fund_info_cache.dart               # 基金信息缓存模型，存储基金代码、名称、当前净值、估值等数据的本地缓存结构
│   ├── log_entry.dart                     # 日志条目模型，消息内容、日志类型（信息/成功/错误/警告/网络/缓存）、时间戳，支持SQLite序列化(toMap/fromMap)
│   ├── net_worth_point.dart               # 净值及趋势
│   ├── profit_result.dart                 # 收益结果模型，绝对收益、年化收益率
│   ├── top_holding.dart                   # 十大重仓情况
│   ├── transaction_record.dart            # 交易记录模型，单笔买入/卖出交易的详细信息（金额、份额、日期、净值、手续费等），支持SQLite序列化(toMap/fromMap)
│   └── valuation_alert.dart               # 估值预警规则模型，基金代码/名称、涨跌阈值、启用状态、创建时间
│
├── views/
│   ├── add_holding_view.dart              # 新增持仓页，表单输入客户信息、基金代码、交易金额/份额/日期，支持重复持仓检测与合并，自动查询基金名称和净值
│   ├── client_view.dart                   # 客户视图页，分组展示持仓
│   ├── config_view.dart                   # 程序设置相关页面，隐私/主题切换/日志查询/持仓管理及其他
│   ├── edit_holding_view.dart             # 编辑持仓页，显示持仓详情，支持加仓/减仓操作，查看交易历史
│   ├── export_holding_view.dart           # 导出文件页面，支持CSV/Excel
│   ├── fund_detail_view.dart              # 基金详情页，包含估值/净值趋势/十大重仓
│   ├── history_view.dart                  # 历史净值弹窗页
│   ├── import_holding_view.dart           # 导入文件页面，支持CSV/Excel
│   ├── license_view.dart                  # 本程序应用的开源协议AGPL v3
│   ├── log_view.dart                      # 日志页面，以功能性分类展示日志
│   ├── manage_holdings_view.dart          # 管理持仓页，编辑/删除/客户与基金持仓信息，支持批量重命名
│   ├── pending_transactions_view.dart     # 待确认交易管理页，展示T+1/T+2待确认的交易列表，支持手动刷新确认，显示预计确认日期和状态
│   ├── splash_view.dart                   # 开场动画页
│   ├── summary_view.dart                  # 基金汇总页，按基金代码分组，显示基金详情及收益
│   ├── top_performers_view.dart           # 收益排行页，按金额/收益/收益率/持有天数排序，支持筛选
│   └── version_view.dart                  # 版本信息页，显示应用版本和功能说明
│
└── widgets/
    ├── adaptive_top_bar.dart              # 顶部工具栏组件，包含刷新、搜索、筛选等功能，支持防抖搜索
    ├── add_transaction_dialog.dart        # 加仓/减仓对话框，支持交易金额/份额/净值/费率输入，自动计算预估数据
    ├── alert_edit_dialog.dart             # 估值预警编辑弹窗组件，支持新建/编辑预警规则，表单验证和错误提示
    ├── batch_rename_dialog.dart           # 批量重命名弹窗组件，支持同名客户冲突检测和提示
    ├── biometric_lock_overlay.dart        # 生物识别锁定覆盖层组件，显示锁定界面、验证按钮、解锁动画
    ├── countdown_refresh_button.dart      # 倒计时刷新按钮组件，自动更新净值，间隔可设置
    ├── custom_fund_config_dialog.dart     # 自定义基金配置对话框，弹出式页面，支持基金代码验证和存在性检查
    ├── empty_state.dart                   # 空状态组件，无数据时显示的占位图标和提示文字
    ├── floating_tab_bar.dart              # 底部导航栏组件，滚动时变化透明度，磨玻璃和阴影效果
    ├── fund_card.dart                     # 基金卡片组件，展示基金名称/代码/净值/收益/收益率，提供"交易记录"入口
    ├── fund_performance_chart.dart        # 基金业绩走势折线图组件，在基金详情页中调用，支持多指标对比（本基金/同类平均/沪深300/中证500/中证1000/自定义基金）
    ├── fund_performance_dialog.dart       # 基金业绩详情弹窗组件，展示多周期业绩表现（近1周~成立来），优先使用API数据，自动计算补充周期
    ├── glass_button.dart                  # 全局磨玻璃风格按钮组件
    ├── gradient_card.dart                 # 渐变卡片组件，客户分组、基金分组标题
    ├── refresh_button.dart                # 刷新按钮组件，封装刷新逻辑
    ├── search.dart                        # 顶部搜索栏组件，防抖支持条件搜索
    ├── stock_candle_chart.dart            # 股票K线蜡烛图组件，支持日K/周K/月K切换，拖动查看历史数据，十字线交互，动态Y轴刻度
    ├── stock_chart_widget.dart            # 股票图表容器组件，封装K线图和成交量图的组合显示
    ├── stock_detail_dialog.dart           # 股票详情弹窗组件，显示实时行情、价格呼吸动画、K线图，支持交易时间自动刷新
    ├── theme_switch.dart                  # 主题切换组件，药丸状滑动开关，浅色/跟随系统/深色
    ├── toast.dart                         # Toast提示组件，全局消息提示，淡入淡出动画，自动消失
    ├── top_holdings_widget.dart           # 前十大重仓股展示组件，左右分栏布局，显示股票名称、涨跌幅、占比、市场标识
    └── transaction_history_dialog.dart    # 交易历史对话框，展示某客户某基金的所有交易记录
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
