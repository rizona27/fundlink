![](http://github-profile-summary-cards.vercel.app/api/cards/repos-per-language?username=rizona27&theme=buefy)
![](http://github-profile-summary-cards.vercel.app/api/cards/productive-time?username=rizona27&theme=buefy&utcOffset=8)
```text
lib/
├── main.dart                              # 应用入口，初始化DataManager，配置主题模式（浅色/深色/跟随系统），管理主题切换动画
│
├── services/
│   ├── data_manager.dart                  # 数据管理核心，持仓增删改查、日志记录、隐私模式、收益计算、SharedPreferences持久化
│   └── fund_service.dart                  # 基金API服务，调用天天基金接口获取净值/名称/收益率，含缓存和重试机制
│
├── models/
│   ├── fund_holding.dart                  # 持仓数据模型，客户信息、基金代码/名称、购买金额/份额/日期、净值、收益计算属性
│   ├── log_entry.dart                     # 日志条目模型，消息内容、日志类型（信息/成功/错误/警告/网络/缓存）、时间戳
│   └── profit_result.dart                 # 收益结果模型，绝对收益、年化收益率
│
├── views/
│   ├── add_holding_view.dart              # 新增持仓页，表单输入客户姓名/基金代码/金额/份额/日期，保存后自动获取基金信息
│   ├── client_view.dart                   # 客户视图页，按客户分组展示持仓，支持搜索、展开/折叠、刷新、隐私模式
│   ├── config_view.dart                   # 设置页，隐私模式开关、主题切换、日志查询、新增/管理持仓入口
│   ├── edit_holding_view.dart             # 编辑持仓页，修改已有持仓信息，基金代码变更时重新获取基金数据
│   ├── manage_holdings_view.dart          # 管理持仓页，批量修改客户姓名、批量删除客户、单个编辑/删除持仓
│   ├── summary_view.dart                  # 基金汇总页，按基金代码分组，显示每个基金的持有人及收益
│   └── top_performers_view.dart           # 收益排行页，按金额/收益/收益率/持有天数排序，支持筛选
│
└── widgets/
    ├── empty_state.dart                   # 空状态组件，无数据时显示的占位图标和提示文字
    ├── floating_tab_bar.dart	           # 底部导航栏组件，滚动时变化透明度，磨玻璃和阴影效果
    ├── fund_card.dart                     # 基金卡片组件，展示基金名称/代码/净值/收益/收益率，支持深色模式
    ├── glass_button.dart                  # 全局，磨玻璃风格按钮组件
    ├── gradient_card.dart                 # 渐变卡片组件，客户分组标题，支持展开/折叠动画，深色/浅色模式适配
    ├── refresh_button.dart                # 刷新按钮组件，封装刷新逻辑（并发控制、重试机制、加载遮罩），显示刷新动画
    ├── search.dart                        # 搜索栏组件，防抖支持名称、客户号、基金名、基金代码搜索
    ├── theme_switch.dart                  # 主题切换组件，药丸状滑动开关，支持浅色/跟随系统/深色三种模式
    └── toast.dart                         # Toast提示组件，全局消息提示，淡入淡出动画，自动消失
```

![](http://github-profile-summary-cards.vercel.app/api/cards/profile-details?username=rizona27&theme=buefy)
