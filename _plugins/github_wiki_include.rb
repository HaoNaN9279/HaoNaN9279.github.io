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
      # 获取原始 Markdown 内容
      raw_content = fetch_wiki_content
      
      # 使用 Jekyll 的 Markdown 转换器
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
  end
end

Liquid::Template.register_tag('github_wiki', Jekyll::GitHubWikiTag)