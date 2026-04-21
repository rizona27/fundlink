# FundLink | 一基暴富 📈

------

## ✨ 核心特性

- 📊 **资产分析**：
  - **收益率计算**：支持绝对收益与年化收益率的分开计算。
  - **穿透式分析**：自动展示基金“十大重仓股”及占比。
  - **业绩曲线**：可视化基金净值走势与对比。
- 📥 **数据流**：
  - **模糊智能导入**：支持 CSV/Excel 批量导入，具备日期与格式模糊匹配能力。
  - **自定义导出**：可根据需求组合字段（客户号、备注、净值等）导出汇总数据。
- 🔒 **信息安全**：
  - **隐私模式**：脱敏展示基金信息，方便截屏转发。
  - **本地化存储**：数据全量存储于本地，不经过第三方。

------

## 🚀 部署与运行

### 环境要求

- Flutter SDK >= 3.x
- CocoaPods (用于 iOS 编译)

### 快速开始

Bash

```
# 克隆仓库
git clone https://github.com/rizona27/fundlink.git

# 安装依赖
flutter pub get

# 运行生成代码 (如果使用了 build_runner)
flutter pub run build_runner build

# 启动项目
flutter run
```

------

## 📝 项目结构


```text

lib/
├── main.dart                              # 应用入口，初始化DataManager，配置主题模式（浅色/深色/跟随系统）
│
├── services/
│   ├── data_manager.dart                  # 数据管理核心，持仓增删改查、日志记录、隐私模式、收益计算、持久化
│   ├── file_export_service.dart           # 支持导出组件，解析格式类型CSV/Excel
│   ├── file_import_service.dart           # 支持导入组件，解析格式类型CSV/Excel
│   └── fund_service.dart                  # 基金API服务，调用接口获取数据，含缓存和重试机制
│
├── models/
│   ├── fund_holding.dart                  # 持仓数据模型，客户信息、基金代码/名称、购买金额/份额/日期、净值、收益计算属性
│   ├── log_entry.dart                     # 日志条目模型，消息内容、日志类型（信息/成功/错误/警告/网络/缓存）、时间戳
│   ├── net_worth_point.dart               # 净值及趋势
│   ├── profit_result.dart                 # 收益结果模型，绝对收益、年化收益率
│   └── top_holding.dart                   # 十大重仓情况
│
├── views/
│   ├── add_holding_view.dart              # 新增持仓页，表单输入信息
│   ├── client_view.dart                   # 客户视图页，分组展示持仓
│   ├── config_view.dart                   # 程序设置相关页面，隐私/主题切换/日志查询/持仓管理及其他
│   ├── edit_holding_view.dart             # 编辑持仓页，修改已有持仓信息
│   ├── export_holding_view.dart           # 导出文件页面，支持CSV/Excel
│   ├── fund_detail_view.dart              # 基金详情页，包含估值/净值趋势/十大重仓
│   ├── history_view.dart                  # 历史净值弹窗页
│   ├── inport_holding_view.dart           # 导入文件页面，支持CSV/Excel
│   ├── license_view.dart                  # 本程序应用的开源协议AGPL v3
│   ├── log_view.dart                      # 日志页面，以功能性分类展示日志
│   ├── manage_holdings_view.dart          # 管理持仓页，编辑/删除/客户与基金持仓信息
│   ├── splash_view.dart                   # 开场动画页
│   ├── summary_view.dart                  # 基金汇总页，按基金代码分组，显示基金详情及收益
│   ├── top_performers_view.dart           # 收益排行页，按金额/收益/收益率/持有天数排序，支持筛选
│   └── version_view.dart                  # 更新软件和版本信息
│
└── widgets/
    ├── adaptive_top_bar.dart              # 顶部工具栏组件，包含是刷新、搜索、筛选等
    ├── countdown_refresh_button.dart      # 顶部工具栏内估值组件，自动更新，间隔设置
    ├── empty_state.dart                   # 空状态组件，无数据时显示的占位图标和提示文字
    ├── floating_tab_bar.dart              # 底部导航栏组件，滚动时变化透明度，磨玻璃和阴影效果
    ├── fund_card.dart                     # 基金卡片组件，展示基金名称/代码/净值/收益/收益率
    ├── fund_performance_chart.dart        # 基金业绩走势折线图组件，在基金详情页中调用
    ├── glass_button.dart                  # 全局磨玻璃风格按钮组件
    ├── gradient_card.dart                 # 渐变卡片组件，客户分组、基金分组标题
    ├── refresh_button.dart                # 刷新按钮组件，封装刷新逻辑
    ├── search.dart                        # 顶部搜索栏组件，防抖支持条件搜索
    ├── theme_switch.dart                  # 主题切换组件，药丸状滑动开关，浅色/跟随系统/深色
    └── toast.dart                         # Toast提示组件，全局消息提示，淡入淡出动画，自动消失
```

## ⚖️ 开源协议

本项目采用 **GNU Affero General Public License v3.0 (AGPL-3.0)** 协议授权。

------

###   声明

- 本项目仅供**个人学习**与**技术交流**使用，不得用于任何商业用途。
- 项目中展示的所有数据及计算结果均来自公开网络接口，**不保证其准确性、完整性或及时性**。
- 本项目所提供的信息**不构成任何投资建议**。
- 请在遵守相关法律法规及数据源服务条款的前提下使用。



**FundLink** - 让每一份资产波动都尽在掌握。

Designed with ❤️ for Finance Professionals.
