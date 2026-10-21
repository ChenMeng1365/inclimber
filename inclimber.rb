#coding:utf-8
# func: 网页镜像 CLI: 参数URL或读取当前目录 todo-list.txt, 完成即清除条目, 刷新 index.html
# CALL: ruby inclimber.rb <url> [<url>...]     直接镜像/提取
# CALL: ruby inclimber.rb --md <url> [<url>...] 强制提取 Markdown
# CALL: ruby inclimber.rb --list              查看待处理清单
# CALL: ruby inclimber.rb --add <url> [<url>] 加入待处理清单
# CALL: ruby inclimber.rb                     处理 todo-list.txt (每行一个网页)

require 'fileutils'
require_relative 'wmirror'
require_relative 'wxmd'

TODO = 'todo-list.txt'
INDEX = 'index.html'

#### 工具 ####
def usage
  puts <<~EOS
    用法:
      web-mir <url> [<url2> ...]          直接镜像/提取
      web-mir --md <url> [...]              强制转 Markdown
      web-mir --list                     查看待处理清单
      web-mir --add <url> [...]             加入待处理清单
      web-mir                              处理 todo-list.txt (每行一个网页)
    说明:
      微信链接自动走提取; 其余走镜像(资源本地化, 外链保留跳转互联网)
      输出目录: 网页标题_时间戳/ ; 完成后更新 index.html 索引
  EOS
end

def ts
  Time.now.strftime('%Y%m%d%H%M%S%3N')
end

def out_dir title
  n = WMirror.clean_title(title)
  n = 'page' if n.empty? or n == '.' or n == '..'
  d = "#{n}_#{ts}"
  d = "#{n}_#{ts}_#{rand(1000)}" while File.exist?(d)
  d
end

def esc t
  t.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

def is_wx? url
  url.to_s.include?('mp.weixin.qq.com') or url.to_s.include?('weixin')
end

#### 处理 ####
def process url
  url = url.strip
  return :skip if url.empty? or url.start_with?('#')
  if File.file?(url)
    md_from_file url
  elsif is_wx?(url)
    wx_extract url
  else
    page_mirror url
  end
end

def page_mirror url
  puts "[镜像] #{url}"
  r = WMirror.fetch_page url
  raise '下载失败' unless r
  html, murl, title = r
  dir = out_dir title
  FileUtils.mkdir_p dir
  body = WMirror.localize_html html, murl, dir
  fname = WMirror.page_name murl
  File.binwrite File.join(dir, fname), body
  puts "  => #{dir}\\#{fname}  (标题: #{title})"
  true
rescue => e
  puts "  [失败] #{e.class}: #{e.message}"
  false
end

def wx_extract url
  puts "[微信] #{url}"
  html, murl, ct = WMirror.grab url
  raise '页面不存在' unless html
  txt = WMirror.to_utf8 html
  title = ''
  doc = Nokogiri::HTML txt
  t = doc.at_css('#activity-name, .rich_media_title, h1.rich_media_title')
  title = t ? t.text.strip : ''
  dir = out_dir title.empty? ? '微信文章' : title
  FileUtils.mkdir_p dir
  r = WxMd.extract txt, murl, dir
  fname = "#{WMirror.clean_title(r[:title])}.md"
  File.write File.join(dir, fname), r[:md], encoding: 'UTF-8'
  # raw.html 轻量本地化: 图片落地/表格兜底样式, 本地打开不慢且有边框
  raw = WMirror.localize_raw txt, murl, dir
  File.write File.join(dir, 'raw.html'), raw, encoding: 'UTF-8'
  puts "  => #{dir}\\#{fname}  (标题: #{r[:title]})"
  true
rescue => e
  puts "  [失败] #{e.class}: #{e.message}"
  false
end

def md_from_file path
  puts "[提取] #{path}"
  txt = File.binread path
  txt = WMirror.to_utf8 txt
  title = File.basename(path, File.extname(path))
  dir = out_dir title
  FileUtils.mkdir_p dir
  r = WxMd.extract txt, File.expand_path(path), dir
  fname = "#{WMirror.clean_title(r[:title])}.md"
  File.write File.join(dir, fname), r[:md], encoding: 'UTF-8'
  # 本地文件同样生成本地化 raw 备份
  raw = WMirror.localize_raw txt, File.expand_path(path), dir
  File.write File.join(dir, 'raw.html'), raw, encoding: 'UTF-8'
  puts "  => #{dir}\#{fname}"
  true
rescue => e
  puts "  [失败] #{e.class}: #{e.message}"
  false
end

def md_from_file path
  puts "[提取] #{path}"
  txt = File.binread path
  txt = WMirror.to_utf8 txt
  title = File.basename(path, File.extname(path))
  dir = out_dir title
  FileUtils.mkdir_p dir
  r = WxMd.extract txt, File.expand_path(path), dir
  fname = "#{WMirror.clean_title(r[:title])}.md"
  File.write File.join(dir, fname), r[:md], encoding: 'UTF-8'
  puts "  => #{dir}\\#{fname}"
  true
