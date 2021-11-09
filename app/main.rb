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

# Resources is a container class that represents the tree of all HTTP requestable resources that this webserver has.
# It has capabilities to add resources dynamically.
class Resources
  # Constructs a resource tree containing all of the subfiles of the given directory.
  # If no argument is supplied, then instead create an empty resource tree.
  # @param top_level_directory - the root directory for the resource tree (can be nil)
  def initialize(top_level_directory)
    @resources =
      if top_level_directory.nil?
        {}
      else
        discover_file_paths(top_level_directory)
      end
  end

  # Registers the given resource to the given path. This will overwrite any resource that is
  # already bound to that path.
  # @param path - The String path to that is to be routed to the resource
  # @param resource - resource is expected to conform to <code>Resource</code>'s interface
  def register_resource(path, resource)
    @resources[path] = resource
  end

  # Returns the resource that the given String routes too. This method does not check that the
  # result actually exists.
  # @param path - the requested path
  # @return the associated resource, can be nil
  def [](path)
    # Just pass the [] call to the underlying Hash.
    @resources[path]
  end

  private

  # Given a directory, this method creates a Hash containing every file contained within this directory and its
  # children. The created Hash maps the relative path of a file with a prepended '/' to its corresponding FileResource
  # which this method also creates. This method does not add sub-directories as indexable resources, only files.
  # @param top_level_directory - the directory whose files will be mapped to FileResources
  # @return a Hash containing /relative_address => FileResource pairs.
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

# Resource is an abstract class that represents the interface that resources are expected to conform to.
# It is advised to override this class when creating new Resource types, rather than relying on duck-typing.
class Resource

  # The binary data that this resource represents. This interface requires that calling this method does
  # not change the value returned by mime. However, subsequent calls to get_data may return different results.
  # @param _query - a String that contains the query at the end of a URL, the format of this String is definable by the
  # overriding method, further, this query can be ignored, the caller is also allowed to pass a nil string, which is to
  # be treated as there being no query. It is up to implementation whether the empty String and nil are to be treated
  # equivalently
  # @return The binary data that this resource represents.
  def get_data(_query); end

  # This returns the MIME type of the data gotten by get_data. This interface requires that
  # calling get_data <strong>does not</strong> change the value returned by mime. Calling
  # mime multiple times in a row, regardless of intervening time, each call must return the
  # same value.
  # @param _extension_to_mime - a Hash mapping file extensions (including preceding .) to mime types. This is a field
  # that may or may not be used by implementations, however it must be passed by the caller.
  # @return the mime type of the data as a String.
  def mime(_extension_to_mime); end

end

class FileResource < Resource

  def initialize(file)
    super()
    @file = file
  end

  def get_data(_query)
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
  '.xml' => 'text/xml',
  '.js' => 'text/html'
}
resources = Resources.new Dir.open '../public'

get_handler = GetRequestHandler.new(extension_to_mime, resources)
server = HTTPServer.new 8585
server.register_request_handler('GET', get_handler)
server.start_accept_loop false
