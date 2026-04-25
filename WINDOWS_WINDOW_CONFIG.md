# Windows 窗口配置指南

## 概述

本文档说明如何配置 Windows 平台的窗口属性，包括初始尺寸、最小尺寸等。

## 文件位置

所有 Windows 窗口相关的配置都在以下目录：
```
windows/runner/
├── main.cpp              # 主入口，设置窗口初始参数
├── win32_window.h        # Win32Window 类声明
└── win32_window.cpp      # Win32Window 类实现
```

## 当前配置

### 1. 初始窗口尺寸

**文件**: `windows/runner/main.cpp`

```cpp
Win32Window::Size size(1280, 720);  // 宽1280px，高720px
```

这是应用启动时的默认窗口大小。

### 2. 最小窗口尺寸

**文件**: `windows/runner/main.cpp`

```cpp
window.SetMinimumSize(800, 600);  // 最小宽800px，高600px
```

用户无法将窗口缩小到此尺寸以下。

### 3. 窗口位置

**文件**: `windows/runner/main.cpp`

```cpp
Win32Window::Point origin(10, 10);  // 距离屏幕左上角各10px
```

## 如何修改配置

### 修改初始窗口尺寸

编辑 `windows/runner/main.cpp` 第29行：

```cpp
// 修改前
Win32Window::Size size(1280, 720);

// 修改后（例如改为1920x1080）
Win32Window::Size size(1920, 1080);
```

### 修改最小窗口尺寸

编辑 `windows/runner/main.cpp` 第36行：

```cpp
// 修改前
window.SetMinimumSize(800, 600);

// 修改后（例如改为1024x768）
window.SetMinimumSize(1024, 768);
```

### 修改窗口初始位置

编辑 `windows/runner/main.cpp` 第28行：

```cpp
// 修改前
Win32Window::Point origin(10, 10);

// 修改后（例如居中显示）
Win32Window::Point origin(100, 100);
```

## 推荐配置

### 标准桌面应用

适合大多数场景：
```cpp
Win32Window::Size size(1280, 720);     // 初始尺寸
window.SetMinimumSize(800, 600);       // 最小尺寸
```

### 宽屏优化

适合内容较多的应用：
```cpp
Win32Window::Size size(1920, 1080);    // 初始尺寸
window.SetMinimumSize(1024, 768);      // 最小尺寸
```

### 紧凑布局

适合简洁的工具类应用：
```cpp
Win32Window::Size size(1024, 600);     // 初始尺寸
window.SetMinimumSize(640, 480);       // 最小尺寸
```

## 技术实现细节

### WM_GETMINMAXINFO 消息处理

在 `win32_window.cpp` 中，我们处理了 `WM_GETMINMAXINFO` 消息来限制最小窗口尺寸：

```cpp
case WM_GETMINMAXINFO: {
  auto min_max_info = reinterpret_cast<MINMAXINFO*>(lparam);
  if (min_width_ > 0 && min_height_ > 0) {
    // Convert client size to window size (including borders and title bar)
    RECT window_rect = {0, 0, static_cast<LONG>(min_width_), static_cast<LONG>(min_height_)};
    AdjustWindowRectEx(&window_rect, GetWindowStyle(hwnd), FALSE, GetWindowExStyle(hwnd));
    min_max_info->ptMinTrackSize.x = window_rect.right - window_rect.left;
    min_max_info->ptMinTrackSize.y = window_rect.bottom - window_rect.top;
  }
  return 0;
}
```

**关键点**：
- 使用 `AdjustWindowRectEx` 将客户区尺寸转换为窗口尺寸
- 自动考虑标题栏、边框等系统装饰
- 支持不同 DPI 设置

### DPI 感知

窗口尺寸会自动根据 DPI 进行缩放：

```cpp
UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
double scale_factor = dpi / 96.0;

HWND window = CreateWindow(
    window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
    Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
    Scale(size.width, scale_factor), Scale(size.height, scale_factor),
    nullptr, nullptr, GetModuleHandle(nullptr), this);
```

这确保了在不同分辨率和缩放比例的显示器上，窗口的实际物理尺寸保持一致。

## 常见问题

### Q1: 为什么设置了最小尺寸后，窗口仍然可以缩小？

**A**: 确保调用了 `SetMinimumSize()` 方法，并且传入的参数大于0：

```cpp
window.SetMinimumSize(800, 600);  // ✅ 正确
window.SetMinimumSize(0, 0);      // ❌ 无效
```

### Q2: 如何让窗口启动时最大化？

**A**: 修改 `main.cpp` 中的 `Show()` 调用：

```cpp
// 修改 win32_window.cpp 中的 Show() 方法
bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWMAXIMIZED);  // 最大化显示
}
```

### Q3: 如何限制最大窗口尺寸？

**A**: 可以在 `WM_GETMINMAXINFO` 处理中添加最大尺寸限制：

