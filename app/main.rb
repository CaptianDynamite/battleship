require 'socket'

class HTTPServer
  def initialize(port)
    @server = TCPServer.new port
    @request_handlers = {}
  end

  def register_request_handler(request_type, handler)
    @request_handlers[request_type] = handler
  end

  def start_accept_loop(create_thread)
    if create_thread
      Thread.start do
        accept_loop
      end
    else
      accept_loop
    end
  end

  private

  def accept_loop
    loop do
      Thread.start(@server.accept) do |connection|
        method, path, query = split_request connection.gets
        response = @request_handlers[method].request(path, query)

        puts "#{[method, path, query]}\n#{response[0]}" # Debug statement

        put_http_response(connection, response)
      end
    end
  end

  def put_http_response(connection, response)
    status, headers, body = response
    connection.print "HTTP/1.1 #{status}\r\n"
    headers.each do |key, value|
      connection.print "#{key}: #{value}\r\n"
    end
    connection.print "\r\n"
    connection.write body
    connection.close
  end

  def split_request(request)
    method, full_path = request.split(' ')
    path, query = full_path.split('?')
    [method, path, query]
  end
end

class GetRequestHandler
  def initialize(extension_to_mime, resources)
    @extension_to_mime = extension_to_mime
    @resources = resources
  end

  def register_file_path
    puts 'not implemented'
  end

  def request(path, query)
    resource = @resources[path]
    mime = resource.mime(@extension_to_mime)
    if mime.nil?
      response = '404'
      headers = {}
      contents = []
    else
      response = '200'
      headers = { 'ContentType' => mime }
      contents = resource.get_data(query)
    end

    [response, headers, contents]
  end
end

class Resources
  def initialize(top_level_directory)
    @resources = discover_file_paths(top_level_directory)
  end

  def register_resource(path, resource)
    @resources[path] = resource
  end

  def [](path)
    @resources[path]
  end

  private

  def discover_file_paths(top_level_directory)
    # Route / to /index.html so no special processing has to be done at request time
    path = top_level_directory.to_path
    resources = { '/' => FileResource.new("#{path}/index.html") }
    # This is done so that the current working directory can be restored
    pwd = Dir.pwd
    # Recursively find all files in top_level_directory
    Dir.chdir top_level_directory
    file_paths = Dir.glob('**/**')
    # Route the URLs to their corresponding FileResources, excluding directories
    file_paths.each do |file|
      resources["/#{file}"] = FileResource.new "#{path}/#{file}" unless File.directory? file
    end
    # Restore previous working directory - no side effects!
    Dir.chdir pwd
    resources
  end
end

class Resource

  def initialize; end

  def get_data(_query); end

  def mime(_extension_to_mime); end

end

class FileResource < Resource

  def initialize(file)
    super()
    @file = file
  end

  def get_data(query)
    file = File.open @file
    data = file.binmode.read
    file.close
    data
  end

  def mime(extension_to_mime)
    file = File.open @file
    extension = File.extname(file)
    file.close
    extension_to_mime[extension]
  end

  def to_s
    @file
  end

end

extension_to_mime = {
  '.html' => 'text/html',
  '.png' => 'image/png',
  '.svg' => 'image/svg',
  '.webmanifest' => 'text/json',
  '.xml' => 'text/xml'
}
resources = Resources.new Dir.open '../public'

get_handler = GetRequestHandler.new(extension_to_mime, resources)
server = HTTPServer.new 8585
server.register_request_handler('GET', get_handler)
server.start_accept_loop false
