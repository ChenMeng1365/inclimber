#coding:utf-8
# func: 网页镜像核心: 下载页面, 资源本地化(assets/), 外链保留可跳转互联网
# USE: gem install nokogiri
# CALL: WMirror.grab(url) #=> [body, 最终uri, content_type]
# CALL: WMirror.mirror(url, out_dir) #=> {title:, url:, file:}

require 'net/http'
require 'uri'
require 'openssl'
require 'fileutils'
require 'digest'
require 'nokogiri'

module WMirror
  UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

  module_function

  #### 网络 ####
  def grab url, referer = nil, depth = 0 #=> [body, 最终uri, content_type]
    uri = URI.parse url
    http = Net::HTTP.new uri.host, uri.port
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 15
    http.read_timeout = 60
    req = Net::HTTP::Get.new uri.request_uri
    req['User-Agent'] = UA
    req['Accept'] = '*/*'
    req['Referer'] = referer if referer
    res = http.request req
    case res
    when Net::HTTPSuccess
      [res.body.to_s.force_encoding('BINARY'), uri.to_s, res['content-type'].to_s]
    when Net::HTTPRedirection
      loc = URI.join(uri, res['location'].to_s).to_s rescue nil
      return [nil, uri.to_s, ''] unless loc
      return grab(loc, referer, depth + 1) if depth < 5
      [nil, uri.to_s, '']
    else
      [nil, uri.to_s, '']
    end
  rescue
    [nil, url.to_s, '']
  end

  # 相对链接拼绝对
  def abse base, rel
    URI.join(base, rel).to_s
  rescue
    rel
  end

  # 字节转 UTF-8 文本, GBK 兜底
  def to_utf8 raw
    s = raw.dup.force_encoding('UTF-8')
    return s if s.valid_encoding?
    enc = raw[0, 2048].to_s[/charset\s*=\s*["']?([\w-]+)/i, 1] || 'GBK'
    begin
      raw.dup.force_encoding(enc).encode('UTF-8')
    rescue
      raw.dup.force_encoding('BINARY').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end
  end

  # 标题清洗为合法文件夹名
  def clean_title t
    t.to_s.gsub(/[\\\/:*?"<>|\r\n]+/, '_').gsub(/\s+/, ' ').strip[0, 80].to_s
  end

  #### 资源 ####
  # CALL: ext_of(url, content_type) #=> 扩展名
  def ext_of url, ct
    t = ct.to_s.downcase
    return '.css' if t.include?('css')
    return '.js' if t.include?('javascript') or t.include?('ecmascript')
    return '.png' if t.include?('png')
    return '.jpg' if t.include?('jpeg')
    return '.gif' if t.include?('gif')
    return '.webp' if t.include?('webp')
    return '.avif' if t.include?('avif')
    return '.svg' if t.include?('svg')
    return '.woff2' if t.include?('woff2')
    return '.woff' if t.include?('woff')
    return '.ttf' if t.include?('ttf')
    return '.mp4' if t.include?('mp4')
    return '.webm' if t.include?('webm')
    File.extname(URI.parse(url).path.to_s)
  end

  # 保存资源到 out/assets, 返回相对 out 的路径, 失败 nil (带缓存)
  def save_asset url, out, referer = nil
    @cache ||= {}
    return @cache[url] if @cache[url]
    body, final, ct = grab url, referer
    return nil unless body
    ext = ext_of final, ct
    ext = '.bin' if ext.nil? or ext.empty?
    name = Digest::SHA256.hexdigest(final)[0, 12] + ext
    FileUtils.mkdir_p File.join(out, 'assets')
    File.binwrite File.join(out, 'assets', name), body
    rel = File.join 'assets', name
    @cache[url] = rel
    rel
  end

  # 拷贝本地图片到 out/assets
  def save_local src, out
    ab = File.expand_path src
    return src unless File.file?(ab)
    name = Digest::SHA256.hexdigest(ab)[0, 12] + File.extname(ab)
    FileUtils.mkdir_p File.join(out, 'assets')
    FileUtils.cp ab, File.join(out, 'assets', name)
    File.join 'assets', name
  end

  #### CSS ####
  # 改写 css 内 url(), 资源落到 assets/, 引用改相对 css 自身
  def local_css css_bin, css_uri, out
    txt = to_utf8 css_bin
    txt.gsub(/url\(\s*(['"]?)([^'")]+)\1\s*\)/i) do
      q, u = $1, $2
      if u.start_with?('data:', '#', 'about:') or u.empty?
        Regexp.last_match(0)
      else
        rel = save_asset(abse(css_uri, u), out, css_uri)
        rel ? "url(#{q}#{File.basename(rel)}#{q})" : Regexp.last_match(0)
      end
    end
  end

  #### HTML 本地化 ####
  def localize_html html_bin, base_uri, out
    doc = Nokogiri::HTML to_utf8(html_bin)
    doc.css('base').each(&:remove)

    # 外链/相对链接: 一律改绝对, 点击仍跳转互联网
    doc.css('a[href]').each do|a|
      h = a['href'].to_s.strip
      next if h.empty? or h.start_with?('#', 'javascript:', 'mailto:', 'tel:', 'data:')
      a['href'] = abse base_uri, h
    end

    # css 文件
    doc.css('link[rel="stylesheet"][href]').each do|ln|
      h = ln['href'].to_s.strip
      next if h.empty? or h.start_with?('data:')
      abs = abse base_uri, h
      body, final, ct = grab abs, base_uri
      next unless body
      css = local_css body, final, out
      name = Digest::SHA256.hexdigest(final)[0, 12] + '.css'
      FileUtils.mkdir_p File.join(out, 'assets')
      File.binwrite File.join(out, 'assets', name), css
      ln['href'] = File.join 'assets', name
    end

    # js 文件
    doc.css('script[src]').each do|s|
      h = s['src'].to_s.strip
      next if h.empty? or h.start_with?('data:')
      abs = abse base_uri, h
      body, final, ct = grab abs, base_uri
      next unless body
      ext = ext_of final, ct
      ext = '.js' if ext.nil? or ext.empty? or ext == '.bin'
      name = Digest::SHA256.hexdigest(final)[0, 12] + ext
      FileUtils.mkdir_p File.join(out, 'assets')
      File.binwrite File.join(out, 'assets', name), body
      s['src'] = File.join 'assets', name
    end

    # img: data-src(懒加载) 优先, srcset 逐项本地化
    doc.css('img').each do|im|
      src = im['data-src'].to_s
      src = im['src'].to_s if src.empty?
      src = src.strip
      if not src.empty? and not src.start_with?('data:')
        rel = save_asset abse(base_uri, src), out, base_uri
        im['src'] = rel if rel
      end
      im.delete 'data-src'
      if im['srcset']
        im['srcset'] = im['srcset'].split(',').map do|p|
          seg = p.strip.split(/\s+/)
          if seg.empty? or seg[0].start_with?('data:')
            p
          else
            r2 = save_asset(abse(base_uri, seg[0]), out, base_uri)
            r2 ? ([r2] + seg[1..-1]).join(' ') : p
          end
        end.join(', ')
      end
    end

    # 音视频
    doc.css('video[src],audio[src],source[src]').each do|v|
      h = v['src'].to_s.strip
      next if h.empty? or h.start_with?('data:')
      rel = save_asset abse(base_uri, h), out, base_uri
      v['src'] = rel if rel
    end
    doc.css('video[poster]').each do|v|
      h = v['poster'].to_s.strip
      next if h.empty?
      rel = save_asset abse(base_uri, h), out, base_uri
      v['poster'] = rel if rel
    end

    doc.to_html
  end

  #### raw 轻量本地化 ####
  # func: 微信等原始页备份: 图片落地 assets, 协议相对链接转 https, 注入表格兜底样式
  def raw_style
    '<style>table{border-collapse:collapse;width:auto;margin:8px auto}td,th{border:1px solid #7a8aa0;padding:6px 10px}th{background:#eef2f7;font-weight:600}</style>'
  end

  def localize_raw html_bin, base_uri, out
    doc = Nokogiri::HTML to_utf8(html_bin)

    # 协议相对 (//host) -> https, 本地打开 file:// 否则失效
    doc.css('a[href],link[href],script[src],img[src],img[data-src],video[src],audio[src],source[src]').each do|n|
      %w[href src data-src].each do|at|
        v = n[at]
        next unless v and v.start_with?('//')
        n[at] = 'https:' + v
      end
    end

    # 图片本地化
    doc.css('img').each do|im|
      src = im['data-src'].to_s
      src = im['src'].to_s if src.empty?
      src = src.strip
      if not src.empty? and not src.start_with?('data:')
        rel = save_asset abse(base_uri, src), out, base_uri
        im['src'] = rel if rel
      end
      im.delete 'data-src'
      if im['srcset']
        im['srcset'] = im['srcset'].split(',').map do|p|
          seg = p.strip.split(/\s+/)
          if seg.empty? or seg[0].start_with?('data:')
            p
          else
            r2 = save_asset(abse(base_uri, seg[0]), out, base_uri)
            r2 ? ([r2] + seg[1..-1]).join(' ') : p
          end
        end.join(', ')
      end
    end

    h = doc.to_html
    style = raw_style
    h.include?('</head>') ? h.sub('</head>', style + '</head>') : style + h
  end

  # 入口页文件名: 根路径 -> index.html, 其余路径转下划线拼接
  def page_name uri
    path = URI.parse(uri).path.to_s
    return 'index.html' if path.empty? or path == '/'
    n = path.split('/').reject(&:empty?).join('_')
    n = 'index.html' if n.empty?
    n = "#{n}.html" unless n.end_with?('.html', '.htm')
    n
  end

  # 下载页面并返回 [html, 最终uri, title]
  def fetch_page url
    html, murl, ct = grab url
    return nil unless html
    doc = Nokogiri::HTML to_utf8(html)
    t = doc.at_css('title')
    title = t ? t.text.strip : ''
    title = murl if title.empty?
    [html, murl, title]
  end
end