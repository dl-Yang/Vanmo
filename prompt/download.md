# VanmoMac 和 VanmoIos 下载功能开发

## UI功能入口

### MacMediaDetailView macOS 媒体详情页
- 在 @VanmoMac/UI/MediaDetail/MacMediaDetailView.swift 页面的【收藏按钮】旁边新增一个同样风格的下载按钮
- 点击下载按钮可以下载对应的播放文件

### MediaDetailView ios 媒体详情页
-  @Vanmo/Features/Library/Views/MediaDetailView.swift，io s 中已经有了下载按钮，现在为 ios 添加下载功能
- 点击下载按钮可以下载对应的播放文件
### MacConnectionsBrowseView macOS 已保存的协议连接页面
- @VanmoMac/UI/Browser/Views/MacConnectionsBrowseView.swift VanmoMac 为**可播放的**文件菜单添加下载操作

### 
- @Vanmo/Features/Browser/Views/BrowserView.swift ios 为**可播放的**文件 长按新增下载操作

## 下载
- 下载中的内容将用一个新的 macos `window `和 ios 使用新页面 显示页面显示每个文件的下载进度
- 显示页面显示每个文件的下载进度，资源名称和和对应元数据信息（注意元数据不下载）
- 下载完成的资源可以直接进行点击播放；下载**被打断**将记住进度允许**断点续传**下载。
- 因为网络问题或者别的原因 **下载失败** 则需要重新下载

## 下载管理
- 拥有默认下载位置路径
- 允许管理修改媒体文件的本地下载位置
- 下载页面允许进行**多选**，选中的item 将能被**删除**
- 允许选中**单个**item然后访问本地文件项目

