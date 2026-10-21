# 网页镜像 web-mir (gem: webmirror)

网页快速镜像 + 微信文章转 Markdown 命令行工具, Ruby 编写.

## 安装

```
gem build webmirror.gemspec
gem install webmirror-0.1.0.gem
```

依赖 nokogiri 自动安装.

## 用法

```
web-mir <url> [<url2> ...]   直接镜像/提取
web-mir                      处理 todo-list.txt (每行一个网页)
web-mir --md <url|文件>      强制转 Markdown (在线或本地页面)
web-mir --list               查看待处理清单
web-mir --add <url>          加入待处理清单
web-mir --help               帮助
```

## 行为

- 普通页面镜像: 资源本地化到 `网页标题_时间戳/assets/`, CSS/JS/图片/字体/音视频全部落地, 外链保留点击仍跳转互联网, 本地特效(hover/JS)可用
- 微信链接 (mp.weixin.qq.com): 自动识别并提取 Markdown + 图片引用; raw.html 轻量本地化(图片落地, 表格兜底样式), 本地打开快且有边框
- 处理成功的条目自动从 todo-list.txt 清除, 注释行(#)与空行保留
- 完成后自动更新 `index.html` 镜像索引 (深蓝表头表格, 已有则更新)

## 开发模式

```
ruby webmirror.rb <url>    # 直接跑源码
```

## 文件

- `webmirror.rb`  CLI 入口
- `wmirror.rb`   镜像核心 (下载/本地化)
- `wxmd.rb`      微信提取
- `webmirror.gemspec`  打包定义 (require_paths=["."])