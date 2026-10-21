#coding:utf-8
# func: 微信文章转 Markdown: 正文递归提取, 图片本地化引用
# CALL: WxMd.extract(html, base_url, out_dir) #=> {title:, author:, mp:, md:}

require 'nokogiri'
require 'uri'
require 'fileutils'
require_relative 'wmirror'

module WxMd
  module_function

  # 从 HTML 提取微信文章 markdown, 图片下载到 out_dir/assets
  def extract html, base_url, out_dir
    doc = Nokogiri::HTML WMirror.to_utf8(html)
    title = pick doc, '#activity-name', '.rich_media_title', 'h1.rich_media_title', 'title'
    title = '微信文章' if title.to_s.empty?
    mp = pick doc, '#js_name', '.rich_media_meta_nickname'
    author = pick doc, '#js_author_name', '.rich_media_meta_text'
    box = doc.at_css('#js_content') || doc.at_css('.rich_media_content') || doc.at_css('.rich_media_content_with_background') || doc.at_css('.rich_media_area_primary')

    md = ''
    if box
      body = walk_w box, base_url, out_dir, base_url
      md = body.flatten.compact.reject(&:empty?).join("\n\n")
    else
      md = '!! 提取失败: 未找到正文容器 js_content / rich_media_content'
    end

    head = []
    head << "> 公众号: #{mp}" if mp and not mp.empty?
    head << "> 作者: #{author}" if author and not author.empty?
    head << "> 原文: #{base_url}"
    md = "#{head.join("\n")}\n\n#{md}" unless md.start_with?('!!')
    {title: title, author: author, mp: mp, md: md}
  end

  def pick doc, *names
    names.each do|s|
      n = doc.at_css(s)
      return n.text.strip if n and not n.text.strip.empty?
    end
    nil
  end

  # 块级节点递归 => 段落数组
  def walk_w node, base, out, ref
    return [] unless node
    node.children.map do|c|
      case c.name
      when 'p'
        t = inline_w c, base, out
        t.strip.empty? ? nil : t
      when 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'
        "#{'#' * c.name[1].to_i} #{inline_w(c, base, out)}"
      when 'img'
        pic_w c, base, out, ref
      when 'ul', 'ol'
        li = c.name == 'ol'
        c.children.map do|lc|
          next nil unless lc.name == 'li'
          head = li ? '1. ' : '- '
          head + inline_w(lc, base, out).to_s
        end
      when 'li'
        '- ' + inline_w(c, base, out).to_s
      when 'blockquote'
        walk_w(c, base, out, ref).map{|l| l.to_s.split("\n").map{|x| x.strip.empty? ? '>' : "> #{x.strip}"}.join("\n")}
      when 'section'
        if c['data-type'] == 'blockquote' or c['data-type'] == 'quote'
          walk_w(c, base, out, ref).map{|l| l.to_s.split("\n").map{|x| x.strip.empty? ? '>' : "> #{x.strip}"}.join("\n")}
        else
          walk_w c, base, out, ref
        end
      when 'table'
        '!! 表格已跳过 (微信富文本表格转 md 暂不支持)'
      when 'hr'
        '---'
      when 'text'
        t = c.text.strip
        t.empty? ? nil : t
      when 'br'
        nil
      else
        walk_w c, base, out, ref
      end
    end
  end

  # 行内递归 => 字符串
  def inline_w node, base, out
    node.children.map do|c|
      case c.name
      when 'text' then c.text
      when 'strong', 'b' then "**#{inline_w(c, base, out)}**"
      when 'em', 'i' then "*#{inline_w(c, base, out)}*"
      when 'code' then "`#{c.text}`"
      when 'a'
        href = c['href'].to_s
        href = 'javascript:void(0)' if href.empty?
        "[#{inline_w(c, base, out)}](#{href})"
      when 'img'
        pic_w c, base, out
      when 'span', 'label', 'sub', 'sup', 'font', 'u', 'del', 's', 'q'
        inline_w c, base, out
      else
        inline_w c, base, out
      end
    end.join
  end

  # 图片 => 本地化引用, 微信图片数据在 data-src
  def pic_w im, base, out
    src = im['data-src'].to_s
    src = im['src'].to_s if src.empty?
    src = src.strip
    return '' if src.empty? or src.start_with?('data:')
    src = URI::DEFAULT_PARSER.unescape src.gsub('&amp;', '&')
    rel = if src =~ %r{^https?://}
            WMirror.save_asset src, out, base
          else
            # 本地文件页面: 相对路径以源文件目录为根
            base_dir = base =~ %r{^[A-Za-z]:[\\/]} ? File.dirname(base) : nil
            ab = base_dir ? File.expand_path(src, base_dir) : File.expand_path(src)
            WMirror.save_local ab, out
          end
    rel ? "![#{im['alt'].to_s.strip}](#{rel})" : "![#{im['alt'].to_s.strip}](#{src})"
  end
end