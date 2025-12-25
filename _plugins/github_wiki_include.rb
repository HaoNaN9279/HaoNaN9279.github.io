require 'net/http'
require 'json'
require 'uri'

module Jekyll
  class GitHubWikiTag < Liquid::Tag
    def initialize(tag_name, text, tokens)
      super
      params = text.strip.split(',')
      @owner = params[0].strip
      @repo = params[1].strip
      @page = params[2]&.strip || 'Home'
    end

    def render(context)
      raw_content = fetch_wiki_content
      
      # 确保内容编码为 UTF-8
      raw_content = ensure_utf8(raw_content)
      
      site = context.registers[:site]
      converter = site.find_converter_instance(Jekyll::Converters::Markdown)
      converter.convert(raw_content)
    end

    private

    def fetch_wiki_content
      # GitHub Wiki 页面实际上是单独的 Git 仓库
      # API 格式：https://api.github.com/repos/:owner/:repo.wiki/:page
      
      url = "https://raw.githubusercontent.com/wiki/#{@owner}/#{@repo}/#{@page}.md"
      
      begin
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        
        request = Net::HTTP::Get.new(uri.request_uri)
        
        # 设置接受编码
        request['Accept-Charset'] = 'UTF-8'
        
        response = http.request(request)
        
        if response.code == '200'
          response.body
        else
          "无法获取 Wiki 内容 (HTTP #{response.code})"
        end
      rescue => e
        "获取 Wiki 内容时出错: #{e.message}"
      end
    end
    
    def ensure_utf8(str)
      # 如果字符串已经编码为 UTF-8，直接返回
      return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?
      
      # 尝试检测并转换编码
      begin
        # 先尝试强制转换为 UTF-8，替换无效字符
        str = str.force_encoding('UTF-8')
        unless str.valid_encoding?
          # 如果是 ASCII-8BIT (二进制)，尝试用不同编码检测
          str = str.force_encoding('ASCII-8BIT').encode('UTF-8', invalid: :replace, undef: :replace)
        end
        str
      rescue Encoding::UndefinedConversionError => e
        # 如果转换失败，使用更安全的方法
        str = str.encode('UTF-8', 'binary', invalid: :replace, undef: :replace)
        str
      end
    end
  end
end

Liquid::Template.register_tag('github_wiki', Jekyll::GitHubWikiTag)