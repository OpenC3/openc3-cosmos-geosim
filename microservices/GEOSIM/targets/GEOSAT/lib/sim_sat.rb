# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

# Simulates the fake satellite used in COSMOS User Training

require 'openc3'

module OpenC3
  MAX_PWR_WATT_SECONDS = 100000
  INIT_PWR_WATT_SECONDS = 25000
  HYSTERESIS = 2.0

  # Simulated satellite for the training. Populates several packets and cycles
  # the telemetry to simulate a real satellite.
  class SimSat < SimulatedTarget
    def initialize(target_name)
      super(target_name)
      @target = System.targets[target_name]

      # Initialize fixed parts of packets
      packet = @tlm_packets['HEALTH_STATUS']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength = packet.buffer.length - 7

      packet = @tlm_packets['THERMAL']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength = packet.buffer.length - 7

      packet = @tlm_packets['EVENT']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength   = packet.buffer.length - 7

      @get_count = 0
      @queue = Queue.new
      @collects = 0

      # HEALTH_STATUS
      @cmd_acpt_cnt = 0
      @cmd_rjct_cnt = 0
      @mode = 'SAFE'
      @cpu_pwr = 100
      @table_data = "\x00" * 10

      # THERMAL
      @temp1 = 0
      @temp2 = 0
      @heater1_ctrl = 'ON'
      @heater1_state = 'OFF'
      @heater1_setpt = 0.0
      @heater1_pwr = 0.0
      @heater2_ctrl = 'ON'
      @heater2_state = 'OFF'
      @heater2_setpt = 0.0
      @heater2_pwr = 0.0
    end

    def set_rates
      set_rate('HEALTH_STATUS', 100)
      set_rate('THERMAL', 100)
    end

    def accept_cmd(message = nil)
      if message
        event_packet = @tlm_packets['EVENT']
        event_packet.message = message
        time = Time.now
        event_packet.timesec = time.tv_sec
        event_packet.timeus  = time.tv_usec
        event_packet.ccsdsseqcnt += 1
        @queue << event_packet.dup
      end
      @cmd_acpt_cnt += 1
    end

    def reject_cmd(message)
      event_packet = @tlm_packets['EVENT']
      event_packet.message = message
      time = Time.now
      event_packet.timesec = time.tv_sec
      event_packet.timeus  = time.tv_usec
      event_packet.ccsdsseqcnt += 1
      @queue << event_packet.dup
      @cmd_rjct_cnt += 1
    end

    def write(packet)
      name = packet.packet_name.upcase

      case name
      when 'NOOP'
        accept_cmd()

      when 'COLLECT'
        if @mode == 'OPERATE'
          @collects += 1
          @duration = packet.read('duration')
          @collect_type = packet.read("type")
          @collect_end_time = Time.now + @duration
          accept_cmd()
        else
          reject_cmd("Mode must be OPERATE to collect images")
        end

      when 'SET_MODE'
        mode = packet.read('mode')
        case mode
        when 'SAFE'
          @mode = mode
          accept_cmd()
        when 'CHECKOUT'
          @mode = mode
          accept_cmd()
        when 'OPERATE'
          @mode = mode
          accept_cmd()
        else
          reject_cmd("Invalid Mode: #{mode}")
        end

      when 'HTR_SETPT'
        num = packet.read('NUM')
        setpt = packet.read('SETPT')
        case num
        when 1
          case setpt
          when -100..100
            @heater1_setpt = setpt
            accept_cmd()
          else
            reject_cmd("Invalid Heater Setpoint: #{setpt}")
          end
        when 2
          case setpt
          when -100..100
            @heater2_setpt = setpt
            accept_cmd()
          else
            reject_cmd("Invalid Heater Setpoint: #{setpt}")
          end
        else
          reject_cmd("Invalid Heater Number: #{num}")
        end

      end
    end

    def graceful_kill
    end

    def get_pending_packets(count_100hz)
      pending_packets = super(count_100hz)
      while @queue.length > 0
        pending_packets << @queue.pop
      end
      pending_packets
    end

    def read(count_100hz, time)
      pending_packets = get_pending_packets(count_100hz)

      pending_packets.each do |packet|
        case packet.packet_name
        when 'HEALTH_STATUS'
          packet.timesec = time.tv_sec
          packet.timeus  = time.tv_usec
          packet.ccsdsseqcnt += 1

          packet.cmd_acpt_cnt = @cmd_acpt_cnt
          packet.cmd_rjct_cnt = @cmd_rjct_cnt
          packet.mode = @mode
          packet.cpu_pwr = @cpu_pwr
          packet.table_data = @table_data

        when 'THERMAL'
          packet.timesec = time.tv_sec
          packet.timeus  = time.tv_usec
          packet.ccsdsseqcnt += 1

          if @heater1_ctrl == 'ON'
            if @temp1 < (@heater1_setpt - HYSTERESIS)
              @heater1_state = 'ON'
            elsif @temp1 > (@heater1_setpt + HYSTERESIS)
              @heater1_state = 'OFF'
            end
          end

          if @heater2_ctrl == 'ON'
            if @temp2 < (@heater2_setpt - HYSTERESIS)
              @heater2_state = 'ON'
            elsif @temp2 > (@heater2_setpt + HYSTERESIS)
              @heater2_state = 'OFF'
            end
          end

          if @heater1_state == 'ON'
            @heater1_pwr = 300
            @temp1 += 0.5
            if @temp1 > 50.0
              @temp1 = 50.0
            end
          else
            @heater1_pwr = 0
            @temp1 -= 0.1
            if @temp1 < -20.0
              @temp1 = -20.0
            end
          end

          if @heater2_state == 'ON'
            @heater2_pwr = 300
            @temp2 += 0.5
            if @temp2 > 100.0
              @temp2 = 100.0
            end
          else
            @heater2_pwr = 0
            @temp2 -= 0.1
            if @temp2 < -20.0
              @temp2 = -20.0
            end
          end

          packet.heater1_ctrl = @heater1_ctrl
          packet.heater1_state = @heater1_state
          packet.heater1_setpt = @heater1_setpt
          packet.heater1_pwr = @heater1_pwr
          packet.heater2_ctrl = @heater2_ctrl
          packet.heater2_state = @heater2_state
          packet.heater2_setpt = @heater2_setpt
          packet.heater2_pwr = @heater2_pwr
          packet.temp1 = @temp1
          packet.temp2 = @temp2
        end
      end

      @get_count += 1
      pending_packets
    end
  end
end
