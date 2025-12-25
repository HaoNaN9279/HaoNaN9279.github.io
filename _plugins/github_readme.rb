require 'net/http'
require 'json'
require 'base64'
require 'time'

module Jekyll
  class GitHubReadmeTag < Liquid::Tag
    CACHE_DIR = File.expand_path('../../.github_cache', __dir__)
    
    def initialize(tag_name, text, tokens)
      super
      params = text.split(',')
      @owner = params[0].strip
      @repo = params[1].strip
      @branch = params[2]&.strip || 'main'
    end
    
    def render(context)
      # 尝试从缓存读取
      cached_content = read_from_cache
      return cached_content if cached_content
      
      # 获取内容
      content = fetch_from_github(context)
      
      # 缓存内容
      cache_content(content) unless content.start_with?('错误')
      
      content
    end
    
    private
    
    def fetch_from_github(context)
      url = URI("https://api.github.com/repos/#{@owner}/#{@repo}/readme")
      url.query = URI.encode_www_form(ref: @branch)
      
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.read_timeout = 30
      http.open_timeout = 30
      
      request = Net::HTTP::Get.new(url)
      request['User-Agent'] = 'Jekyll-Site/1.0'
      request['Accept'] = 'application/vnd.github.v3+json'
      request['Accept-Charset'] = 'utf-8'
      
      # 获取token
      token = get_github_token(context)
      request['Authorization'] = "token #{token}" if token
      
      begin
        response = http.request(request)
        
        case response.code.to_i
        when 200
          process_success_response(response)
        when 403
          process_rate_limit_response(response)
        when 404
          "仓库或README文件未找到: #{@owner}/#{@repo}"
        else
          "GitHub API错误: HTTP #{response.code} - #{response.message}"
        end
      rescue Net::OpenTimeout, Net::ReadTimeout
        "请求GitHub API超时，请稍后重试"
      rescue => e
        "获取README时出错: #{e.message}"
      end
    end
    
    def get_github_token(context)
      # 1. 检查环境变量
      return ENV['GITHUB_TOKEN'] if ENV['GITHUB_TOKEN']
      
      # 2. 检查Jekyll配置
      site = context.registers[:site]
      config = site.config
      if config['github'] && config['github']['token']
        return config['github']['token']
      end
      
      nil
    end
    
    def process_success_response(response)
      data = JSON.parse(response.body)
      
      # 解码内容
      content = Base64.decode64(data['content'])
      
      # 编码处理
      content = content.force_encoding('UTF-8')
      unless content.valid_encoding?
        content = content.encode('UTF-8', invalid: :replace, undef: :replace)
      end
      
      # 清理BOM（如果有）
      content = content.sub("\xEF\xBB\xBF".force_encoding('UTF-8'), '')
      
      # 修复相对路径
      base_url = "https://raw.githubusercontent.com/#{@owner}/#{@repo}/#{@branch}"
      content = fix_relative_paths(content, base_url)
      
      # 可选：添加仓库信息头
      header = "---\n**来源：**[#{@owner}/#{@repo}](https://github.com/#{@owner}/#{@repo})\n\n---\n\n"
      header + content
    end
    
    def process_rate_limit_response(response)
      remaining = response['X-RateLimit-Remaining'] || '0'
      limit = response['X-RateLimit-Limit'] || '60'
      reset_time = response['X-RateLimit-Reset']
      
      if remaining == '0' && reset_time
        reset_at = Time.at(reset_time.to_i)
        time_until_reset = distance_of_time_in_words(Time.now, reset_at)
        return "GitHub API 速率限制已超（#{limit} 次/小时）。请在 #{time_until_reset} 后重试。"
      end
      
      "HTTP 403: 访问被拒绝。请检查仓库权限或添加GitHub Token。"
    end
    
    def fix_relative_paths(content, base_url)
      # 修复图片路径
      content.gsub!(/!\[([^\]]*)\]\((?!http|\/)([^)]+)\)/) do |match|
        alt_text = $1
        path = $2
        
        # 处理相对路径
        if path.start_with?('./')
          path = path[2..-1]
        end
        
        "![#{alt_text}](#{base_url}/#{path})"
      end
      
      # 修复相对链接（可选）
      content.gsub!(/\[([^\]]+)\]\((?!http|\/|#)([^)]+)\)/) do |match|
        link_text = $1
        path = $2
        
        # 如果是相对路径的链接，可以转换为GitHub仓库的链接
        if path.end_with?('.md')
          "**#{link_text}** (链接已移除，请访问 [GitHub仓库](https://github.com/#{@owner}/#{@repo}) 查看完整文档)"
        else
          match
        end
      end
      
      content
    end
    
    def distance_of_time_in_words(from_time, to_time)
      minutes = ((to_time - from_time) / 60).round
      hours = (minutes / 60).round
      
      if minutes < 60
        "#{minutes}分钟"
      else
        "#{hours}小时"
      end
    end
    
    def cache_key
      "#{@owner}_#{@repo}_#{@branch}".gsub(/[^a-zA-Z0-9_]/, '_')
    end
    
    def read_from_cache
      return nil unless Dir.exist?(CACHE_DIR)
      
      cache_file = File.join(CACHE_DIR, "#{cache_key}.md")
      return nil unless File.exist?(cache_file)
      
      # 检查缓存是否过期（1小时）
      return nil if Time.now - File.mtime(cache_file) > 3600
      
      File.read(cache_file, encoding: 'UTF-8')
    rescue
      nil
    end
    
    def cache_content(content)
      FileUtils.mkdir_p(CACHE_DIR)
      cache_file = File.join(CACHE_DIR, "#{cache_key}.md")
      File.write(cache_file, content, encoding: 'UTF-8')
    end
  end
end

Liquid::Template.register_tag('github_readme', Jekyll::GitHubReadmeTag)