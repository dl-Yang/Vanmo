# 功能重构
## 媒体库页面
### emby 协议（包括类 emby 等协议比如 jellyfin）:
- 首页依然作为媒体库进行媒体项的展示
- 首页将不再展示详细的媒体条目而是请求 CollectionFolder，调用  **/Library/VirtualFolders** 接口作为第一入口，接口数据格式可以参考 folder_api_example.md
Embby CollectionType包括以下内容:
movies       电影库
tvshows      电视剧库
music        音乐库
musicvideos  音乐视频库
homevideos   家庭视频/照片视频
boxsets      合集
books        书籍
photos       照片库
mixed        混合内容
CollectionType **只保留 movies / tvshows / playlist**。
- 首页获取到 CollectionFolder 后，在首页进行展示，进入 CollectionFloder 内部则是可以看到 CollectionFolder 内的媒体内容列表的 [List] 页面作为第二级页面
List 页面会获取该 CollectionFolder 内的所有支持的**媒体类型Type**的媒体内容，点击任意媒体内容将进入到现有的详情页面
- **对于 Series， Season，Episode 的电视剧类型处理保持现在的逻辑：List 页面只展示 Series 大类型，进入到详情页再检索 Season 和 Episode**
**媒体类型Type** 只提取：

CollectionFolder    媒体库根（电影库、剧集库）
Movie           电影                                        
Series          电视剧（剧集顶层）
Season          季
Episode         单集
Video           普通视频（家庭录像、未归类视频）

枚举映射
Movie / Video       -> .movie
Series              -> .tvShow
Episode             -> .tvEpisode
Season              -> .season
CollectionFolder    -> .collectionFolder

