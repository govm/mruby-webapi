class WebAPI
  CRLF = "\r\n"
  FORMCHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~"

  def initialize(url, opts={})
    @url = URL.new(url)
    @opts = opts.dup
  end

  def get resource
    req = _make_request "GET", resource, ""
    response_str = _send_request req
    Response.new(response_str)
  end

  def get_str resource
    _make_request "GET", resource, ""
  end

  def post resource, body
    req = post_str resource, body
    response_str = _send_request req
    Response.new(response_str)
  end

  def post_str resource, body
    body = WebAPI.urlencode(body) if body.is_a? Hash
    _make_request "POST", resource, body
  end

  # private
  def _make_path(resource)
    if @url.scheme == "http" and @opts[:proxy]
      path = @url.scheme + "://" + @url.authority + "/"
    else
      path = ""
    end

    if @url.path[-1] == "/" and resource[0] == "/"
      path += @url.path + resource[1, resource.size]  # remove duplicated "/"
    else
      path += @url.path + resource
    end

    path
  end

  # private
  def _make_request method, resource, body=""
    path = _make_path(resource)
    req = "#{method} #{path} HTTP/1.1" + CRLF

    h = {
      "Host" => @url.host + ":" + @url.port.to_s,
      "Connection" => "close",
      "User-Agent" => "mruby-weapi",
    }

    if body != ""
      h["Content-Type"] = @opts[:content_type] if @opts[:content_type]
      h["Content-Length"] = body.size.to_s
    end

    h.update @opts[:headers] if @opts[:headers]
    h.each { |key, val|
      req += key + ": " + val + CRLF
    }

    req + CRLF + body
  end

  # private
  def _send_request req
    sock = text = nil

    if @url.scheme == "http"
      if @opts[:proxy]
        proxy = URL.new @opts[:proxy]
        sock = TCPSocket.open proxy.host, proxy.port
      else
        sock = TCPSocket.open @url.host, @url.port
      end
    else
      tlsopts = { :port => @url.port }
      tlsopts[:certs] = @opts[:certs]
      tlsopts[:identity] = @url.host

      if @opts[:proxy]
        proxy = URL.new @opts[:proxy]
        sock = TCPSocket.open proxy.host, proxy.port
        sock.write "CONNECT #{@url.host}:#{@url.port} HTTP/1.1" + CRLF
        sock.write "Host: #{@url.host}:#{@url.port}" + CRLF
        sock.write CRLF
        sock.flush

        resp = ""
        resp += sock.recv(100) until resp.include? CRLF+CRLF

        tls = TLS.new sock, tlsopts
      else
        tls = TLS.new @url.host, tlsopts
      end
    end

    sock.write req
    text = sock.read
    sock.close
    text
  end

  def self.urldecode(str)
    def unescape(s)
      HEXA = "0123456789ABCDEFabcdef"
      i = 0
      t = ""
      while i < s.size
        if s[i] == "%"
          if i + 2 < s.size and HEXA.include?(s[i+1]) and HEXA.include?(s[i+2])
            t += s[i+1..i+2].to_i(16).chr
            i += 2
          else
            raise "invalid percent sequence in URL encoded string"
          end
        elsif s[i] == "+"
          t += " "
        else
          t += s[i]
        end
        i += 1
      end
      t
    end

    str.split("&").map { |entry|
      key, val = entry.split("=", 2)
      [ unescape(key), unescape(val) ]
    }
  end

  def self.urlencode(h)
    def escape(s)
      t = ""
      s.each_char { |ch|
        if FORMCHARS.include?(ch)
          t += ch
        elsif ch == " "
          t += "+"
        else
          t += format("%%%02X", ch.getbyte(0))
        end
      }
      t
    end

    if h.is_a? String
      escape(h)
    else
      str = ""
      h.each { |key, val|
        str += "&" unless str == ""
        str += escape(key.to_s) + "=" + escape(val.to_s)
      }
      str
    end
  end

  class Response
    attr_reader :http_version
    attr_reader :code
    attr_reader :message
    attr_reader :content_type
    attr_reader :body

    def initialize(text)
      @str = text
      status_line, str = text.split(CRLF, 2)

      @http_version, @code, @message = status_line.split(" ", 3)

      i = (str || "").index(CRLF + CRLF)
      if i 
        i += (CRLF+CRLF).size
        @body = str[i, text.size]
      else
        @body = ""
      end
    end

    def to_s
      @str
    end
  end

  class URL
    @@defaultports = { "http" => 80, "https" => 443 }

    attr_reader :scheme, :authority, :host, :port, :path

    def initialize(str)
      scheme, str = str.split("://", 2)
      @scheme = scheme.downcase

      @authority, path = str.split("/", 2)

      # userinfo is not supported
      #userinfo, host = authority.split("@", 2)

      @host, @port = @authority.split(":", 2)
      unless @port
        # default port number is defined for each scheme
        @port = @@defaultports[@scheme]
        raise InvalidURIError, "port must be specified" unless @port
      end

      unless host
        host = userinfo
        userinfo = nil
      end
      
      if @authority.include? "@"
      else
        @userinfo = nil
      end

      # path == nil : without leading /
      if path == nil
        @path = ""
      else
        @path = "/" + path
      end
    end
  end

  class Error < StandardError; end
  class InvalidURIError < Error; end
  class ResponseError < Error; end
end