```cpp
case WM_GETMINMAXINFO: {
  auto min_max_info = reinterpret_cast<MINMAXINFO*>(lparam);
  
  // 最小尺寸
  if (min_width_ > 0 && min_height_ > 0) {
    RECT window_rect = {0, 0, static_cast<LONG>(min_width_), static_cast<LONG>(min_height_)};
    AdjustWindowRectEx(&window_rect, GetWindowStyle(hwnd), FALSE, GetWindowExStyle(hwnd));
    min_max_info->ptMinTrackSize.x = window_rect.right - window_rect.left;
    min_max_info->ptMinTrackSize.y = window_rect.bottom - window_rect.top;
  }
  
  // 最大尺寸（需要添加 max_width_ 和 max_height_ 成员变量）
  if (max_width_ > 0 && max_height_ > 0) {
    RECT window_rect = {0, 0, static_cast<LONG>(max_width_), static_cast<LONG>(max_height_)};
    AdjustWindowRectEx(&window_rect, GetWindowStyle(hwnd), FALSE, GetWindowExStyle(hwnd));
    min_max_info->ptMaxTrackSize.x = window_rect.right - window_rect.left;
    min_max_info->ptMaxTrackSize.y = window_rect.bottom - window_rect.top;
  }
  
  return 0;
}
```

### Q4: 窗口尺寸是否包含标题栏和边框？

**A**: 
- **初始尺寸** (`size`): 指的是客户区尺寸（不包含标题栏和边框）
- **最小尺寸** (`SetMinimumSize`): 也是指客户区尺寸，但内部会自动转换为窗口总尺寸

系统会自动处理转换，你只需要关心内容区域的尺寸即可。

### Q5: 如何保存和恢复窗口位置和尺寸？

**A**: 需要使用 Windows API 或第三方库来实现持久化存储。基本思路：

1. 在窗口关闭时保存位置和尺寸到注册表或配置文件
2. 在窗口创建时读取并应用这些值

示例代码（简化版）：

```cpp
// 保存窗口状态
void SaveWindowState(HWND hwnd) {
  WINDOWPLACEMENT wp;
  wp.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(hwnd, &wp);
  
  // 保存到注册表或文件
  // ...
}

// 恢复窗口状态
void RestoreWindowState(HWND hwnd) {
  // 从注册表或文件读取
  // ...
  
  WINDOWPLACEMENT wp;
  SetWindowPlacement(hwnd, &wp);
}
```

## macOS 和 Linux 平台

### macOS

macOS 的窗口配置在 `macos/Runner/MainFlutterWindow.swift` 中：

```swift
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // 设置最小尺寸
    self.minSize = NSSize(width: 800, height: 600)
    
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
```

### Linux

Linux 的窗口配置在 `linux/my_application.cc` 中：

```cpp
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // 设置初始尺寸
  gtk_window_set_default_size(window, 1280, 720);
  
  // 设置最小尺寸
  gtk_window_set_resizable(window, TRUE);
  GdkGeometry geometry;
  geometry.min_width = 800;
  geometry.min_height = 600;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  gtk_widget_show(GTK_WIDGET(window));
}
```

## 最佳实践

### 1. 选择合适的初始尺寸

- **内容驱动**: 根据主要内容区域的需求确定
- **目标用户**: 考虑用户的典型屏幕分辨率
- **行业标准**: 参考同类应用的常见尺寸

### 2. 合理设置最小尺寸

- **可用性优先**: 确保所有功能在最小尺寸下仍可使用
- **测试验证**: 在最小尺寸下测试所有页面和功能
- **留有余地**: 不要设置得太小，保持一定的边距

### 3. 响应式设计

即使设置了最小尺寸，也应该确保应用在不同尺寸下都能良好显示：

```dart
// Flutter 中使用 LayoutBuilder 实现响应式布局
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < 600) {
      // 窄屏布局
      return MobileLayout();
    } else {
      // 宽屏布局
      return DesktopLayout();
    }
  },
)
```

### 4. 考虑多显示器

- 测试在不同分辨率和 DPI 的显示器上的表现
- 确保窗口不会超出屏幕边界
- 考虑支持多显示器拖拽

## 性能影响

设置窗口尺寸对性能的影响微乎其微：

- **初始尺寸**: 只影响启动时的窗口大小，不影响运行时性能
- **最小尺寸**: 只在用户调整窗口大小时生效，CPU占用可忽略不计
- **DPI 缩放**: 自动处理，无需额外优化

## 总结

✅ **已完成**：
- 设置初始窗口尺寸为 1280x720
- 设置最小窗口尺寸为 800x600
- 支持 DPI 自动缩放
- 正确处理窗口装饰（标题栏、边框）

📝 **建议**：
- 根据实际应用内容调整尺寸
- 在所有支持的平台上测试
- 考虑添加窗口状态持久化
- 实现响应式布局以适配不同尺寸

---

**最后更新**: 2026-04-25  
**适用版本**: fundlink v1.0+