rescue => e
  puts "  [失败] #{e.class}: #{e.message}"
  false
end

#### todo ####
def run_todo
  unless File.exist?(TODO)
    puts "未找到 #{TODO}, 请先创建或在命令行传 URL"
    return
  end
  lines = File.readlines(TODO, encoding: 'UTF-8').map { |l| l.gsub("\uFEFF", '').chomp }
  remain = []
  lines.each do|l|
    url = l.strip
    if url.empty? or url.start_with?('#')
      remain << l
      next
    end
    ok = process url
    if ok == true
      puts "  [清除] #{url}"
    else
      remain << l
    end
  end
  File.write TODO, remain.join("\n") + (remain.empty? ? '' : "\n"), encoding: 'UTF-8'
  update_index
end

def list_todo
  unless File.exist?(TODO)
    puts "无 #{TODO}"
    return
  end
  File.readlines(TODO, encoding: 'UTF-8').each_with_index do|l, i|
    s = l.sub("\uFEFF", '').strip
    next if s.empty? or s.start_with?('#')
    puts "#{i + 1}: #{s}"
  end
end

def add_todo urls
  urls.each do|u|
    next if u.empty?
    File.open(TODO, 'a', encoding: 'UTF-8') { |f| f.puts u }
    puts "[加入] #{u}"
  end
end

#### index ####
def update_index
  dirs = Dir.glob('*').select do|d|
    File.directory?(d) and d =~ /_\d{8,}$/ and dir_files(d).any?
  end
  entries = dirs.map do|d|
    base, stamp = d.rpartition('_').values_at(0, 2)
    link = entry_link d
    [base, stamp, link]
  end.sort_by { |e| e[1] || '' }
  html = build_html entries
  File.write INDEX, html, encoding: 'UTF-8'
  puts "[索引] #{INDEX} 更新完成, 共 #{entries.size} 条"
end

def dir_files dir
  Dir.glob(File.join(dir, '*.html')) + Dir.glob(File.join(dir, '*.htm')) + Dir.glob(File.join(dir, '*.md'))
end

def entry_link dir
  fs = dir_files dir
  return '' if fs.empty?
  fs.sort_by { |f| f.end_with?('index.html') ? 0 : 1 }.first
end

def fmt_ts stamp
  return '' unless stamp =~ /^\d{8,}$/
  s = stamp[0, 14]
  "%s-%s-%s %s:%s" % [s[0, 4], s[4, 2], s[6, 2], s[8, 2], s[10, 2]]
end

def build_html entries
  rows = entries.map do|base, stamp, link|
    "<tr><td><a href=\"#{esc(link)}\">#{esc(base)}</a></td><td class=\"t\">#{fmt_ts(stamp)}</td></tr>"
  end.join("\n    ")
  <<~HTML
  <!DOCTYPE html>
  <html lang="zh-CN">
  <head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>网页镜像索引</title>
  <style>
    body{background:#0f172a;color:#e2e8f0;font-family:"Microsoft YaHei",system-ui,sans-serif;margin:0;padding:40px 24px}
    .wrap{max-width:900px;margin:0 auto}
    h1{font-size:22px;font-weight:600;border-left:4px solid #38bdf8;padding-left:12px;margin-bottom:6px}
    .sub{color:#64748b;font-size:13px;margin-bottom:24px}
    table{width:100%;border-collapse:collapse;border:1px solid #3b82f6}
    th{background:#1e3a5f;color:#e2e8f0;font-weight:600;text-align:left;padding:10px 14px;border:1px solid #3b82f6}
    td{padding:10px 14px;border:1px solid #3b82f6;color:#e2e8f0}
    tr:nth-child(even) td{background:#16223a}
    tr:hover td{background:#1e293b}
    td a{color:#38bdf8;text-decoration:none;word-break:break-all}
    td a:hover{text-decoration:underline}
    td.t{color:#94a3b8;font-size:12px;white-space:nowrap;width:150px}
    .none{color:#64748b;font-size:14px;text-align:center}
  </style>
  </head>
  <body>
  <div class="wrap">
  <h1>网页镜像索引</h1>
  <p class="sub">共 #{entries.size} 个条目 · 点击进入本地镜像</p>
  <table>
  <thead><tr><th>标题</th><th>时间</th></tr></thead>
  <tbody>
    #{entries.empty? ? '<tr><td colspan="2" class="none">暂无镜像条目</td></tr>' : rows}
  </tbody>
  </table>
  </div>
  </body>
  </html>
  HTML
end

#### 入口 ####
def main
  args = ARGV.dup
  case args[0]
  when nil
    run_todo
  when '--list'
    list_todo
  when '--add'
    add_todo args.drop(1)
  when '--md'
    args.drop(1).each { |u| do_ml u }
    update_index
  when '--help', '-h'
    usage
  else
    args.each { |u| process u }
    update_index
  end
end

# 强制提取 md (非微信页面也尝试)
def do_ml url
  url = url.strip
  return if url.empty?
  if File.file?(url)
    md_from_file url
  else
    wx_extract url
  end
end

if __FILE__ == $PROGRAM_NAME
  main()
end