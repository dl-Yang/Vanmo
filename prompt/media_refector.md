# 功能重构
## 媒体库页面
1. emby 协议（包括类 emby 等协议比如 jellyfin）:
- 首页作为媒体库进行媒体项的展示，将提取出来的媒体项分类然后进行
**媒体类型type** 只提取：
视频类：
Movie           电影                                        
Series          电视剧（剧集顶层）
Season          季
Episode         单集
Video           普通视频（家庭录像、未归类视频）
容器类：
Folder              通用文件夹
CollectionFolder    媒体库根（电影库、剧集库）
UserView            用户视角下的库视图
BoxSet              合集（系列电影合集，比如哈利波特系列）
Playlist            播放列表
UserRootFolder      用户根
AggregateFolder     聚合文件夹
枚举映射
Movie / Video       -> .movie
Series              -> .tvShow
Episode             -> .tvEpisode
Season              -> .season
Folder              -> .folder
CollectionFolder    -> .collectionFolder
UserView            -> .collectionFolder
BoxSet              -> .collectionFolder
Audio               -> .audio
MusicAlbum          -> .musicAlbum
Photo               -> .photo
其他                 -> .other

