def D m
  puts m if EMaily::log
end

class Array
  def / len
    a = []
    each_with_index do |x,i|
      a << [] if i % len == 0
      a.last << x
    end
    a
  end
end

module EMaily
  @@log = false
  @@status = true
  VERSION = "0.3"
  
  def self.status
    @@status
  end
  
  def self.status=(v)
    @@status=v
  end
  
  def self.log
    @@log
  end
  
  def self.log=(v)
    @@log=v
  end
    
  class Email
    def initialize(args)
      #setup
      EMaily.log = args[:log] if args[:log]
      @servers = Servers.load
      #variables
      @list = CSV.parse(args[:list])
      @attach = args[:attachment] || []
      @o_from = @from = args[:from]
      @content_type = args[:content_type] || 'text/html; charset=UTF-8;'
      @template = Template.new(args[:template], @content_type)
      @template.bidly = args[:bidly] || false
      @ports = @template.ports
      @template.site = args[:site] if args[:site]
      @subject = @template.subject || args[:subject]
      if args[:servers]
        @serv = []; args[:servers].each {|s| @serv << @servers[s][0][:values] }
        setup_server(@serv[0])
      else
        setup_server(@servers[0][0][:values])
      end
    end
    attr_accessor :list, :from, :content_type, :subject, :serv, :ports
    
    def self.start(file, &block)
      self.new(file)
      block.call(self) if block_given?
    end
        
    def send
      @list.each { |p| connect(p[:email], generate_email(p)) }
    end
    
    def send_block(bloc = 1, rest = 0, thread = false, &block) 
      threads = [] if thread == true
      (@list / bloc).each do |b|
        block.call(self) if block_given?
        if thread        
          threads << Thread.new { b.each { |p| connect p[:email], generate_email(p)}}
        else
          b.each { |p| connect p[:email], generate_email(p) }
        end
      end
      threads.each { |t| t.join }
    end

    def send_web
      @list.each { |p| connect_web(@serv[0], p[:email], generate_email(p)) }
    end

    def send_web_block(bloc = 1, rest = 0, thread = false, &block) 
      threads = [] if thread == true
      (@list / bloc).each do |b|
        block.call(self) if block_given?
        if thread        
          threads << Thread.new { b.each { |p| connect_web(@serv[0], p[:email], generate_email(p))}}
        else
          b.each { |p| connect_web(@serv[0], p[:email], generate_email(p)) }
        end
      end
      threads.each { |t| t.join }
    end
    
    def send_to_random_servers(bloc = 1, rest = 0, thread = false)
      send_block(bloc, rest, thread) { setup_server(@serv[rand(@serv.size)]) }
    end
    
    def send_to_servers(bloc = 1, rest = 0, thread = false)
      @v=0; send_block(bloc, rest, thread) do
        setup_server(@serv[@v % @serv.size]);  
        @v += 1
      end
    end
    
    private
    
    def generate_email(data)
      @template.generate_email(data)
    end
    
    def setup_server(server)
      Mail.defaults { delivery_method :smtp, server }
      if @from.nil? || (@from != server[:user_name] && server[:user_name].match(/@/))
        @from = server[:user_name]
      elsif server[:user_name].nil?
        @from = server[:reply_to]
      else
        @from = @o_from || "anonymous@#{server[:domain]}"
      end
    end
    
    def handcraft_request(url, port, ssl, request_string, email)
      begin
        if ssl
          socket = TCPSocket.new(url, port.to_i)
          ssl_context = OpenSSL::SSL::SSLContext.new()
          unless ssl_context.verify_mode
             D "warning: peer certificate won't be verified this session."
             ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          sslsocket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
          sslsocket.sync_close = true
          sslsocket.connect
          sslsocket.puts(request_string)
          @header, @response = sslsocket.gets(nil).split("\r\n\r\n")
        else
          request = TCPSocket.new(url, port.to_i)
          req = request_string
          request.print req
          @header, @response = request.gets(nil).split("\r\n\r\n")
        end
      rescue
        puts "error: #{$!}"
      end
      if @header.match(/HTTP\/1.1 200 OK/)
        D "Successfully sent #{email}\n"
      else
        D "Something went wrong. Check response ...\n"
      end
    end
    
    def connect_web(server,email, template)
      begin
        handcraft_request(server[:address], server[:port], server[:ssl], template, email)
      rescue
        D "Something went wrong sending #{email}\nError: #{$!}\n"
      end
    end
    
    def connect(email,template)
      begin
        mail = Mail.new
        mail.to email
        mail.from @from
        mail.subject @subject
        if @template.is_text?
          mail.text_part { body template }
        else
          mail.text_part do
        	  body 'This mail should be rendered or viewed as HTML'
          end
        end
        if @template.is_html?
          mail.html_part do
        	  content_type 'text/html; charset=UTF-8'
            body template
          end
        end
        @attach.each do |file|
          mail.add_file file
        end
        mail.deliver
        D "Successfully sent #{email}"
      rescue
        D "Something went wrong sending #{email}\nError: #{$!}\n"
      end
    end
  end
end
