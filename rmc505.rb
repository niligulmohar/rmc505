#! /usr/bin/env ruby

require 'logger'
require 'forwardable'
require 'yaml'
require 'observer'
require 'Korundum'
$: << File.join(File.dirname(__FILE__), 'asound')
require 'asound'

######################################################################

require 'gui'
require 'devices'

######################################################################

class String
  def hexdump
    result = ''
    each_byte do |byte|
      result += " %02x" % byte
    end
    return result
  end
end

class Snd::Seq::Event
  def v_link_off?
    sysex? and variable_data =~ /^\xf0\x41.\x00\x51\x12\x10\x00\x00\x00.\xf7$/
  end
end

######################################################################

class MidiInterface
  def initialize
    @seq = Snd::Seq.open
    @seq.client_name = 'rmc505'
    @seq.nonblocking = true

    @port = @seq.create_simple_port('Listener',
                                    Snd::Seq::PORT_CAP_READ |
                                    Snd::Seq::PORT_CAP_WRITE |
                                    Snd::Seq::PORT_CAP_SUBS_READ |
                                    Snd::Seq::PORT_CAP_SUBS_WRITE,
                                    Snd::Seq::PORT_TYPE_MIDI_GENERIC)

    @connections = []
    connect

  end

  def new_connection(&block)
    @new_connection_block = block
  end

  def connect
    @seq.each_port do |port|
      if port.midi? && (port.read_subscribable? || port.write_subscribable?)
        if port.read_subscribable?
          $logger.debug("Making subscription:  read <-- #{port.ids}")
          @port.connect_from(port)
        end
        if port.write_subscribable?
          $logger.debug("Making subscription: write --> #{port.ids}")
          @port.connect_to(port)
        end
      end
    end
  end

  def broadcast!
    ev = Snd::Seq::Event.new
    ev.source = @port
    ev.to_port_subscribers!
    ev.direct!
    yield ev
    @seq.event_output(ev)
    @seq.drain_output
  end

  def identity_request!
    broadcast! do |event|
      event.set_sysex("\xf0\x7e\x7f\x06\x01\xf7")
      $logger.debug("* <-- Identity request")
    end

    # $logger.debug('Sending fake PCR-A30 response')
    # @port.event_output! do |event|
    #   event.direct!
    #   event.set_sysex("\xf0\x7e\x10\x06\x02\x41\x62\x01\x00\x00\x01\x01\x00\x00\xf7")
    # end
    # $logger.debug('Sending fake Roland D2 response')
    # @port.event_output! do |event|
    #   event.direct!
    #   event.set_sysex("\xf0\x7e\x10\x06\x02\x41\x0b\x01\x03\x00\x00\x03\x00\x00\xf7")
    # end
  end

  def pump
    event = nil
    while (event = @seq.event_input) do
      if event.sysex?
        if event.v_link_off?
          # When this kind of message comes from a PCR-A30, it means
          # that its midi-out port has started working as an usb midi
          # interface. This is a good time to send another identity
          # request.
          identity_request!
        end
        catch :recognized do
          @connections.each do |connection|
            if connection.sysex_match?(event)
              connection.recieve_sysex(event)
              throw :recognized
            end
          end
          port = Snd::Seq::Port.new(@seq, event.source_info)
          dest_port = Snd::Seq::DestinationPort.new(port, @port)
          new_connection = DeviceClass.connection(event, dest_port)
          if new_connection
            @connections << new_connection
            @new_connection_block.call(new_connection) if @new_connection_block
            new_connection.recieve_sysex(event)
          elsif event.identity_request?
            $logger.warn("#{event.source_ids} --> Identity request recieved")
          elsif !event.v_link_off?
            $logger.warn("#{event.source_ids} --> Unrecognized %s (%d bytes):" %
                           [if event.identity_response?
                              'identity response'
                            else
                              'sysex'
                            end,
                             event.variable_data.length])
            $logger.debug("      #{event.variable_data.hexdump}")
          end
        end
      elsif not event.clock?
        $logger.debug("#{event.source_ids} --> MIDI #{event}")
      end
    end
  end
end

######################################################################

def initialize_app(logdevice_class)
  $logger = Logger.new(logdevice_class.new(STDERR))
  $logger.datetime_format = "%H:%M:%S"

  $midi = MidiInterface.new

  yield $midi

  $midi.identity_request!
end

run_gui
