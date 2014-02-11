#!/usr/bin/env ruby
require_relative "core.rb"

require 'rubame'
require 'edn'

require_relative "sonicpi/scsynth"
require_relative "sonicpi/studio"
require_relative "sonicpi/spider"
require_relative "sonicpi/server"
require_relative "sonicpi/util"
require_relative "sonicpi/rcv_dispatch"

include SonicPi::Util

ws_out = Queue.new
$scsynth = SonicPi::SCSynth.instance

at_exit do
  puts "Exiting - shutting down scsynth server..."
  $scsynth.shutdown
end

$c = OSC::Client.new("localhost", 4556)
$c.send(OSC::Message.new("/d_loadDir", synthdef_path))
sleep 2

$sp =  SonicPi::Spider.new "localhost", 4556, ws_out, 5

$rd = SonicPi::RcvDispatch.new($sp, ws_out)
$clients = []

# Send stuff out from Sonic Pi jobs out to GUI
Thread.new do
  loop do
    begin
      message = ws_out.pop
      if debug_mode
        raise "message not a Hash!" unless message.is_a? Hash
      end
      message[:ts] = Time.now.strftime("%H:%M:%S")

      if debug_mode
        puts "sending:"
        puts "#{message.to_edn}"
        puts "---"
      end
      $clients.each{|c| c.send(message.to_edn)}
    rescue Exception => e
      puts e.message
      puts e.backtrace.inspect
    end
  end
end

# Receive events from the GUI to Sonic Pi (potentially creating new jobs)
server = Rubame::Server.new("0.0.0.0", 25252)

while true
  server.run do |client|
    client.onopen do
      client.send({:type => :message, :val => "Connection initiated..."}.to_edn)
      $clients << client
      puts "New Websocket Client: \n#{client.frame} \n #{client.socket} \n"

    end
    client.onmessage do |msg|
      puts "====> #{msg}" if debug_mode
      $rd.dispatch EDN.read(msg)
    end
    client.onclose do
      $clients.delete client
      warn("Connection closed...")
    end
  end
end