require 'rubygems'
require '../lib/watirgrid'

grid = Watir::Grid.new(:ring_server_port => 12358, 
:ring_server_host => '192.168.1.102', 
:loglevel => Logger::DEBUG)
grid.start(:read_all => true)

threads = []
grid.browsers.each do |browser|
  threads << Thread.new do 
    @uuid = browser[:uuid]
    p @uuid
  end
end
threads.each {|thread| thread.join}

grid.start(:read_all => true, :uuid => @uuid)

threads = []
grid.browsers.each do |browser|
  threads << Thread.new do 
    @uuid = browser[:uuid]
    p @uuid
  end
end
threads.each {|thread| thread.join}

