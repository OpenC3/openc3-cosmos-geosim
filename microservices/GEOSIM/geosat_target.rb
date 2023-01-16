# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3'
require 'openc3/interfaces'
require 'openc3/tools/cmd_tlm_server/interface_thread'
require_relative 'targets/GEOSAT/lib/sim_sat'

module OpenC3
  class GeosatTarget
    class GeosatServerInterface < TcpipServerInterface
      def initialize(port)
        super(port.to_i, port.to_i, 5.0, nil, 'LENGTH', 64, 16, 11, 1, 'BIG_ENDIAN', 4, "0x1ACDFC1D", nil, true)
      end
    end

    class GeosatInterfaceThread < InterfaceThread
      def initialize(interface, sim_sat)
        super(interface)
        @sim_sat = sim_sat
      end

      protected
      def handle_packet(packet)
        identified_packet = System.commands.identify(packet.buffer, ['GEOSAT'])
        if identified_packet
          @sim_sat.write(identified_packet)
        else
          # Ignoring unknown packet
        end
      end
    end

    class GeosatTelemetryThread
      attr_reader :thread

      def initialize(interface, sim_sat)
        @sim_sat = sim_sat
        @interface = interface
        @sleeper = Sleeper.new
        @count_100hz = 0
        @next_tick_time = Time.now.sys + @sim_sat.tick_period_seconds
      end

      def start
        @thread = Thread.new do
          @stop_thread = false
          begin
            while true
              break if @stop_thread
              # Calculate time to sleep to make ticks the right distance apart
              now = Time.now.sys
              delta = @next_tick_time - now
              if delta > 0.0
                @sleeper.sleep(delta) # Sleep between packets
                break if @stop_thread
              elsif delta < -1.0
                # Fell way behind - jump next tick time
                @next_tick_time = Time.now.sys
              end

              pending_packets = @sim_sat.read(@count_100hz, @next_tick_time)
              @next_tick_time += @sim_sat.tick_period_seconds
              @count_100hz += @sim_sat.tick_increment
              pending_packets.each do |packet|
                @interface.write(packet)
              end
            end
          rescue Exception => err
            Logger.error "GeosatTelemetryThread unexpectedly died\n#{err.formatted}"
            raise err
          end
        end
      end

      def stop
        @stop_thread = true
        OpenC3.kill_thread(self, @thread)
      end

      def graceful_kill
        @sleeper.cancel
      end
    end

    def initialize(port)
      System.instance(["GEOSAT"], File.join(__dir__, "targets"))
      @sim_sat = SimSat.new('GEOSAT')
      @sim_sat.set_rates
      @interface = GeosatServerInterface.new(port)
      @interface_thread = nil
      @telemetry_thread = nil
    end

    def start
      @interface_thread = GeosatInterfaceThread.new(@interface, @sim_sat)
      @interface.target_names = ['GEOSAT']
      @interface.cmd_target_names = ['GEOSAT']
      @interface.tlm_target_names = ['GEOSAT']
      @interface_thread.start
      @telemetry_thread = GeosatTelemetryThread.new(@interface, @sim_sat)
      @telemetry_thread.start
    end

    def stop
      @telemetry_thread.stop if @telemetry_thread
      @interface_thread.stop if @interface_thread
    end

    def self.run(port)
      Logger.level = Logger::INFO
      target = self.new(port)
      begin
        target.start
        while true
          sleep 1
        end
      rescue SystemExit, SignalException
        target.stop
      end
    end
  end
end

OpenC3::GeosatTarget.run(ARGV[0]) if __FILE__ == $0
