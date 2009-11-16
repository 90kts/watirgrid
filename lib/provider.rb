#!/usr/bin/env ruby 
# provider.rb
# Rinda Ring Provider

require 'rubygems'
require 'rinda/ring'
require 'rinda/tuplespace'
require 'logger'
require 'optparse'
require 'drb/acl'

begin
    require 'watir'
rescue LoadError
end

begin
    require 'safariwatir'
rescue LoadError
end

begin
    require 'firewatir'
    include FireWatir
rescue LoadError
end

module Watir
  
  ##
  # Extend Watir with a Provider class
  # to determine which browser type is supported by the 
  # remote DRb process. This returns the DRb front object.
  class Provider

    include DRbUndumped # all objects will be proxied, not copied

    attr_reader :browser

    def initialize(browser = nil)
      browser = (browser || 'tmp').downcase.to_sym  
      case browser
        when :safari
          @browser = Watir::Safari
        when :firefox
          @browser = FireWatir::Firefox 
        when :ie
          @browser = Watir::IE
        else
          @browser = find_supported_browser
      end    
    end

    def find_supported_browser
      if Watir::Safari then return Watir::Safari end
      if Watir::IE then return Watir::IE end
      if FireWatir::Firefox then return FireWatir::Firefox end
    end

    def new_browser   
      if @browser.nil?
        find_supported_browser.new
      else
        @browser.new
      end 
    end 

  end

end

class Provider

  attr_accessor :drb_server_uri, :ring_server_uri

  def initialize(params = {})   
    @drb_server_host  = params[:drb_server_host]  || external_interface
    @drb_server_port  = params[:drb_server_port]  || 0
    @ring_server_host = params[:ring_server_host] || external_interface
    @ring_server_port = params[:ring_server_port] || Rinda::Ring_PORT

    @renewer = params[:renewer] || Rinda::SimpleRenewer.new
    @browser_type = params[:browser_type] || nil

    logfile = params[:logfile] || STDOUT
    @log  = Logger.new(logfile, 'daily')
    @log.level = params[:loglevel] || Logger::INFO
    @log.datetime_format = "%Y-%m-%d %H:%M:%S "   

    @log.debug("DRB Server Port #{@drb_server_port}\nRing Server Port #{@ring_server_port}")
  end  

  ##
  # Start providing watir objects on the ring server  
  def start
    # create a DRb 'front' object
    watir_provider = Watir::Provider.new(@browser_type)
    architecture = Config::CONFIG['arch']
    hostname = ENV['SERVER_NAME'] || %x{hostname}.strip

    # setup the security--remember to call before DRb.start_service()
    DRb.install_acl(ACL.new(@acls))

    # start the DRb Server
    drb_server = DRb.start_service(
      "druby://#{@drb_server_host}:#{@drb_server_port}")  

    # obtain DRb Server uri
    @drb_server_uri = drb_server.uri
    @log.info("DRb server started on : #{@drb_server_uri}")

    # create a service tuple
    @tuple = [
                :name, 
                :WatirProvider, 
                watir_provider, 
                'A watir provider', 
                hostname,
                architecture,
                @browser_type
              ]   

    # locate the Rinda Ring Server via a UDP broadcast
    @log.debug("Attempting to find ring server on : druby://#{@ring_server_host}:#{@ring_server_port}")
    ring_server = Rinda::RingFinger.new(@ring_server_host, @ring_server_port)
    ring_server = ring_server.lookup_ring_any
    @log.info("Ring server found on  : druby://#{@ring_server_host}:#{@ring_server_port}")

    # advertise this service on the primary remote tuple space
    ring_server.write(@tuple, @renewer)

    # log DRb server uri
    @log.info("New tuple registered  : druby://#{@ring_server_host}:#{@ring_server_port}")

    # wait for explicit stop via ctrl-c
    DRb.thread.join if __FILE__ == $0  
  end

  ##
  # Stop the provider by shutting down the DRb service
  def stop    
    DRb.stop_service
    @log.info("DRb server stopped on : #{@drb_server_uri}")    
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

end

