# mac 版本 ui 优化
- 侧边栏宽度需要可调节
- 控制侧边栏展开收起的开关放到“交通灯”旁边，不再`mainConent`中为每个页面单独添加
- `mainContent`的内容应该顶到窗口的最顶部，现在被 `window.titleBar` 挤下去了（也就是说我希望完全去掉 titlBar 布局）
- `VanmoRootView`的毛玻璃效果需要能跟随主题（Light 和 Dark）进行颜色变化，现在毛玻璃始终是白色背景需要优化。