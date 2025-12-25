require 'net/http'
require 'json'
require 'base64'

module Jekyll
  class GitHubReadmeTag < Liquid::Tag
    def initialize(tag_name, text, tokens)
      super
      params = text.split(',')
      @owner = params[0].strip
      @repo = params[1].strip
      @branch = params[2]&.strip || 'main'
    end

    def render(context)
      # 从GitHub API获取README
      url = URI("https://api.github.com/repos/#{@owner}/#{@repo}/readme?ref=#{@branch}")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(url)
      request['Accept'] = 'application/vnd.github.v3+json'
      
      begin
        response = http.request(request)
        
        if response.code == '200'
          data = JSON.parse(response.body)
          content = Base64.decode64(data['content'])
          
          # 可选：处理相对路径的图片和链接
          content = fix_relative_paths(content, data['download_url'])
          
          # 返回Markdown内容
          content
        else
          "无法获取README文件 (HTTP #{response.code})"
        end
      rescue => e
        "获取README时出错: #{e.message}"
      end
    end

    private
    
    def fix_relative_paths(content, download_url)
      # 获取基础URL
      base_url = download_url.gsub('/README.md', '')
      
      # 修复相对路径的图片
      content.gsub(/!\[(.*?)\]\((?!http)(.*?)\)/) do |match|
        alt = $1
        path = $2
        
        if path.start_with?('./')
          path = path[2..-1]
        end
        
        if !path.start_with?('http') && !path.start_with?('/')
          path = "#{base_url}/#{path}"
        end
        
        "![#{alt}](#{path})"
      end
    end
  end
end

Liquid::Template.register_tag('github_readme', Jekyll::GitHubReadmeTag)