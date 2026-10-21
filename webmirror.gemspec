#coding:utf-8
# func: webmirror gemspec, 手动列文件 + require_paths=["."]
Gem::Specification.new do|s|
  s.name = 'webmirror'
  s.version = '0.1.0'
  s.summary = '网页快速镜像 + 微信文章转 Markdown 命令行工具'
  s.description = '镜像页面资源本地化(外链保留跳转互联网, 特效可用), 微信文章提取 md+图片, todo-list 批处理自动清除并更新 index.html'
  s.authors = ['inclimber']
  s.email = %q{matthrewchains@gmail.com}
  s.files = ['webmirror.rb', 'wmirror.rb', 'wxmd.rb', 'bin/web-mir', 'README.md']
  s.bindir = 'bin'
  s.executables = ['web-mir']
  s.require_paths = ["."]
  s.homepage = %q{http://127.0.0.1}
  s.license = 'MIT'
  s.add_dependency 'nokogiri', '>= 1.10'
  s.required_ruby_version = '>= 3.0'
end