require 'rubygems'
require 'controller'
require 'provider'

module Watir

  ##
  # Extend Watir with a Grid class which 
  # implements a grid of browsers by connecting to a tuplespace
  # and instatiating remote browser objects on nominated providers.
  class Grid

    attr_accessor :drb_server_uri, :ring_server, :browsers

    def initialize(params = {})   
      @drb_server_host  = params[:drb_server_host]  || external_interface
      @drb_server_port  = params[:drb_server_port]  || 0
      @ring_server_host = params[:ring_server_host] || external_interface
      @ring_server_port = params[:ring_server_port] || Rinda::Ring_PORT
      @renewer = params[:renewer] || Rinda::SimpleRenewer.new

      @quantity = params[:quantity]

      logfile = params[:logfile] || STDOUT
      @log  = Logger.new(logfile, 'daily')
      @log.level = params[:loglevel] || Logger::ERROR
      @log.datetime_format = "%Y-%m-%d %H:%M:%S "   
    end

    ##
    # Start required services
    def start(params = {})
      start_drb_server
      find_ring_server
      get_tuples(params)
    end

    ##
    # Yield a browser object when iterating over the grid of browsers
    def each
      threads = []
      id = 0
      @browsers.each do |browser|
        threads << Thread.new do 
          id += 1
          yield(browser, id)
        end
      end
      threads.each {|thread| thread.join}
    end

    ##
    # Return the size (quantity) of browsers started on the grid
    def size
      @browsers.size
    end

    private

    ##
    # Get the external facing interface for this server  
    def external_interface    
      begin
        UDPSocket.open {|s| s.connect('watir.com', 1); s.addr.last }      
      rescue
        '127.0.0.1'
      end
    end

    ##
    # Start the DRb Server
    def start_drb_server
      drb_server = DRb.start_service(
        "druby://#{@drb_server_host}:#{@drb_server_port}")  
      @drb_server_uri = drb_server.uri
      @log.info("DRb server started on : #{@drb_server_uri}")
    end

    ##
    # Locate the Rinda Ring Server via a UDP broadcast
    def find_ring_server
      @ring_server = Rinda::RingFinger.new(
        @ring_server_host, @ring_server_port)
      @ring_server = @ring_server.lookup_ring_any
      @log.info("Ring server found on : druby://#{@ring_server_host}:#{@ring_server_port}")
    end

    ##
    # Get all tuple spaces on ringserver
    def get_tuples(params = {})
      quantity = params[:quantity] || -1
      architecture = params[:architecture] || nil
      browser_type = params[:browser_type] || nil
      
      @browsers = []
      services = @ring_server.read_all([
        :name,
        nil, # watir provider
        nil, # browser front object
        nil, # provider description
        nil, # hostname
        architecture,
        browser_type])

      @log.info("Found #{services.size} services.")
      if services.size > 0 then
        services[1..quantity].each do |service|
          hostname = service[4]
          if params[:hostnames] then
            if params[:hostnames][hostname] then
              @browsers << service[2].new_browser
              @ring_server.take(service)if params[:take_all] == true
            end
          else
            @browsers << service[2].new_browser
            @ring_server.take(service)if params[:take_all] == true
          end
        end
      else
        @browsers
      end
    end
  end

end

